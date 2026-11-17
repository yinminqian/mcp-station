use super::Proc;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

pub fn default_data_dir() -> PathBuf {
    if cfg!(target_os = "macos") {
        home_dir().join("Library/Application Support/MCP Station")
    } else {
        home_dir().join(".local/share/mcp-station")
    }
}

/// 子进程默认只拿到这些环境变量（再加全局 env 和它自己的 env）。内核自己的环境不整个传下去：
/// 子进程是第三方代码，有的工具会把环境变量原样返回给调用者。代理变量也不在里面（mcp-rust 里有，这里去掉）。
pub const BASE_ENV: &[&str] = &[
    "PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "LC_CTYPE", "TZ", "TMPDIR",
    "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
    "npm_config_registry", "NPM_CONFIG_REGISTRY", "npm_config_cache", "NPM_CONFIG_CACHE",
    "UV_INDEX_URL", "UV_DEFAULT_INDEX", "UV_CACHE_DIR", "UV_TOOL_DIR", "UV_TOOL_BIN_DIR", "UV_PYTHON_INSTALL_DIR",
    "PIP_INDEX_URL", "XDG_CACHE_HOME", "XDG_DATA_HOME",
];

/// 从用户的登录 shell 读一次 PATH。launchd 和图形界面拿到的 PATH 很短，没有 Homebrew、nvm，npx / uvx 都找不到。
pub async fn login_path() -> Option<String> {
    let shell = std::env::var("SHELL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| {
        if cfg!(target_os = "macos") { "/bin/zsh".into() } else { "/bin/sh".into() }
    });
    let out = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        tokio::process::Command::new(shell)
            .args(["-ilc", "printf '\\n__MCPSTATION_PATH__%s' \"$PATH\""])
            .stdin(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .output(),
    )
    .await
    .ok()?
    .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let path = text.rsplit("__MCPSTATION_PATH__").next()?.trim().to_string();
    (!path.is_empty() && text.contains("__MCPSTATION_PATH__")).then_some(path)
}

/// 按 PATH 找可执行文件。命令里带 `/` 的直接看那个文件。
pub fn find_program(cmd: &str, path: &str) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    let ok = |p: &Path| p.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0);
    if cmd.contains('/') {
        let p = PathBuf::from(cmd);
        return ok(&p).then_some(p);
    }
    path.split(':').filter(|d| !d.is_empty()).map(|d| Path::new(d).join(cmd)).find(|p| ok(p))
}

/// 子进程放进自己的进程组：杀的时候能连同 npx / uv 留下的孙子进程一起杀掉。
pub fn prepare_child(cmd: &mut tokio::process::Command) {
    cmd.process_group(0);
}

pub fn terminate_tree(pid: u32) {
    let _ = nix::sys::signal::killpg(nix::unistd::Pid::from_raw(pid as i32), nix::sys::signal::Signal::SIGTERM);
}

pub fn kill_tree(pid: u32) {
    let _ = nix::sys::signal::killpg(nix::unistd::Pid::from_raw(pid as i32), nix::sys::signal::Signal::SIGKILL);
}

pub fn alive(pid: u32) -> bool {
    nix::sys::signal::kill(nix::unistd::Pid::from_raw(pid as i32), None).is_ok()
}

/// 上一个内核留下的子进程组还在：组长还活着、已经被 init 收养（父进程，也就是上一个内核，已经不在了）。
pub fn is_stale_child(table: &[super::Proc], pid: u32, _cmd: &str) -> bool {
    table.iter().any(|p| p.pid == pid && p.pgid == pid && p.ppid == 1)
}

/// 只有自己能读写（配置里有密钥，runtime.json 里有控制令牌）。
pub fn restrict(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

/// 谁在监听这个端口（网关端口被占时告诉用户是谁）。
pub fn port_owner(port: u16) -> Option<String> {
    let out = StdCommand::new("lsof").args(["-nP", &format!("-iTCP:{port}"), "-sTCP:LISTEN", "-Fpc"]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let pid = text.lines().find_map(|l| l.strip_prefix('p'))?.to_string();
    let name = text.lines().find_map(|l| l.strip_prefix('c')).unwrap_or("进程");
    Some(format!("{name}（pid {pid}）"))
}

/// 全部进程的 pid / 父 pid / 进程组 / 常驻内存。一次 `ps`，几十毫秒。
pub fn process_table() -> Vec<Proc> {
    let Ok(out) = StdCommand::new("/bin/ps").args(["-A", "-o", "pid=,ppid=,pgid=,rss="]).output() else {
        return Vec::new();
    };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| {
            let mut f = l.split_whitespace();
            Some(Proc {
                pid: f.next()?.parse().ok()?,
                ppid: f.next()?.parse().ok()?,
                pgid: f.next()?.parse().ok()?,
                rss: f.next()?.parse::<u64>().ok()? * 1024,
            })
        })
        .collect()
}

pub async fn shutdown_signal() {
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("SIGTERM");
    tokio::select! {
        _ = term.recv() => {}
        _ = tokio::signal::ctrl_c() => {}
    }
}
