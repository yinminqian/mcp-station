//! 上游连接器：每个 MCP 一个 actor（stdio 是一个子进程，HTTP 是一个上游会话），外部只通过 `UpstreamHandle` 说话。
//! 从 mcp-rust 搬来，主要改动：
//! - 健康状态从一个原子值换成界面需要的完整 `Status`（原因、下次重试时间、pid、日志、工具清单……），变了就发事件；
//! - 退避表沿用 App 原来的 5/15/30/60/120/300 秒，去掉熔断；配置写错（找不到命令、缺变量、地址或令牌不对）不重试；
//! - 握手后先拉完 tools / prompts / resources 才算就绪，所以"等它启动"等到的就是完整清单；
//! - 不声明 sampling / roots / elicitation（共享单例连接无法把上游发来的请求归到具体客户端，见 mcp-rust 的说明）。

pub mod http;
pub mod stdio;

use crate::config::McpEntry;
use crate::error::UpstreamError;
use crate::events::{Event, Events};
use crate::jsonrpc::{Id, Message};
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

pub const PROTOCOL_VERSION: &str = "2025-06-18";
/// 单行报文 / 单个响应体上限。截图、大的工具表可以有几 MB，但不能无上限。
pub const MAX_MESSAGE_BYTES: usize = 64 * 1024 * 1024;
/// 连不上时的重试间隔（秒），按连续失败次数递增。
const BACKOFF: [u64; 6] = [5, 15, 30, 60, 120, 300];
const LOG_KEEP: usize = 200;

pub fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Starting,
    Ready,
    Backoff,
    ConfigError,
}

