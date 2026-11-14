//! runtime.json：内核此刻在哪个端口、控制接口的令牌。启动时写、正常退出时删，只有自己能读。
//! 界面（Swift，以后的 Windows 界面）读它来连控制接口。

use crate::paths;
use serde_json::json;

pub fn new_token() -> String {
    format!("{}{}", uuid::Uuid::new_v4().simple(), uuid::Uuid::new_v4().simple())
}

pub fn write(port: u16, control_port: u16, token: &str, started_at: f64) {
    let v = json!({
        "pid": std::process::id(),
        "version": crate::VERSION,
        "api": crate::control::API_VERSION,
        "port": port,
        "controlPort": control_port,
        "token": token,
        "startedAt": started_at,
    });
    let _ = crate::config::write_atomic(&paths::runtime(), serde_json::to_string_pretty(&v).unwrap().as_bytes());
}

pub fn update_port(port: u16) {
    let Ok(raw) = std::fs::read(paths::runtime()) else { return };
    let Ok(mut v) = serde_json::from_slice::<serde_json::Value>(&raw) else { return };
    v["port"] = json!(port);
    let _ = crate::config::write_atomic(&paths::runtime(), serde_json::to_string_pretty(&v).unwrap().as_bytes());
}

pub fn remove() {
    let _ = std::fs::remove_file(paths::runtime());
}
