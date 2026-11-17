//! 平台相关的事情都在这里：数据目录、子进程（进程组、杀进程树）、登录 shell 的 PATH、进程表、自启。
//! 业务代码里不出现 `#[cfg]`。Windows 这次只保证能编译，具体实现留了位置。

#[cfg(unix)]
mod unix;
#[cfg(unix)]
pub use unix::*;

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use windows::*;

#[cfg(target_os = "macos")]
mod launchd;
#[cfg(target_os = "macos")]
pub use launchd::{install, service_status, uninstall};

#[cfg(not(target_os = "macos"))]
pub fn install(_restart: bool) -> Result<serde_json::Value, String> {
    Err("这个平台还不支持自启安装".into())
}
#[cfg(not(target_os = "macos"))]
pub fn uninstall() -> Result<serde_json::Value, String> {
    Err("这个平台还不支持自启安装".into())
}
#[cfg(not(target_os = "macos"))]
pub fn service_status() -> serde_json::Value {
    serde_json::json!({ "installed": false, "supported": false })
}

/// 一个进程：pid、父 pid、进程组、常驻内存（字节）。
#[derive(Debug, Clone)]
pub struct Proc {
    pub pid: u32,
    pub ppid: u32,
    #[cfg_attr(windows, allow(dead_code))]
    pub pgid: u32,
    pub rss: u64,
}

/// 以 `root` 为根的进程树里所有进程的常驻内存之和。npx / uvx 起的 MCP 真正干活的是子进程，只量根会少算。
pub fn tree_rss(table: &[Proc], root: u32) -> Option<u64> {
    if !table.iter().any(|p| p.pid == root) {
        return None;
    }
    let mut total = 0;
    let mut stack = vec![root];
    while let Some(pid) = stack.pop() {
        for p in table {
            if p.pid == pid {
                total += p.rss;
            }
            if p.ppid == pid && p.pid != pid {
                stack.push(p.pid);
            }
        }
    }
    Some(total)
}
