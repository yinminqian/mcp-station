//! 注册表：配置、正在运行的上游、客户端会话、内存采样，都在这里。网关（northbound / router）和控制接口（control）只通过它读写。
//!
//! 生命周期规则（docs/ARCHITECTURE.md §1）：一个 MCP 被默认服务或任一命名服务用到才运行。配置一变就 `reconcile`：
//! 多出来的停掉、新用到的启动、定义（或全局环境变量）变了的重启——这是 mcp-rust catalog 的 reload 语义。
//!
//! 和 mcp-rust 的 registry 不同：那里是全局的"slug__工具名"表加 glob 规则，表达不了"单个 MCP 的地址不加前缀"和别名前缀，
//! 所以路由改成按地址（Route）算成员，每个成员带自己的前缀。

use crate::calls::Calls;
use crate::config::{self, ConfigFile, McpEntry};
use crate::events::{Event, Events};
use crate::jsonrpc::{Id, Message};
use crate::upstream::{self, Catalog, Inbound, State, UpstreamHandle};
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};
use tokio_util::sync::CancellationToken;

/// 客户端连的是哪个地址。
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "name", rename_all = "lowercase")]
pub enum Route {
    /// `/mcp`：所有开关打开的 MCP，工具名加 `<名字>__` 前缀。
    Default,
    /// `/s/<服务>/mcp`：自己挑的几个 MCP，也加前缀。
    Named(String),
    /// `/servers/<名字>/mcp`：只有它自己，不加前缀（和单独连这个 MCP 一模一样）。
    Single(String),
}

