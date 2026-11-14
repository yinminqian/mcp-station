//! 控制接口 `/control/*`：给界面（Mac 的 Swift App，以后的 Windows 界面）用。和网关分开监听 127.0.0.1 的随机端口，
//! 端口和令牌写在 runtime.json 里——网关端口被占时控制接口照样能用，界面能显示原因、能改端口。
//! 每个请求带 `Authorization: Bearer <令牌>`；带 Origin 头的一律拒绝。
//!
//! 实时推送走 `GET /control/events`（SSE）：连上先发一份完整快照，之后按"谁变了"推送。每个事件固定两行
//! （`event:` 和单行的 `data:`），界面按行读就行。

use crate::config::{self, McpEntry, ServiceEntry};
use crate::events::Event;
use crate::jsonrpc::{Id, Message};
use crate::registry::Registry;
use axum::body::Bytes;
use axum::extract::{Path, Query, Request, State};
use axum::http::StatusCode;
use axum::middleware::{self, Next};
use axum::response::sse::{Event as SseEvent, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use axum::Json;
use futures::Stream;
use serde::Deserialize;
use serde_json::{json, Value};
use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

/// 控制接口的版本。界面发现对不上时提示升级内核。
pub const API_VERSION: u32 = 1;

#[derive(Debug)]
pub struct CtlError {
    status: u16,
    code: &'static str,
    message: String,
}

impl CtlError {
    pub fn new(status: u16, code: &'static str, message: impl Into<String>) -> Self {
        Self { status, code, message: message.into() }
    }
}

impl IntoResponse for CtlError {
    fn into_response(self) -> Response {
        let status = StatusCode::from_u16(self.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
        (status, Json(json!({ "error": { "code": self.code, "message": self.message } }))).into_response()
    }
}

type R = Result<Json<Value>, CtlError>;

#[derive(Clone)]
struct Ctl {
    reg: Arc<Registry>,
    token: Arc<str>,
}

pub fn app(reg: Arc<Registry>, token: String) -> axum::Router {
    let st = Ctl { reg, token: Arc::from(token) };
    axum::Router::new()
        .route("/control/ping", get(ping))
        .route("/control/status", get(status))
        .route("/control/events", get(events))
        .route("/control/mcps", post(add_mcp))
        .route("/control/mcps/{name}/default", put(set_default))
        .route("/control/mcps/{name}/restart", post(restart))
        .route("/control/mcps/{name}/retry", post(retry))
        .route("/control/mcps/{name}/call", post(call))
        .route("/control/services", post(create_service))
        .route("/control/services/{name}", put(update_service).delete(delete_service))
        .route("/control/settings", put(settings))
        .route("/control/import", post(import))
        .route("/control/export", get(export))
        .route("/control/reload", post(reload))
        .route("/control/calls", get(calls))
        .route("/control/logs", get(logs))
        .layer(axum::extract::DefaultBodyLimit::max(crate::upstream::MAX_MESSAGE_BYTES))
        .layer(middleware::from_fn_with_state(st.clone(), auth))
        .with_state(st)
}

async fn auth(State(st): State<Ctl>, req: Request, next: Next) -> Response {
    if req.headers().contains_key("origin") {
        return CtlError::new(403, "forbidden", "不接受浏览器发来的请求").into_response();
    }
    let ok = req.headers().get("authorization").and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")) == Some(&*st.token);
    if !ok {
        return CtlError::new(401, "unauthorized", "令牌不对（读 runtime.json）").into_response();
    }
    next.run(req).await
}

async fn ping() -> Json<Value> {
    Json(json!({ "version": crate::VERSION, "api": API_VERSION, "pid": std::process::id() }))
}

async fn status(State(st): State<Ctl>) -> Json<Value> {
    Json(st.reg.snapshot_json(false))
}

async fn events(State(st): State<Ctl>) -> Sse<impl Stream<Item = Result<SseEvent, Infallible>>> {
    let reg = st.reg.clone();
    let rx = reg.events.subscribe();
    let first = futures::stream::once({
        let reg = reg.clone();
        async move { Ok(sse("snapshot", reg.snapshot_json(true))) }
    });
    let live = futures::stream::unfold((rx, reg), |(mut rx, reg)| async move {
        let ev = match rx.recv().await {
            Ok(Event::Core) => sse("core", reg.core_json()),
            Ok(Event::Mcp(n)) => match reg.mcp_json(&n) {
                Some(m) => sse("mcp", m),
                None => sse("snapshot", reg.snapshot_json(true)), // 删掉了
            },
            Ok(Event::Services) => sse("services", json!(reg.services_json())),
            Ok(Event::Calls(c)) => sse("calls", json!(c)),
            Ok(Event::Memory(m)) => sse("memory", m),
            // 积压了（界面读太慢）：发一份完整快照兜底
            Ok(Event::Snapshot) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => sse("snapshot", reg.snapshot_json(true)),
            Err(_) => return None,
        };
        Some((Ok(ev), (rx, reg)))
    });
    Sse::new(futures::StreamExt::chain(first, live)).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("keepalive"))
}

fn sse(kind: &str, data: Value) -> SseEvent {
    SseEvent::default().event(kind).data(data.to_string())
}

fn mcp_or_404(reg: &Registry, name: &str) -> R {
    reg.mcp_json(name).map(Json).ok_or_else(|| CtlError::new(404, "unknown_mcp", format!("找不到 MCP「{name}」")))
}

#[derive(Deserialize)]
struct OnOff {
    on: bool,
}

async fn set_default(State(st): State<Ctl>, Path(name): Path<String>, Json(b): Json<OnOff>) -> R {
    st.reg.mutate(|c| {
        let mut e = c.entry(&name).ok_or_else(|| CtlError::new(404, "unknown_mcp", format!("找不到 MCP「{name}」")))?.map_err(|e| CtlError::new(409, "bad_entry", e))?;
        e.set_default(b.on);
        c.set_entry(&name, &e);
        Ok(())
    })?;
    mcp_or_404(&st.reg, &name)
}

async fn restart(State(st): State<Ctl>, Path(name): Path<String>) -> R {
    match st.reg.handle(&name) {
        Some(h) => h.restart(),
        None => st.reg.reconcile(),
    }
    mcp_or_404(&st.reg, &name)
}

async fn retry(State(st): State<Ctl>, Path(name): Path<String>) -> R {
    if let Some(h) = st.reg.handle(&name) {
        h.retry();
    }
    mcp_or_404(&st.reg, &name)
}

#[derive(Deserialize)]
struct NewMcp {
    name: String,
    entry: Value,
}

async fn add_mcp(State(st): State<Ctl>, Json(b): Json<NewMcp>) -> Result<(StatusCode, Json<Value>), CtlError> {
    let name = b.name.trim().to_string();
    if name.is_empty() {
        return Err(CtlError::new(400, "missing_field", "名字"));
    }
    if !config::is_valid_name(&name) {
        return Err(CtlError::new(400, "invalid_name", name));
    }
    McpEntry::parse(&b.entry).map_err(|e| CtlError::new(400, "missing_field", e))?;
    st.reg.mutate(|c| {
        if c.mcps.contains_key(&name) {
            return Err(CtlError::new(409, "duplicate_mcp", name.clone()));
        }
        c.mcps.insert(name.clone(), b.entry.clone());
        Ok(())
    })?;
    Ok((StatusCode::CREATED, mcp_or_404(&st.reg, &name)?))
}

#[derive(Deserialize)]
struct CallBody {
    tool: String,
    #[serde(default)]
    arguments: Value,
}

/// 试调用：经常驻的连接调一次工具，结果记进调用记录（route=test）。返回内容的文字拼起来，过长截断。
async fn call(State(st): State<Ctl>, Path(name): Path<String>, Json(b): Json<CallBody>) -> R {
    if st.reg.config().mcps.get(&name).is_none() {
        return Err(CtlError::new(404, "unknown_mcp", format!("找不到 MCP「{name}」")));
    }
    let args = if b.arguments.is_null() { json!({}) } else { b.arguments };
    let msg = Message::request(Id::Num(1), "tools/call", Some(json!({ "name": b.tool, "arguments": args })));
    let timeout = Duration::from_secs(600);
    let started = std::time::Instant::now();
    let reply = crate::router::forward(&st.reg, &name, Id::Num(1), msg, timeout).await;
    let ms = started.elapsed().as_millis() as u64;
    let (is_error, text) = match (&reply.error, &reply.result) {
        (Some(e), _) => (true, e.get("message").and_then(Value::as_str).unwrap_or("出错").to_string()),
        (None, Some(r)) => (r.get("isError").and_then(Value::as_bool).unwrap_or(false), content_text(r.get("content"))),
        _ => (true, "上游没有返回结果".into()),
    };
    st.reg.record_call(crate::calls::NewCall {
        mcp: &name, tool: &b.tool, route: "test", service: None, client: "MCP Station", ms,
        error: is_error.then(|| text.clone()),
    });
    Ok(Json(json!({ "isError": is_error, "text": text, "ms": ms })))
}

/// tools/call 返回的 content：文字原样拼起来，图片等写成占位说明；最多 2 万字。
fn content_text(content: Option<&Value>) -> String {
    let parts: Vec<String> = content
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .map(|item| match item.get("type").and_then(Value::as_str) {
                    Some("text") => item.get("text").and_then(Value::as_str).unwrap_or("").to_string(),
                    Some("image") => format!("[图片 {}]", item.get("mimeType").and_then(Value::as_str).unwrap_or("")),
                    Some("audio") => format!("[音频 {}]", item.get("mimeType").and_then(Value::as_str).unwrap_or("")),
                    Some("resource") | Some("resource_link") => format!(
                        "[资源 {}]",
                        item.pointer("/resource/uri").or_else(|| item.get("uri")).and_then(Value::as_str).unwrap_or("")
                    ),
                    other => format!("[{}]", other.unwrap_or("未知内容")),
                })
                .collect()
        })
        .unwrap_or_default();
    let text = parts.join("\n");
    if text.chars().count() > 20000 {
        format!("{}\n…（已截断）", text.chars().take(20000).collect::<String>())
    } else {
        text
    }
}

