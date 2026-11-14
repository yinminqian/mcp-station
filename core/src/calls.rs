//! 调用记录：每次 tools/call（客户端经网关调的，或界面里的"试调用"）一条。内存里留最近 3000 条，
//! 磁盘上 calls.jsonl 一行一条、只追加。只留最近 3 天（和日志一样），启动时和之后每小时整理一次。
//! 也认 App 里旧的 Swift 网关写的行（Swift 的 Codable 格式），历史记录不丢。

use crate::paths;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::io::Write;
use std::sync::Mutex;

const KEEP: usize = 3000;

pub struct Calls {
    ring: Mutex<(VecDeque<Value>, u64)>,
}

pub struct NewCall<'a> {
    pub mcp: &'a str,
    pub tool: &'a str,
    /// default / named / single / test
    pub route: &'a str,
    pub service: Option<&'a str>,
    pub client: &'a str,
    pub ms: u64,
    pub error: Option<String>,
}

impl Calls {
    pub fn load() -> Self {
        let text = std::fs::read_to_string(paths::calls()).unwrap_or_default();
        let lines: Vec<&str> = text.lines().filter(|l| !l.trim().is_empty()).collect();
        let ring: VecDeque<Value> = lines.iter().rev().take(KEEP).rev().filter_map(|l| parse_line(l)).collect();
        let next = ring.iter().filter_map(|c| c["id"].as_u64()).max().unwrap_or(0) + 1;
        let me = Self { ring: Mutex::new((ring, next)) };
        me.prune();
        me
    }

    /// 丢掉 3 天前的记录，重写文件（只留内存里那些）。
    pub fn prune(&self) {
        let cutoff = crate::upstream::now() - crate::logfile::KEEP.as_secs_f64();
        let mut g = self.ring.lock().unwrap();
        g.0.retain(|c| c["t"].as_f64().unwrap_or(0.0) >= cutoff);
        let body: String = g.0.iter().map(|c| format!("{c}\n")).collect();
        let _ = crate::config::write_atomic(&paths::calls(), body.as_bytes());
    }

    pub fn record(&self, c: NewCall) -> Value {
        let mut g = self.ring.lock().unwrap();
        let id = g.1;
        g.1 += 1;
        let first_line = c.error.map(|e| e.lines().next().unwrap_or("出错").chars().take(200).collect::<String>());
        let v = json!({
            "id": id, "t": crate::upstream::now(), "mcp": c.mcp, "tool": c.tool, "route": c.route,
            "service": c.service, "client": c.client, "ms": c.ms, "error": first_line,
        });
        if g.0.len() == KEEP {
            g.0.pop_front();
        }
        g.0.push_back(v.clone());
        drop(g);
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(paths::calls()) {
            let _ = writeln!(f, "{v}");
        }
        crate::platform::restrict(&paths::calls());
        v
    }

    pub fn recent(&self, after: u64, limit: usize) -> Vec<Value> {
        let g = self.ring.lock().unwrap();
        let mut out: Vec<Value> = g.0.iter().filter(|c| c["id"].as_u64().unwrap_or(0) > after).cloned().collect();
        if out.len() > limit {
            out.drain(..out.len() - limit);
        }
        out
    }
}

/// 一行记录：内核自己的格式原样用；Swift 旧格式（time 是 2001 年起的秒数，service 是中文）转过来。
fn parse_line(line: &str) -> Option<Value> {
    let v: Value = serde_json::from_str(line).ok()?;
    if v.get("route").is_some() {
        return Some(v);
    }
    let t = v.get("time")?.as_f64()? + 978_307_200.0;
    let service = v.get("service").and_then(Value::as_str).unwrap_or("");
    let (route, svc) = match service {
        "默认" => ("default", None),
        "试调用" => ("test", None),
        "单独地址" => ("single", None),
        s => ("named", Some(s)),
    };
    // Swift 的 Duration 编码成 [秒, 阿秒]
    let ms = v.get("duration").and_then(Value::as_array).map_or(0, |d| {
        d.first().and_then(Value::as_i64).unwrap_or(0) as u64 * 1000 + d.get(1).and_then(Value::as_i64).unwrap_or(0) as u64 / 1_000_000_000_000_000
    });
    let error = v.pointer("/outcome/error/_0").and_then(Value::as_str);
    Some(json!({
        "id": v.get("id")?, "t": t, "mcp": v.get("mcp")?, "tool": v.get("tool")?, "route": route, "service": svc,
        "client": v.get("client").and_then(Value::as_str).unwrap_or("未知客户端"), "ms": ms, "error": error,
    }))
}

#[cfg(test)]
mod tests {
    #[test]
    fn 认swift旧格式() {
        let v = super::parse_line(r#"{"id":3,"time":784900000.5,"mcp":"iterm","tool":"read","service":"默认","client":"d2","duration":[1,250000000000000000],"outcome":{"ok":{}}}"#).unwrap();
        assert_eq!(v["route"], "default");
        assert_eq!(v["ms"], 1250);
        assert!(v["error"].is_null());
        let e = super::parse_line(r#"{"id":4,"time":1,"mcp":"a","tool":"b","service":"ios","client":"c","outcome":{"error":{"_0":"坏了"}}}"#).unwrap();
        assert_eq!(e["service"], "ios");
        assert_eq!(e["error"], "坏了");
    }
}
