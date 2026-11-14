//! children.json：内核起的子进程（每个都是自己进程组的组长）。内核被强杀、被 launchd 重启时子进程不会跟着死，
//! 下次启动先把还活着的旧进程组清掉，再起新的，免得同一个 MCP 跑两份。
//!
//! 怎么确认"还是那个进程"（防 pid 被复用后误杀）：pid 还在、它仍是自己进程组的组长、父进程已经变成 1（原来的内核没了）。

use crate::paths;
use crate::platform;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[derive(Serialize, Deserialize, Clone)]
struct Child {
    name: String,
    pid: u32,
    cmd: String,
}

static LIST: Mutex<Vec<Child>> = Mutex::new(Vec::new());

fn save(list: &[Child]) {
    if let Ok(data) = serde_json::to_vec_pretty(list) {
        let _ = crate::config::write_atomic(&paths::children(), &data);
    }
}

pub fn add(name: &str, pid: u32, cmd: &str) {
    let mut l = LIST.lock().unwrap();
    l.push(Child { name: name.into(), pid, cmd: cmd.into() });
    save(&l);
}

pub fn remove(pid: u32) {
    let mut l = LIST.lock().unwrap();
    l.retain(|c| c.pid != pid);
    save(&l);
}

/// 启动时调用：清掉上一个内核留下的子进程组。
pub fn reap_stale() {
    let Ok(raw) = std::fs::read(paths::children()) else { return };
    let old: Vec<Child> = serde_json::from_slice(&raw).unwrap_or_default();
    if old.is_empty() {
        return;
    }
    let table = platform::process_table();
    for c in old {
        let Some(p) = table.iter().find(|p| p.pid == c.pid) else { continue };
        if p.pgid == c.pid && p.ppid == 1 {
            tracing::warn!(mcp = %c.name, pid = c.pid, "清掉上一个内核留下的子进程组");
            platform::terminate_tree(c.pid);
            std::thread::sleep(std::time::Duration::from_millis(300));
            if platform::alive(c.pid) {
                platform::kill_tree(c.pid);
            }
        }
    }
    save(&[]);
}