#[derive(Deserialize)]
struct NewService {
    name: String,
    #[serde(default)]
    mcps: Vec<String>,
}

async fn create_service(State(st): State<Ctl>, Json(b): Json<NewService>) -> R {
    if !config::is_valid_name(&b.name) {
        return Err(CtlError::new(400, "invalid_name", b.name));
    }
    st.reg.mutate(|c| {
        if c.services.contains_key(&b.name) {
            return Err(CtlError::new(409, "duplicate_name", b.name.clone()));
        }
        c.services.insert(b.name.clone(), ServiceEntry { mcps: b.mcps.clone(), ..Default::default() });
        Ok(())
    })?;
    Ok(Json(json!(st.reg.services_json())))
}

#[derive(Deserialize)]
struct ServiceUpdate {
    mcps: Option<Vec<String>>,
    name: Option<String>,
}

async fn update_service(State(st): State<Ctl>, Path(name): Path<String>, Json(b): Json<ServiceUpdate>) -> R {
    if let Some(n) = &b.name {
        if !config::is_valid_name(n) {
            return Err(CtlError::new(400, "invalid_name", n.clone()));
        }
    }
    st.reg.mutate(|c| {
        let mut s = c.services.remove(&name).ok_or_else(|| CtlError::new(404, "unknown_service", format!("找不到服务「{name}」")))?;
        if let Some(m) = b.mcps {
            // 按 MCP 名字排序存，和界面列表的顺序一致
            let mut m = m;
            m.sort_by_key(|x| x.to_lowercase());
            s.mcps = m;
        }
        let new_name = b.name.unwrap_or(name.clone());
        if new_name != name && c.services.contains_key(&new_name) {
            return Err(CtlError::new(409, "duplicate_name", new_name));
        }
        c.services.insert(new_name, s);
        Ok(())
    })?;
    Ok(Json(json!(st.reg.services_json())))
}