impl State {
    pub fn as_str(self) -> &'static str {
        match self {
            State::Starting => "starting",
            State::Ready => "ready",
            State::Backoff => "backoff",
            State::ConfigError => "config_error",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Catalog {
    pub tools: Vec<Value>,
    pub prompts: Vec<Value>,
    pub resources: Vec<Value>,
    pub templates: Vec<Value>,
}

#[derive(Debug, Clone)]
pub struct LogLine {
    pub id: u64,
    pub t: f64,
    pub level: &'static str,
    pub text: String,
}

#[derive(Debug, Clone)]
pub struct Status {
    pub state: State,
    pub error: Option<String>,
    pub retry_at: Option<f64>,
    pub attempts: u32,
    pub pid: Option<u32>,
    pub started_at: Option<f64>,
    pub restarts: u32,
    pub server_info: Value,
    pub instructions: Option<String>,
    pub capabilities: Value,
    pub catalog: Catalog,
    pub log: VecDeque<LogLine>,
}

static NEXT_LOG_ID: AtomicU64 = AtomicU64::new(1);

/// 一个上游的共享状态。actor 写，网关和控制接口读。
pub struct Shared {
    pub name: Arc<str>,
    status: Mutex<Status>,
    events: Events,
}

impl Shared {
    pub fn status(&self) -> Status {
        self.status.lock().unwrap().clone()
    }

    pub fn state(&self) -> State {
        self.status.lock().unwrap().state
    }

    pub fn update(&self, f: impl FnOnce(&mut Status)) {
        f(&mut self.status.lock().unwrap());
        self.events.emit(Event::Mcp(self.name.to_string()));
    }

    /// 记一行日志（内核自己的说明，或 stderr）。不单独发事件：stderr 可能刷屏，跟着下一次状态变化一起推。
    pub fn log(&self, level: &'static str, text: impl Into<String>) {
        let mut s = self.status.lock().unwrap();
        if s.log.len() == LOG_KEEP {
            s.log.pop_front();
        }
        s.log.push_back(LogLine { id: NEXT_LOG_ID.fetch_add(1, Ordering::Relaxed), t: now(), level, text: text.into() });
    }

    fn set_starting(&self, what: String) {
        self.log("info", what);
        self.update(|s| {
            s.state = State::Starting;
            s.retry_at = None;
        });
    }

    fn set_ready(&self, pid: Option<u32>, hs: Handshake, catalog: Catalog) {
        let summary = format!(
            "握手成功{} · {} 工具 · {} resource · {} prompt",
            if hs.server.is_empty() { String::new() } else { format!(" · {}", hs.server) },
            catalog.tools.len(),
            catalog.resources.len(),
            catalog.prompts.len()
        );
        self.log("info", summary);
        self.update(|s| {
            s.state = State::Ready;
            s.error = None;
            s.retry_at = None;
            s.attempts = 0;
            s.pid = pid;
            s.started_at = Some(now());
            s.server_info = hs.server_info;
            s.instructions = hs.instructions;
            s.capabilities = hs.capabilities;
            s.catalog = catalog;
        });
    }

    fn set_config_error(&self, why: String) {
        self.log("error", why.clone());
        self.update(|s| {
            s.state = State::ConfigError;
            s.error = Some(why);
            s.retry_at = None;
            s.pid = None;
            s.started_at = None;
        });
    }

    /// 连不上：记下原因，算出下次重试时间。返回要等多久。
    fn set_backoff(&self, why: String) -> Duration {
        let mut wait = 0;
        self.log("error", why.clone());
        self.update(|s| {
            s.attempts += 1;
            wait = BACKOFF[(s.attempts as usize).min(BACKOFF.len()) - 1];
            s.state = State::Backoff;
            s.error = Some(why);
            s.retry_at = Some(now() + wait as f64);
            s.pid = None;
            s.started_at = None;
        });
        self.log("info", format!("{wait} 秒后重试"));
        Duration::from_secs(wait)
    }

    pub fn set_catalog(&self, catalog: Catalog) {
        self.update(|s| s.catalog = catalog);
    }
}

#[derive(Debug, Clone)]
pub struct Handshake {
    pub server: String,
    pub server_info: Value,
    pub instructions: Option<String>,
    pub capabilities: Value,
}

impl Handshake {
    fn parse(result: &Value) -> Self {
        let info = result.get("serverInfo").cloned().unwrap_or(json!({}));
        let server = [info.get("name"), info.get("version")]
            .iter()
            .filter_map(|v| v.and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join(" ");
        Self {
            server,
            server_info: info,
            instructions: result.get("instructions").and_then(Value::as_str).map(str::to_string).filter(|s| !s.is_empty()),
            capabilities: result.get("capabilities").cloned().unwrap_or(json!({})),
        }
    }
}

/// 上游主动推过来的东西。
#[derive(Debug, Clone)]
pub enum Inbound {
    Notification(Message),
}

pub(crate) enum Command {
    Call { msg: Message, timeout: Duration, reply: oneshot::Sender<Result<Message, UpstreamError>> },
    /// 转发给上游的通知（客户端取消请求等，M7 用）。
    #[allow(dead_code)]
    Notify(Message),
    /// 立即重连：手动重启，或"立即重试"提前结束退避。
    Restart,
}

#[derive(Clone)]
pub struct UpstreamHandle {
    pub name: Arc<str>,
    pub shared: Arc<Shared>,
    tx: mpsc::Sender<Command>,
    inbound: broadcast::Sender<Inbound>,
}

impl UpstreamHandle {
    /// 发一个请求并等回复。启动中时请求在邮箱里排队，握手完就处理；退避和配置错误时立刻回错误。
    pub async fn call(&self, msg: Message, timeout: Duration) -> Result<Message, UpstreamError> {
        let (reply, rx) = oneshot::channel();
        self.tx.try_send(Command::Call { msg, timeout, reply }).map_err(|e| UpstreamError::Unavailable {
            slug: self.name.to_string(),
            reason: match e {
                mpsc::error::TrySendError::Full(_) => "请求积压".into(),
                mpsc::error::TrySendError::Closed(_) => "已停止".into(),
            },
        })?;
        rx.await.map_err(|_| UpstreamError::Unavailable { slug: self.name.to_string(), reason: "处理请求时退出".into() })?
    }

    #[allow(dead_code)]
    pub fn notify(&self, msg: Message) {
        let _ = self.tx.try_send(Command::Notify(msg));
    }

    /// 手动重启：计一次重启次数。
    pub fn restart(&self) {
        self.shared.update(|s| s.restarts += 1);
        let _ = self.tx.try_send(Command::Restart);
    }

    /// 立即重试：不计次数，只是提前结束退避（配置错误时也会再试一次）。
    pub fn retry(&self) {
        let _ = self.tx.try_send(Command::Restart);
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Inbound> {
        self.inbound.subscribe()
    }

    pub fn status(&self) -> Status {
        self.shared.status()
    }
}

/// 启动一个上游所需的全部信息。环境变量在这里已经算好（全局 env + 自己的 env，`${VAR}` 已展开）。
pub struct Spec {
    pub name: Arc<str>,
    pub entry: McpEntry,
    pub global_env: BTreeMap<String, String>,
    pub login_path: Option<String>,
}

impl Spec {
    /// `${VAR}` 先查全局 env，再查内核自己的环境。
    pub fn expand(&self, s: &str) -> Result<String, String> {
        crate::config::expand(s, &|k| self.global_env.get(k).cloned().or_else(|| std::env::var(k).ok()))
            .map_err(|var| format!("用到的变量 ${{{var}}} 没有定义（在设置的全局环境变量里加上它）"))
    }
}

pub const INIT_TIMEOUT: Duration = Duration::from_secs(60);
pub const LIST_TIMEOUT: Duration = Duration::from_secs(30);

pub fn spawn(spec: Spec, events: Events, shutdown: CancellationToken) -> UpstreamHandle {
    let shared = Arc::new(Shared {
        name: spec.name.clone(),
        status: Mutex::new(Status {
            state: State::Starting,
            error: None,
            retry_at: None,
            attempts: 0,
            pid: None,
            started_at: None,
            restarts: 0,
            server_info: json!({}),
            instructions: None,
            capabilities: json!({}),
            catalog: Catalog::default(),
            log: VecDeque::new(),
        }),
        events,
    });
    let (tx, rx) = mpsc::channel(256);
    let (inbound, _) = broadcast::channel(256);
    let handle = UpstreamHandle { name: spec.name.clone(), shared: shared.clone(), tx, inbound: inbound.clone() };
    if spec.entry.url.is_some() {
        tokio::spawn(http::supervisor(spec, rx, shared, inbound, shutdown));
    } else {
        tokio::spawn(stdio::supervisor(spec, rx, shared, inbound, shutdown));
    }
    handle
}

/// 一轮连接怎么结束的。
pub(crate) enum RunOutcome {
    /// 子进程退出、连接断了、握手失败：按退避重连。
    Failed(String),
    /// 配置写错了：重试也没用，等用户改配置或手动重试。
    ConfigError(String),
    Restart,
    Shutdown,
}

/// 监督循环里"这一轮结束之后"的处理。返回 false 表示内核在关停，退出循环。
pub(crate) async fn after_run(
    outcome: RunOutcome,
    sh: &Shared,
    rx: &mut mpsc::Receiver<Command>,
    shutdown: &CancellationToken,
) -> bool {
    match outcome {
        RunOutcome::Shutdown => false,
        RunOutcome::Restart => {
            sh.log("info", "重启");
            true
        }
        RunOutcome::Failed(why) => {
            let wait = sh.set_backoff(why);
            !matches!(drain(rx, Some(wait), sh, shutdown).await, Drained::Shutdown)
        }
        RunOutcome::ConfigError(why) => {
            sh.set_config_error(why);
            !matches!(drain(rx, None, sh, shutdown).await, Drained::Shutdown)
        }
    }
}

enum Drained {
    Shutdown,
    Proceed,
}

/// 不可用期间排空邮箱：每个请求立刻回错误（别让调用方干等到超时）。`Restart` 提前结束等待。
async fn drain(rx: &mut mpsc::Receiver<Command>, how_long: Option<Duration>, sh: &Shared, shutdown: &CancellationToken) -> Drained {
    let sleep = tokio::time::sleep(how_long.unwrap_or(Duration::from_secs(365 * 24 * 3600)));
    tokio::pin!(sleep);
    loop {
        tokio::select! {
            _ = shutdown.cancelled() => return Drained::Shutdown,
            _ = &mut sleep => return Drained::Proceed,
            cmd = rx.recv() => match cmd {
                None => return Drained::Shutdown,
                Some(Command::Restart) => return Drained::Proceed,
                Some(Command::Notify(_)) => {}
                Some(Command::Call { reply, .. }) => {
                    let reason = sh.status().error.unwrap_or_else(|| "正在重连".into());
                    let _ = reply.send(Err(UpstreamError::Unavailable { slug: sh.name.to_string(), reason }));
                }
            }
        }
    }
}

/// 握手阶段用的一问一答（还没进入并发转发的主循环）。stdio 和 HTTP 各自实现。
pub(crate) trait Rpc {
    async fn rpc(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value, String>;
}

pub(crate) fn initialize_params() -> Value {
    json!({
        "protocolVersion": PROTOCOL_VERSION,
        // 刻意留空：不声明 sampling / roots / elicitation（见模块说明）。
        "capabilities": {},
        "clientInfo": { "name": "MCP Station", "version": env!("CARGO_PKG_VERSION") }
    })
}

/// 按握手声明的能力拉清单。tools 跟着 nextCursor 翻页（最多 20 页）。拉不到的那一类当作没有，不让整个上游失败。
pub(crate) async fn fetch_catalog(r: &mut impl Rpc, caps: &Value, sh: &Shared) -> Result<Catalog, String> {
    let mut c = Catalog::default();
    if caps.get("tools").is_some() {
        c.tools = paged(r, "tools/list", "tools").await?;
    }
    if caps.get("prompts").is_some() {
        c.prompts = paged(r, "prompts/list", "prompts").await.unwrap_or_else(|e| {
            sh.log("warn", format!("prompts/list 失败：{e}"));
            Vec::new()
        });
    }
    if caps.get("resources").is_some() {
        c.resources = paged(r, "resources/list", "resources").await.unwrap_or_default();
        c.templates = paged(r, "resources/templates/list", "resourceTemplates").await.unwrap_or_default();
    }
    Ok(c)
}

async fn paged(r: &mut impl Rpc, method: &str, key: &str) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    let mut cursor: Option<String> = None;
    for _ in 0..20 {
        let params = cursor.as_ref().map_or(json!({}), |c| json!({ "cursor": c }));
        let res = r.rpc(method, params, LIST_TIMEOUT).await?;
        out.extend(res.get(key).and_then(Value::as_array).cloned().unwrap_or_default());
        cursor = res.get("nextCursor").and_then(Value::as_str).map(str::to_string);
        if cursor.is_none() {
            break;
        }
    }
    Ok(out)
}

/// 网关向上游发请求用自己的 id 空间（多个客户端的 id 会撞），以 gw- 开头便于在上游日志里认出来。
pub(crate) fn gw_id(n: u64) -> Id {
    Id::as_gateway(n)
}
