//! config.json：唯一的配置来源，只由内核读写（界面通过控制接口改）。格式见 docs/ARCHITECTURE.md §4，和 Swift 端一致。
//!
//! - `mcps` 每一项沿用 Claude 的 `command/args/env` 与 `url/headers`，本软件自己的字段放在 `x` 里；
//! - 每个 MCP 条目单独解析：坏了一项只把那一项标成配置错误，文件原样保留；
//! - 不认识的字段原样保留（各层都有 `extra` 兜住），手写的内容不会被改丢；
//! - 写入先写临时文件再 rename；每次成功读取后备份一份，整个文件坏了时用备份运行，并拒绝一切写入。

use crate::paths;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

pub const DEFAULT_PORT: u16 = 8090;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ConfigFile {
    #[serde(default = "one")]
    pub version: u32,
    #[serde(default = "default_port")]
    pub port: u16,
    /// 全局环境变量，每个 MCP 都能用 `${名字}` 引用。
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    /// 原样存 JSON，用时再解析成 `McpEntry`（见模块说明）。
    #[serde(default)]
    pub mcps: BTreeMap<String, Value>,
    #[serde(default)]
    pub services: BTreeMap<String, ServiceEntry>,
    /// 额外放行的 Host（内置 localhost、127.0.0.1、host.docker.internal）。
    #[serde(default, rename = "allowedHosts", skip_serializing_if = "Vec::is_empty")]
    pub allowed_hosts: Vec<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

fn one() -> u32 { 1 }
fn default_port() -> u16 { DEFAULT_PORT }

impl Default for ConfigFile {
    fn default() -> Self {
        Self { version: 1, port: DEFAULT_PORT, env: BTreeMap::new(), mcps: BTreeMap::new(), services: BTreeMap::new(),
               allowed_hosts: Vec::new(), extra: Map::new() }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct ServiceEntry {
    #[serde(default)]
    pub mcps: Vec<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct McpEntry {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub args: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub env: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub headers: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub x: Option<Extra>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Extra {
    /// 是否加入默认服务。没写就是加入。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<bool>,
    /// HTTP 上游用自签证书时，信任这个 CA 证书（PEM 或 DER，支持 `~`）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ca_cert: Option<String>,
    /// 聚合地址里工具名的前缀，默认用 MCP 的名字。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alias: Option<String>,
    /// 调用超时（秒），默认 600。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl McpEntry {
    pub fn parse(v: &Value) -> Result<Self, String> {
        let e: McpEntry = serde_json::from_value(v.clone()).map_err(|e| format!("定义写得不对：{e}"))?;
        if e.command.is_none() && e.url.is_none() {
            return Err("既没有 command 也没有 url".into());
        }
        Ok(e)
    }

    pub fn is_default(&self) -> bool {
        self.x.as_ref().and_then(|x| x.default).unwrap_or(true)
    }

    pub fn set_default(&mut self, on: bool) {
        let mut x = self.x.take().unwrap_or_default();
        x.default = if on { None } else { Some(false) };
        self.x = (x != Extra::default()).then_some(x);
    }
}

impl ConfigFile {
    pub fn entry(&self, name: &str) -> Option<Result<McpEntry, String>> {
        self.mcps.get(name).map(McpEntry::parse)
    }

    pub fn set_entry(&mut self, name: &str, e: &McpEntry) {
        self.mcps.insert(name.to_string(), serde_json::to_value(e).unwrap_or(Value::Null));
    }

    /// 被默认服务或任一命名服务用到（docs/ARCHITECTURE.md §1：被引用才运行）。
    pub fn is_referenced(&self, name: &str) -> bool {
        self.entry(name).and_then(Result::ok).is_some_and(|e| e.is_default())
            || self.services.values().any(|s| s.mcps.iter().any(|m| m == name))
    }
}

pub struct Loaded {
    pub cfg: ConfigFile,
    /// 整个文件读不了时的原因。这时用备份（或空配置）运行，并拒绝一切写入，免得覆盖用户的文件。
    pub error: Option<String>,
}

pub fn load() -> Loaded {
    let path = paths::config();
    let raw = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Loaded { cfg: ConfigFile::default(), error: None },
        Err(e) => return fallback(format!("{}：{e}", path.display())),
    };
    match serde_json::from_slice::<ConfigFile>(&raw) {
        Ok(cfg) => {
            let _ = std::fs::write(paths::config_backup(), &raw);
            crate::platform::restrict(&paths::config_backup());
            Loaded { cfg, error: None }
        }
        Err(e) => fallback(format!("{}：{e}", path.display())),
    }
}

fn fallback(why: String) -> Loaded {
    let cfg = std::fs::read(paths::config_backup())
        .ok()
        .and_then(|b| serde_json::from_slice::<ConfigFile>(&b).ok())
        .unwrap_or_default();
    Loaded { cfg, error: Some(why) }
}

pub fn load_port() -> u16 {
    std::fs::read(paths::config())
        .ok()
        .and_then(|b| serde_json::from_slice::<ConfigFile>(&b).ok())
        .map_or(DEFAULT_PORT, |c| c.port)
}

pub fn save(cfg: &ConfigFile) -> Result<(), String> {
    let data = serde_json::to_vec_pretty(cfg).map_err(|e| e.to_string())?;
    write_atomic(&paths::config(), &data)
}

pub fn write_atomic(path: &std::path::Path, data: &[u8]) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    std::fs::write(&tmp, data).map_err(|e| format!("写 {} 失败：{e}", tmp.display()))?;
    crate::platform::restrict(&tmp);
    std::fs::rename(&tmp, path).map_err(|e| format!("替换 {} 失败：{e}", path.display()))
}

/// 把 `${NAME}` 换成变量的值。找不到这个变量就报错（返回变量名），由调用方把这个 MCP 标成配置错误。
pub fn expand(s: &str, lookup: &dyn Fn(&str) -> Option<String>) -> Result<String, String> {
    if !s.contains("${") {
        return Ok(s.to_string());
    }
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find("${") {
        let Some(end) = rest[start + 2..].find('}') else { break };
        out.push_str(&rest[..start]);
        let name = &rest[start + 2..start + 2 + end];
        out.push_str(&lookup(name).ok_or_else(|| name.to_string())?);
        rest = &rest[start + 2 + end + 1..];
    }
    out.push_str(rest);
    Ok(out)
}

/// 名字会出现在地址里（/servers/<名字>/mcp、/s/<名字>/mcp），只允许字母、数字、- 和 _（大小写都行）。
pub fn is_valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 64 && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub struct Imported {
    pub mcps: BTreeMap<String, McpEntry>,
    pub services: BTreeMap<String, ServiceEntry>,
    pub env: BTreeMap<String, String>,
}

/// 认这几种 JSON：本软件的 config.json（`mcps`）；Claude Code / Claude Desktop / Cursor 等的 `mcpServers`；VS Code 的 `servers`。
/// 每一项认 `command + args + env` 或 `url + headers`，其余字段忽略，`description` 记成备注。
pub fn parse_import(data: &[u8]) -> Result<Imported, String> {
    let root: Value = serde_json::from_slice(data).map_err(|e| format!("不是合法的 JSON：{e}"))?;
    let root = root.as_object().ok_or("最外层不是 JSON 对象")?;
    let ours = root.contains_key("mcps");
    let table = ["mcps", "mcpServers", "servers"]
        .iter()
        .find_map(|k| root.get(*k).and_then(Value::as_object))
        .ok_or("没有找到 mcps、mcpServers 或 servers")?;
    let strings = |v: Option<&Value>| -> Option<BTreeMap<String, String>> {
        let m: BTreeMap<String, String> = v?.as_object()?.iter().filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_string()))).collect();
        (!m.is_empty()).then_some(m)
    };
    let mut mcps = BTreeMap::new();
    for (name, item) in table {
        let Some(item) = item.as_object() else { continue };
        let mut e = McpEntry {
            command: item.get("command").and_then(Value::as_str).map(str::to_string),
            args: item.get("args").and_then(Value::as_array).map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect()),
            env: strings(item.get("env")),
            url: item.get("url").or_else(|| item.get("serverUrl")).and_then(Value::as_str).map(str::to_string),
            headers: strings(item.get("headers")),
            ..Default::default()
        };
        if ours {
            e.x = item.get("x").and_then(|x| serde_json::from_value(x.clone()).ok());
        }
        if let Some(note) = item.get("description").and_then(Value::as_str).filter(|s| !s.is_empty()) {
            e.x.get_or_insert_with(Extra::default).notes = Some(note.to_string());
        }
        if e.command.is_some() || e.url.is_some() {
            mcps.insert(name.clone(), e);
        }
    }
    if mcps.is_empty() {
        return Err("里面没有可导入的 MCP（每一项要有 command 或 url）".into());
    }
    let services = if ours {
        root.get("services").and_then(|s| serde_json::from_value(s.clone()).ok()).unwrap_or_default()
    } else {
        BTreeMap::new()
    };
    let env = if ours { strings(root.get("env")).unwrap_or_default() } else { BTreeMap::new() };
    Ok(Imported { mcps, services, env })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 展开变量_缺了报变量名() {
        let look = |k: &str| (k == "A").then(|| "1".to_string());
        assert_eq!(expand("x${A}y", &look).unwrap(), "x1y");
        assert_eq!(expand("${B}", &look).unwrap_err(), "B");
        assert_eq!(expand("no vars", &look).unwrap(), "no vars");
    }

    #[test]
    fn 导入认三种格式() {
        let a = parse_import(r#"{"mcpServers":{"fs":{"command":"npx","args":["-y","x"],"description":"文件"}}}"#.as_bytes()).unwrap();
        assert_eq!(a.mcps["fs"].x.as_ref().unwrap().notes.as_deref(), Some("文件"));
        let b = parse_import(br#"{"servers":{"r":{"url":"http://h/mcp","headers":{"A":"b"}}}}"#).unwrap();
        assert_eq!(b.mcps["r"].url.as_deref(), Some("http://h/mcp"));
        let c = parse_import(br#"{"mcps":{"m":{"command":"c","x":{"default":false}}},"services":{"s":{"mcps":["m"]}},"env":{"K":"V"}}"#).unwrap();
        assert!(!c.mcps["m"].is_default());
        assert_eq!(c.services["s"].mcps, vec!["m"]);
        assert_eq!(c.env["K"], "V");
        assert!(parse_import(br#"{"mcpServers":{}}"#).is_err());
    }

    #[test]
    fn 名字规则() {
        assert!(is_valid_name("XcodeBuildMCP") && is_valid_name("mongodb-log") && is_valid_name("a_b"));
        assert!(!is_valid_name("a b") && !is_valid_name("") && !is_valid_name("中文"));
    }

    #[test]
    fn 未知字段原样保留() {
        let v: ConfigFile = serde_json::from_str(r#"{"port":8091,"mine":1,"mcps":{"a":{"command":"c","foo":2,"x":{"bar":3}}}}"#).unwrap();
        let back = serde_json::to_value(&v).unwrap();
        assert_eq!(back["mine"], 1);
        let e = v.entry("a").unwrap().unwrap();
        assert_eq!(serde_json::to_value(&e).unwrap()["foo"], 2);
        assert_eq!(serde_json::to_value(&e).unwrap()["x"]["bar"], 3);
    }
}