async fn delete_service(State(st): State<Ctl>, Path(name): Path<String>) -> R {
    st.reg.mutate(|c| {
        c.services.remove(&name);
        Ok(())
    })?;
    Ok(Json(json!(st.reg.services_json())))
}

#[derive(Deserialize)]
struct Settings {
    port: Option<u16>,
}

async fn settings(State(st): State<Ctl>, Json(b): Json<Settings>) -> R {
    if let Some(p) = b.port {
        if p < 1024 {
            return Err(CtlError::new(400, "invalid_port", p.to_string()));
        }
        st.reg.mutate(|c| {
            c.port = p;
            Ok(())
        })?;
    }
    Ok(Json(st.reg.core_json()))
}

/// 导入一份配置（本软件导出的，或 Claude / Cursor 等的 mcpServers），合并进当前配置。同名的 MCP 覆盖。
async fn import(State(st): State<Ctl>, body: Bytes) -> R {
    let imp = config::parse_import(&body).map_err(|e| CtlError::new(400, "unrecognized", e))?;
    let (mut added, mut updated, mut skipped) = (0, 0, Vec::new());
    st.reg.mutate(|c| {
        for (name, e) in &imp.mcps {
            if !config::is_valid_name(name) {
                skipped.push(name.clone());
                continue;
            }
            if c.mcps.contains_key(name) { updated += 1 } else { added += 1 }
            c.set_entry(name, e);
        }
        for (name, s) in &imp.services {
            if config::is_valid_name(name) {
                c.services.insert(name.clone(), s.clone());
            }
        }
        c.env.extend(imp.env.clone());
        Ok(())
    })?;
    st.reg.events.emit(Event::Snapshot);
    Ok(Json(json!({ "added": added, "updated": updated, "services": imp.services.len(), "skipped": skipped })))
}

async fn export(State(st): State<Ctl>) -> Response {
    let body = serde_json::to_string_pretty(&st.reg.config()).unwrap_or_default();
    ([("content-type", "application/json")], body).into_response()
}

async fn reload(State(st): State<Ctl>) -> Json<Value> {
    st.reg.reload();
    Json(st.reg.snapshot_json(false))
}

#[derive(Deserialize)]
struct CallsQuery {
    after: Option<u64>,
    limit: Option<usize>,
}

async fn calls(State(st): State<Ctl>, Query(q): Query<CallsQuery>) -> Json<Value> {
    let c = st.reg.calls.recent(q.after.unwrap_or(0), q.limit.unwrap_or(200));
    let latest = c.last().and_then(|v| v["id"].as_u64()).unwrap_or(0);
    Json(json!({ "calls": c, "latest": latest }))
}

#[derive(Deserialize)]
struct LogsQuery {
    lines: Option<usize>,
}

async fn logs(Query(q): Query<LogsQuery>) -> Json<Value> {
    let text = crate::logfile::latest().and_then(|p| std::fs::read_to_string(p).ok()).unwrap_or_default();
    let n = q.lines.unwrap_or(200);
    let lines: Vec<&str> = text.lines().rev().take(n).collect::<Vec<_>>().into_iter().rev().collect();
    Json(json!({ "lines": lines }))
}
