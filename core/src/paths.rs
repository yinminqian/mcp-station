//! 数据目录下各文件的位置。开发时用环境变量 `MCPSTATION_HOME=<目录>` 指到别处（Swift 端也认这个变量）。

use std::path::PathBuf;

pub fn data_dir() -> PathBuf {
    match std::env::var_os("MCPSTATION_HOME") {
        Some(p) if !p.is_empty() => PathBuf::from(p),
        _ => crate::platform::default_data_dir(),
    }
}

/// 是不是开发用的数据目录（LaunchAgent 的 Label 要加 `.dev`，免得和正式的撞）。
pub fn is_dev() -> bool {
    std::env::var_os("MCPSTATION_HOME").is_some_and(|p| !p.is_empty())
}

pub fn config() -> PathBuf { data_dir().join("config.json") }
pub fn config_backup() -> PathBuf { data_dir().join("config.json.bak") }
pub fn runtime() -> PathBuf { data_dir().join("runtime.json") }
pub fn children() -> PathBuf { data_dir().join("children.json") }
pub fn sessions() -> PathBuf { data_dir().join("sessions.json") }
pub fn calls() -> PathBuf { data_dir().join("calls.jsonl") }
pub fn lock() -> PathBuf { data_dir().join("core.lock") }
pub fn logs_dir() -> PathBuf { data_dir().join("logs") }
pub fn bin_dir() -> PathBuf { data_dir().join("bin") }
