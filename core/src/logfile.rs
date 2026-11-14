//! 内核日志：logs/core-<日期>.log，一天一个文件，只留最近 3 天（用户 2026-11-14 定的），更早的整个删掉。
//! 启动时清一次，之后每小时清一次。launchd.log 只接日志初始化之前的崩溃输出，超过 50MB 就清空。

use crate::paths;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const KEEP: Duration = Duration::from_secs(3 * 24 * 3600);
const LAUNCHD_LOG_MAX: u64 = 50 * 1024 * 1024;

/// UTC 日期 YYYY-MM-DD（不为这一个用途引日期库）。
fn today() -> String {
    let days = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() / 86400) as i64;
    // Howard Hinnant 的 civil_from_days
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[derive(Clone, Default)]
pub struct Daily(Arc<Mutex<Option<(String, File)>>>);

impl Write for Daily {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let mut g = self.0.lock().unwrap();
        let day = today();
        if g.as_ref().is_none_or(|(d, _)| *d != day) {
            let _ = std::fs::create_dir_all(paths::logs_dir());
            let f = OpenOptions::new().create(true).append(true).open(paths::logs_dir().join(format!("core-{day}.log")))?;
            *g = Some((day, f));
        }
        g.as_mut().unwrap().1.write(buf)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self.0.lock().unwrap().as_mut() {
            Some((_, f)) => f.flush(),
            None => Ok(()),
        }
    }
}

fn core_logs() -> Vec<PathBuf> {
    let Ok(rd) = std::fs::read_dir(paths::logs_dir()) else { return Vec::new() };
    let mut v: Vec<PathBuf> = rd
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("core") && n.ends_with(".log")))
        .collect();
    v.sort();
    v
}

/// 最新的那个日志文件（界面"内核没起来"时显示末尾几行）。
pub fn latest() -> Option<PathBuf> {
    core_logs().pop()
}

pub fn prune() {
    let now = SystemTime::now();
    for p in core_logs() {
        let old = p.metadata().and_then(|m| m.modified()).is_ok_and(|t| now.duration_since(t).unwrap_or_default() > KEEP);
        if old {
            let _ = std::fs::remove_file(&p);
        }
    }
    let launchd = paths::logs_dir().join("launchd.log");
    if launchd.metadata().is_ok_and(|m| m.len() > LAUNCHD_LOG_MAX) {
        let _ = OpenOptions::new().write(true).truncate(true).open(launchd);
    }
}