impl Route {
    pub fn kind(&self) -> &'static str {
        match self {
            Route::Default => "default",
            Route::Named(_) => "named",
            Route::Single(_) => "single",
        }
    }
    pub fn service(&self) -> Option<&str> {
        match self {
            Route::Named(n) => Some(n),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Member {
    pub name: String,
    pub prefix: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SessionInfo {
    pub client: String,
    pub route: Route,
}

struct Up {
    fingerprint: String,
    handle: UpstreamHandle,
    stop: CancellationToken,
}

pub struct Gateway {
    pub port: u16,
    /// 网关端口起不来的原因（被别的程序占着之类）。这时控制接口照常可用，界面能显示原因、能改端口。
    pub error: Option<String>,
}

pub struct Registry {
    cfg: RwLock<ConfigFile>,
    config_error: RwLock<Option<String>>,
    ups: RwLock<BTreeMap<String, Up>>,
    pub sessions: DashMap<String, SessionInfo>,
    pub events: Events,
    pub calls: Calls,
    pub gateway: Mutex<Gateway>,
    port_tx: tokio::sync::watch::Sender<u16>,
    memory: Mutex<(Option<u64>, HashMap<String, u64>)>,
    login_path: Option<String>,
    shutdown: CancellationToken,
    pub started_at: f64,
}

impl Registry {
    pub fn new(loaded: config::Loaded, login_path: Option<String>, shutdown: CancellationToken) -> (Arc<Self>, tokio::sync::watch::Receiver<u16>) {
        let port = loaded.cfg.port;
        let (port_tx, port_rx) = tokio::sync::watch::channel(port);
        let sessions: Vec<(String, SessionInfo)> = std::fs::read(crate::paths::sessions())
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        let reg = Arc::new(Self {
            cfg: RwLock::new(loaded.cfg),
            config_error: RwLock::new(loaded.error),
            ups: RwLock::new(BTreeMap::new()),
            sessions: sessions.into_iter().collect(),
            events: Events::new(),
            calls: Calls::load(),
            gateway: Mutex::new(Gateway { port, error: None }),
            port_tx,
            memory: Mutex::new((None, HashMap::new())),
            login_path,
            shutdown,
            started_at: upstream::now(),
        });
        (reg, port_rx)
    }

    pub fn config(&self) -> ConfigFile {
        self.cfg.read().unwrap().clone()
    }

    pub fn config_error(&self) -> Option<String> {
        self.config_error.read().unwrap().clone()
    }

    pub fn handle(&self, name: &str) -> Option<UpstreamHandle> {
        self.ups.read().unwrap().get(name).map(|u| u.handle.clone())
    }

    // ── 生命周期 ────────────────────────────────────────────────

    /// 按配置启停上游（见模块说明）。
    pub fn reconcile(self: &Arc<Self>) {
        let cfg = self.config();
        let global = serde_json::to_string(&cfg.env).unwrap_or_default();
        let desired: BTreeMap<String, (McpEntry, String)> = cfg
            .mcps
            .keys()
            .filter(|n| cfg.is_referenced(n))
            .filter_map(|n| {
                let e = cfg.entry(n)?.ok()?;
                let fp = format!("{}{}", serde_json::to_string(&e).unwrap_or_default(), global);
                Some((n.clone(), (e, fp)))
            })
            .collect();

        let mut ups = self.ups.write().unwrap();
        let stale: Vec<String> = ups
            .iter()
            .filter(|(n, u)| desired.get(*n).is_none_or(|(_, fp)| *fp != u.fingerprint))
            .map(|(n, _)| n.clone())
            .collect();
        for n in stale {
            if let Some(u) = ups.remove(&n) {
                tracing::info!(mcp = %n, "停止");
                u.stop.cancel();
            }
            self.events.emit(Event::Mcp(n));
        }
        for (n, (entry, fp)) in desired {
            if ups.contains_key(&n) {
                continue;
            }
            tracing::info!(mcp = %n, "启动");
            let stop = self.shutdown.child_token();
            let spec = upstream::Spec { name: Arc::from(n.as_str()), entry, global_env: cfg.env.clone(), login_path: self.login_path.clone() };
            let handle = upstream::spawn(spec, self.events.clone(), stop.clone());
            self.watch(&handle, stop.clone());
            ups.insert(n.clone(), Up { fingerprint: fp, handle, stop });
            self.events.emit(Event::Mcp(n));
        }
    }

    /// 上游说清单变了（tools/prompts/resources 的 list_changed）：重新拉一遍。
    fn watch(self: &Arc<Self>, h: &UpstreamHandle, stop: CancellationToken) {
        let mut rx = h.subscribe();
        let h = h.clone();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = stop.cancelled() => return,
                    m = rx.recv() => match m {
                        Ok(Inbound::Notification(m)) if m.method_str().ends_with("list_changed") => {
                            tracing::info!(mcp = %h.name, method = %m.method_str(), "上游清单变了，重新拉取");
                            if let Some(c) = refetch(&h).await {
                                h.shared.set_catalog(c);
                            }
                        }
                        Ok(_) => {}
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                        Err(_) => return,
                    }
                }
            }
        });
    }

    // ── 路由 ──────────────────────────────────────────────────

    /// 这个地址有哪些成员。None 表示地址不存在（404）。
    pub fn members(&self, route: &Route) -> Option<Vec<Member>> {
        let cfg = self.cfg.read().unwrap();
        let prefixed = |n: &String| {
            let alias = cfg.entry(n).and_then(Result::ok).and_then(|e| e.x.and_then(|x| x.alias)).unwrap_or_else(|| n.clone());
            Member { name: n.clone(), prefix: format!("{alias}__") }
        };
        match route {
            Route::Default => Some(cfg.mcps.keys().filter(|n| cfg.entry(n).and_then(Result::ok).is_some_and(|e| e.is_default())).map(prefixed).collect()),
            Route::Named(s) => Some(cfg.services.get(s)?.mcps.iter().filter(|n| cfg.mcps.contains_key(*n)).map(prefixed).collect()),
            Route::Single(n) => cfg.mcps.contains_key(n).then(|| vec![Member { name: n.clone(), prefix: String::new() }]),
        }
    }

    /// 带前缀的名字（工具 / prompt）属于哪个成员，原名是什么。前缀最长的先匹配，免得 `a__` 抢了 `a_b__` 的。
    pub fn resolve(members: &[Member], exposed: &str) -> Option<(Member, String)> {
        let mut m: Vec<&Member> = members.iter().collect();
        m.sort_by_key(|x| std::cmp::Reverse(x.prefix.len()));
        m.into_iter().find(|x| exposed.starts_with(&x.prefix)).map(|x| (x.clone(), exposed[x.prefix.len()..].to_string()))
    }

    /// 等成员都启动完（没有"启动中"的），最多等 `max`。内核刚重启时客户端立刻来要清单，等一下给完整的，而不是空的。
    pub async fn wait_settled(&self, members: &[Member], max: Duration) {
        let deadline = Instant::now() + max;
        while Instant::now() < deadline {
            let starting = members.iter().any(|m| self.handle(&m.name).is_some_and(|h| h.shared.state() == State::Starting));
            if !starting {
                return;
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
    }

    pub fn catalog(&self, name: &str) -> Option<(Catalog, upstream::Status)> {
        let h = self.handle(name)?;
        let st = h.status();
        Some((st.catalog.clone(), st))
    }

    // ── 会话 ──────────────────────────────────────────────────

    pub fn session_open(&self, id: String, info: SessionInfo) {
        self.sessions.insert(id, info);
        self.sessions_changed();
    }

    pub fn session_close(&self, id: &str) {
        if self.sessions.remove(id).is_some() {
            self.sessions_changed();
        }
    }

    fn sessions_changed(&self) {
        let all: Vec<(String, SessionInfo)> = self.sessions.iter().map(|e| (e.key().clone(), e.value().clone())).collect();
        if let Ok(data) = serde_json::to_vec(&all) {
            let _ = config::write_atomic(&crate::paths::sessions(), &data);
        }
        self.events.emit(Event::Core);
        self.events.emit(Event::Services);
    }

    fn sessions_on(&self, f: impl Fn(&Route) -> bool) -> usize {
        self.sessions.iter().filter(|e| f(&e.value().route)).count()
    }

    // ── 给控制接口的 JSON ─────────────────────────────────────

    pub fn core_json(&self) -> Value {
        let g = self.gateway.lock().unwrap();
        json!({
            "version": env!("CARGO_PKG_VERSION"),
            "api": crate::control::API_VERSION,
            "pid": std::process::id(),
            "port": g.port,
            "startedAt": self.started_at,
            "gatewayError": g.error,
            "configError": self.config_error(),
            "defaultSessions": self.sessions_on(|r| *r == Route::Default),
            "memory": self.memory.lock().unwrap().0,
        })
    }

    pub fn mcp_json(&self, name: &str) -> Option<Value> {
        let cfg = self.cfg.read().unwrap();
        let raw = cfg.mcps.get(name)?.clone();
        let parsed = cfg.entry(name)?;
        let default = parsed.as_ref().map(|e| e.is_default()).unwrap_or(true);
        drop(cfg);
        let mem = self.memory.lock().unwrap().1.get(name).copied();
        let base = json!({ "name": name, "entry": raw, "default": default });
        let Some(h) = self.handle(name) else {
            let (state, error) = match parsed {
                Err(e) => ("config_error", Some(e)),
                Ok(_) => ("stopped", None),
            };
            return Some(merge(base, json!({ "state": state, "error": error, "tools": [], "resources": 0, "prompts": 0, "instructionsLength": 0, "log": [], "restarts": 0 })));
        };
        let s = h.status();
        let tools: Vec<Value> = s.catalog.tools.iter().map(|t| json!({ "name": t["name"], "description": t["description"], "inputSchema": t["inputSchema"] })).collect();
        let log: Vec<Value> = s.log.iter().map(|l| json!({ "id": l.id, "t": l.t, "level": l.level, "text": l.text })).collect();
        Some(merge(base, json!({
            "state": s.state.as_str(), "error": s.error, "retryAt": s.retry_at, "attempts": s.attempts,
            "pid": s.pid, "startedAt": s.started_at, "restarts": s.restarts,
            "tools": tools, "resources": s.catalog.resources.len(), "prompts": s.catalog.prompts.len(),
            "instructionsLength": s.instructions.as_ref().map_or(0, |i| i.chars().count()),
            "log": log, "memory": if s.state == State::Ready { mem } else { None },
        })))
    }

    pub fn mcps_json(&self) -> Vec<Value> {
        let names: Vec<String> = self.cfg.read().unwrap().mcps.keys().cloned().collect();
        names.iter().filter_map(|n| self.mcp_json(n)).collect()
    }

    pub fn services_json(&self) -> Vec<Value> {
        let cfg = self.cfg.read().unwrap();
        cfg.services
            .iter()
            .map(|(n, s)| json!({
                "name": n,
                "mcps": s.mcps.iter().filter(|m| cfg.mcps.contains_key(*m)).collect::<Vec<_>>(),
                "sessions": self.sessions_on(|r| *r == Route::Named(n.clone())),
            }))
            .collect()
    }

    pub fn snapshot_json(&self, with_calls: bool) -> Value {
        let mut v = json!({ "core": self.core_json(), "mcps": self.mcps_json(), "services": self.services_json() });
        if with_calls {
            v["calls"] = json!(self.calls.recent(0, 3000));
        }
        v
    }

    // ── 改配置 ────────────────────────────────────────────────

    /// 改配置：在副本上改、校验、落盘，成功了才替换内存里的，然后 reconcile。配置文件读不了时拒绝一切写入。
    pub fn mutate<T>(self: &Arc<Self>, f: impl FnOnce(&mut ConfigFile) -> Result<T, crate::control::CtlError>) -> Result<T, crate::control::CtlError> {
        if let Some(e) = self.config_error() {
            return Err(crate::control::CtlError::new(409, "config_unreadable", format!("配置文件读不了，先修好它：{e}")));
        }
        let mut next = self.config();
        let out = f(&mut next)?;
        config::save(&next).map_err(|e| crate::control::CtlError::new(500, "save_failed", e))?;
        let port_changed = next.port != self.cfg.read().unwrap().port;
        *self.cfg.write().unwrap() = next.clone();
        if port_changed {
            let _ = self.port_tx.send(next.port);
        }
        self.reconcile();
        self.events.emit(Event::Services);
        Ok(out)
    }

    /// 重新读配置文件（手改过之后）。
    pub fn reload(self: &Arc<Self>) {
        let loaded = config::load();
        let port = loaded.cfg.port;
        *self.config_error.write().unwrap() = loaded.error;
        *self.cfg.write().unwrap() = loaded.cfg;
        let _ = self.port_tx.send_if_modified(|p| std::mem::replace(p, port) != port);
        self.reconcile();
        self.events.emit(Event::Snapshot);
    }

    pub fn record_call(&self, c: crate::calls::NewCall) {
        let v = self.calls.record(c);
        self.events.emit(Event::Calls(vec![v]));
    }

    // ── 内存 ──────────────────────────────────────────────────

    /// 每 5 秒量一次（只在有界面订阅时量，没人看就不花这个开销）。
    pub fn spawn_memory_sampler(self: &Arc<Self>) {
        let reg = self.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(5));
            loop {
                tick.tick().await;
                if !reg.events.has_subscribers() {
                    continue;
                }
                let pids: Vec<(String, u32)> = reg.ups.read().unwrap().iter().filter_map(|(n, u)| Some((n.clone(), u.handle.status().pid?))).collect();
                let table = tokio::task::spawn_blocking(crate::platform::process_table).await.unwrap_or_default();
                let me = std::process::id();
                let core = table.iter().find(|p| p.pid == me).map(|p| p.rss);
                let mcps: HashMap<String, u64> = pids.into_iter().filter_map(|(n, pid)| Some((n, crate::platform::tree_rss(&table, pid)?))).collect();
                *reg.memory.lock().unwrap() = (core, mcps.clone());
                reg.events.emit(Event::Memory(json!({ "core": core, "mcps": mcps })));
            }
        });
    }

    pub fn set_gateway(&self, port: u16, error: Option<String>) {
        {
            let mut g = self.gateway.lock().unwrap();
            g.port = port;
            g.error = error;
        }
        self.events.emit(Event::Core);
    }
}

