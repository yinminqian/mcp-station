//! Windows：这次只写到能编译。以后要做的：用 Job Object 管子进程（替代 taskkill 和 children.json）、
//! 用任务计划或 HKCU\…\Run 自启、二进制加 `#![windows_subsystem = "windows"]`、进程表和端口占用。

use super::Proc;
use std::path::{Path, PathBuf};

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
    let _ = std::process::Command::new("taskkill").args(["/T", "/F", "/PID", &pid.to_string()]).output();
}

pub fn alive(_pid: u32) -> bool {
    false
}

pub fn restrict(_path: &Path) {}

pub fn port_owner(_port: u16) -> Option<String> {
    None
}

pub fn process_table() -> Vec<Proc> {
    Vec::new()
}

pub async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
