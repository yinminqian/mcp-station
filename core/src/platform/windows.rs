//! Windows：进程表（内存采样、清理上次留下的子进程）、端口占用、存活检查都已实现。
//! 还没做的：用 Job Object 管子进程（替代 taskkill 和 children.json）、用任务计划或 HKCU\…\Run 自启、
//! 二进制加 `#![windows_subsystem = "windows"]`。现在由 Windows 版 App 负责拉起内核。

use super::Proc;
use std::path::{Path, PathBuf};
use windows_sys::Win32::Foundation::{CloseHandle, INVALID_HANDLE_VALUE, WAIT_TIMEOUT};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS};
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
use windows_sys::Win32::System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_SYNCHRONIZE};

pub fn home_dir() -> PathBuf {
    std::env::var_os("USERPROFILE").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("C:\\"))
}

pub fn default_data_dir() -> PathBuf {
    std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(home_dir).join("MCP Station")
}

pub const BASE_ENV: &[&str] = &[
    "PATH", "PATHEXT", "SystemRoot", "SystemDrive", "ComSpec", "APPDATA", "LOCALAPPDATA", "USERPROFILE",
    "USERNAME", "TEMP", "TMP", "ProgramFiles", "ProgramData",
];

pub async fn login_path() -> Option<String> {
    None
}

/// Windows 上 `npx` 实际是 `npx.cmd`，要按 PATHEXT 找。
pub fn find_program(cmd: &str, path: &str) -> Option<PathBuf> {
    let exts: Vec<String> = std::env::var("PATHEXT").unwrap_or(".EXE;.CMD;.BAT".into()).split(';').map(str::to_string).collect();
    let try_one = |base: PathBuf| -> Option<PathBuf> {
        if base.is_file() {
            return Some(base);
        }
        exts.iter().map(|e| PathBuf::from(format!("{}{e}", base.display()))).find(|p| p.is_file())
    };
    if cmd.contains('\\') || cmd.contains('/') {
        return try_one(PathBuf::from(cmd));
    }
    path.split(';').filter(|d| !d.is_empty()).find_map(|d| try_one(Path::new(d).join(cmd)))
}

pub fn prepare_child(cmd: &mut tokio::process::Command) {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    cmd.creation_flags(CREATE_NO_WINDOW);
}

pub fn terminate_tree(pid: u32) {
    kill_tree(pid);
}

pub fn kill_tree(pid: u32) {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    use std::os::windows::process::CommandExt;
    let _ = std::process::Command::new("taskkill")
        .args(["/T", "/F", "/PID", &pid.to_string()])
        .creation_flags(CREATE_NO_WINDOW)
        .output();
}

/// 进程还在不在：能打开、并且没有退出。
pub fn alive(pid: u32) -> bool {
    // SAFETY: OpenProcess 失败返回空句柄；成功的句柄在下面关掉。
    unsafe {
        let h = OpenProcess(PROCESS_SYNCHRONIZE, 0, pid);
        if h.is_null() {
            return false;
        }
        let running = WaitForSingleObject(h, 0) == WAIT_TIMEOUT;
        CloseHandle(h);
        running
    }
}

/// 只有自己能读写。Windows 上 %LOCALAPPDATA% 默认就只有本人（和管理员）能访问，这里不再收紧 ACL。
pub fn restrict(_path: &Path) {}

/// 谁在监听这个端口（网关端口被占时告诉用户是谁）。用 `netstat -ano` 找到 pid，再查进程名。
pub fn port_owner(port: u16) -> Option<String> {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    use std::os::windows::process::CommandExt;
    let out = std::process::Command::new("netstat").args(["-ano", "-p", "TCP"]).creation_flags(CREATE_NO_WINDOW).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let suffix = format!(":{port}");
    let pid: u32 = text.lines().find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        // 协议  本地地址  外部地址  状态  PID（状态一列是本地化的，按列数和地址判断，不比字面）
        (f.len() == 5 && f[1].ends_with(&suffix) && (f[2].ends_with(":0") || f[2].ends_with(":*"))).then(|| f[4].parse().ok()).flatten()
    })?;
    let name = snapshot().into_iter().find(|p| p.0 == pid).map(|p| p.2).unwrap_or_else(|| "进程".into());
    Some(format!("{name}（pid {pid}）"))
}

/// 全部进程的 pid / 父 pid / 常驻内存（工作集）。Windows 没有进程组，pgid 填 pid 自己。
///
/// 父 pid 指向的进程已经不在时（父进程退了，孤儿），ppid 记成 1，和 Unix 上被 init 收养的写法一致，
/// 这样 `children::reap_stale` 的判断两边通用。打不开的进程（系统进程、别的用户的）内存记 0。
pub fn process_table() -> Vec<Proc> {
    let snap = snapshot();
    let pids: std::collections::HashSet<u32> = snap.iter().map(|p| p.0).collect();
    snap.iter()
        .map(|&(pid, ppid, _)| Proc {
            pid,
            ppid: if ppid != 0 && pids.contains(&ppid) { ppid } else { 1 },
            pgid: pid,
            rss: working_set(pid).unwrap_or(0),
        })
        .collect()
}

/// 上一个内核留下的子进程是不是还在、并且确实是它（pid 会被复用：名字也要对得上）。
pub fn is_stale_child(table: &[Proc], pid: u32, cmd: &str) -> bool {
    let Some(p) = table.iter().find(|p| p.pid == pid) else { return false };
    if p.ppid != 1 {
        return false;
    }
    let want = Path::new(cmd).file_stem().map(|s| s.to_string_lossy().to_lowercase()).unwrap_or_default();
    snapshot().into_iter().any(|(id, _, name)| {
        id == pid && Path::new(&name).file_stem().map(|s| s.to_string_lossy().to_lowercase()).unwrap_or_default() == want
    })
}

/// (pid, 父 pid, exe 名)
fn snapshot() -> Vec<(u32, u32, String)> {
    let mut out = Vec::with_capacity(512);
    // SAFETY: 快照句柄在函数结束前关掉；PROCESSENTRY32W 按要求先填 dwSize。
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap == INVALID_HANDLE_VALUE {
            return out;
        }
        let mut e: PROCESSENTRY32W = std::mem::zeroed();
        e.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut ok = Process32FirstW(snap, &mut e) != 0;
        while ok {
            let len = e.szExeFile.iter().position(|&c| c == 0).unwrap_or(e.szExeFile.len());
            out.push((e.th32ProcessID, e.th32ParentProcessID, String::from_utf16_lossy(&e.szExeFile[..len])));
            ok = Process32NextW(snap, &mut e) != 0;
        }
        CloseHandle(snap);
    }
    out
}

fn working_set(pid: u32) -> Option<u64> {
    // SAFETY: 打开失败返回空句柄；成功的句柄在下面关掉。
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() {
            return None;
        }
        let mut c: PROCESS_MEMORY_COUNTERS = std::mem::zeroed();
        c.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
        let ok = K32GetProcessMemoryInfo(h, &mut c, c.cb) != 0;
        CloseHandle(h);
        ok.then_some(c.WorkingSetSize as u64)
    }
}

pub async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