fn merge(mut a: Value, b: Value) -> Value {
    if let (Some(a), Value::Object(b)) = (a.as_object_mut(), b) {
        a.extend(b);
    }
    a
}

/// 上游的清单变了之后重新拉（经它的 actor 发请求）。
async fn refetch(h: &UpstreamHandle) -> Option<Catalog> {
    async fn list(h: &UpstreamHandle, method: &str, key: &str) -> Vec<Value> {
        let mut out = Vec::new();
        let mut cursor: Option<String> = None;
        for _ in 0..20 {
            let params = cursor.as_ref().map_or(json!({}), |c| json!({ "cursor": c }));
            let Ok(m) = h.call(Message::request(Id::Num(1), method, Some(params)), upstream::LIST_TIMEOUT).await else { break };
            let Some(r) = m.result else { break };
            out.extend(r.get(key).and_then(Value::as_array).cloned().unwrap_or_default());
            cursor = r.get("nextCursor").and_then(Value::as_str).map(str::to_string);
            if cursor.is_none() {
                break;
            }
        }
        out
    }
    let caps = h.status().capabilities;
    let mut c = h.status().catalog;
    if caps.get("tools").is_some() {
        c.tools = list(h, "tools/list", "tools").await;
    }
    if caps.get("prompts").is_some() {
        c.prompts = list(h, "prompts/list", "prompts").await;
    }
    if caps.get("resources").is_some() {
        c.resources = list(h, "resources/list", "resources").await;
        c.templates = list(h, "resources/templates/list", "resourceTemplates").await;
    }
    Some(c)
}
