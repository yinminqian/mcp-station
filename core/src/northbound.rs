//! 网关的 HTTP 入口（Streamable HTTP）。三种地址共用一个处理函数：`/mcp`、`/s/<服务>/mcp`、`/servers/<名字>/mcp`。
//! 从 mcp-rust 的 northbound/streamable 改来：去掉了鉴权，加了 Host / Origin 检查、会话接管、请求体上限。
//!
//! - 只监听 127.0.0.1；Host 只认 localhost、127.0.0.1、host.docker.internal（加上配置里的 allowedHosts），
//!   带浏览器 Origin 头的请求一律拒绝——防网页借浏览器打本机端口（DNS rebinding）。
//! - 不认识的 Mcp-Session-Id 直接接管，不回 404：会话里只有地址和客户端名，内核重启（升级、崩溃）后可以原地重建，
//!   客户端不用重新握手。会话也写进 sessions.json，重启后还认得客户端名字。
//! - POST 的响应一般用 application/json。请求带了 `_meta.progressToken`、客户端也接受 SSE 时改用 SSE：
//!   先推上游发来的进度（token 换回客户端的），最后推结果。GET（服务器推送流）回 405。
//! - 客户端发来 notifications/cancelled 时转给正在跑这个请求的上游（见 router::cancel）。

use crate::jsonrpc::{code, Message};
use crate::registry::{Registry, Route, SessionInfo};
use crate::router::{self, Ctx};
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{HeaderMap, HeaderValue, Method, StatusCode, Uri};
use axum::response::sse::{Event as SseEvent, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::any;
use axum::Json;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

const SESSION_HEADER: &str = "mcp-session-id";
const UNKNOWN_CLIENT: &str = "未知客户端";

pub fn app(reg: Arc<Registry>) -> axum::Router {
    axum::Router::new()
        .route("/mcp", any(handle))
        .route("/s/{service}/mcp", any(handle))
        .route("/servers/{name}/mcp", any(handle))
        .layer(DefaultBodyLimit::max(crate::upstream::MAX_MESSAGE_BYTES))
        .with_state(reg)
}

/// 在配置的端口上监听。端口被占不退出（否则 launchd 会反复拉起、把 MCP 一遍遍重启），记下原因每 5 秒重试；端口改了就换。
pub async fn serve(reg: Arc<Registry>, mut port_rx: tokio::sync::watch::Receiver<u16>, shutdown: CancellationToken) {
    loop {
        let port = *port_rx.borrow_and_update();
        match tokio::net::TcpListener::bind(("127.0.0.1", port)).await {
            Ok(listener) => {
                tracing::info!(port, "网关开始监听");
                reg.set_gateway(port, None);
                crate::runtime::update_port(port);
                let mut rx = port_rx.clone();
                let stop = shutdown.clone();
                let _ = axum::serve(listener, app(reg.clone()))
                    .with_graceful_shutdown(async move {
                        tokio::select! {
                            _ = stop.cancelled() => {}
                            _ = rx.changed() => {}
                        }
                    })
                    .await;
                if shutdown.is_cancelled() {
                    return;
                }
            }
            Err(e) => {
                let owner = crate::platform::port_owner(port).map(|o| format!("，被 {o} 占着")).unwrap_or_default();
                let why = format!("端口 {port} 起不来：{e}{owner}");
                tracing::warn!("{why}");
                reg.set_gateway(port, Some(why));
                tokio::select! {
                    _ = shutdown.cancelled() => return,
                    _ = port_rx.changed() => {}
                    _ = tokio::time::sleep(Duration::from_secs(5)) => {}
                }
            }
        }
    }
}

fn route_of(path: &str) -> Option<Route> {
    let parts: Vec<&str> = path.trim_matches('/').split('/').collect();
    match parts.as_slice() {
        ["mcp"] => Some(Route::Default),
        ["s", name, "mcp"] => Some(Route::Named(name.to_string())),
        ["servers", name, "mcp"] => Some(Route::Single(name.to_string())),
        _ => None,
    }
}

fn host_allowed(reg: &Registry, headers: &HeaderMap) -> bool {
    let Some(host) = headers.get("host").and_then(|v| v.to_str().ok()) else { return true };
    let name = if host.starts_with('[') { host.split(']').next().unwrap_or(host).trim_start_matches('[') } else { host.split(':').next().unwrap_or(host) };
    ["localhost", "127.0.0.1", "host.docker.internal", "::1"].contains(&name) || reg.config().allowed_hosts.iter().any(|h| h == name)
}

fn error(status: StatusCode, message: impl Into<String>) -> Response {
    (status, Json(json!({ "jsonrpc": "2.0", "id": null, "error": { "code": code::INVALID_REQUEST, "message": message.into() } }))).into_response()
}

async fn handle(State(reg): State<Arc<Registry>>, method: Method, uri: Uri, headers: HeaderMap, body: Bytes) -> Response {
    if headers.contains_key("origin") || !host_allowed(&reg, &headers) {
        return error(StatusCode::FORBIDDEN, "只接受本机和本机容器里的客户端（浏览器网页不能直接连）");
    }
    let Some(route) = route_of(uri.path()) else { return error(StatusCode::NOT_FOUND, "没有这个地址") };
    if reg.members(&route).is_none() {
        let what = match &route {
            Route::Named(n) => format!("没有叫 {n} 的服务"),
            Route::Single(n) => format!("没有叫 {n} 的 MCP"),
            Route::Default => "没有这个地址".into(),
        };
        return error(StatusCode::NOT_FOUND, what);
    }
    let sid = headers.get(SESSION_HEADER).and_then(|v| v.to_str().ok()).map(str::to_string);
    match method {
        Method::POST => {}
        Method::DELETE => {
            if let Some(sid) = &sid {
                reg.session_close(sid);
            }
            return StatusCode::OK.into_response();
        }
        _ => return (StatusCode::METHOD_NOT_ALLOWED, [("allow", "POST, DELETE")]).into_response(),
    }

    let parsed: Value = match serde_json::from_slice(&body) {
        Ok(v) => v,
        Err(e) => {
            return (StatusCode::BAD_REQUEST, Json(json!({ "jsonrpc": "2.0", "id": null, "error": { "code": code::PARSE_ERROR, "message": format!("JSON 解析失败：{e}") } }))).into_response()
        }
    };
    // 2025-06-18 起规范去掉了批处理，但旧客户端可能还发数组；接受它没有成本。
    let (msgs, batch): (Vec<Message>, bool) = match parsed {
        Value::Array(items) => (items.into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect(), true),
        v => match serde_json::from_value(v) {
            Ok(m) => (vec![m], false),
            Err(e) => return error(StatusCode::BAD_REQUEST, format!("不是一条 JSON-RPC 报文：{e}")),
        },
    };

    // ── 会话 ──────────────────────────────────────────────────
    let init = msgs.iter().find(|m| m.method_str() == "initialize");
    let (session_id, client) = if let Some(init) = init {
        if let Some(old) = &sid {
            reg.session_close(old);
        }
        let info = init.params.as_ref().and_then(|p| p.get("clientInfo"));
        let client = [info.and_then(|i| i.get("name")), info.and_then(|i| i.get("version"))]
            .iter()
            .filter_map(|v| v.and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join(" ");
        let client = if client.is_empty() { UNKNOWN_CLIENT.to_string() } else { client };
        let id = uuid::Uuid::new_v4().to_string();
        reg.session_open(id.clone(), SessionInfo { client: client.clone(), route: route.clone() });
        (Some(id), client)
    } else if let Some(sid) = sid {
        let known = reg.sessions.get(&sid).map(|s| s.client.clone());
        let client = match known {
            Some(c) => c,
            None => {
                // 接管：内核重启前的会话，或者别的网关开的会话。
                reg.session_open(sid.clone(), SessionInfo { client: UNKNOWN_CLIENT.into(), route: route.clone() });
                UNKNOWN_CLIENT.into()
            }
        };
        (Some(sid), client)
    } else {
        (None, UNKNOWN_CLIENT.to_string())
    };

    let wants_stream = !batch
        && msgs.len() == 1
        && msgs[0].params.as_ref().and_then(|p| p.pointer("/_meta/progressToken")).is_some()
        && headers.get("accept").and_then(|v| v.to_str().ok()).is_some_and(|a| a.contains("text/event-stream"));
    if wants_stream {
        return stream_reply(reg, msgs.into_iter().next().unwrap(), route, client, session_id);
    }

    let ctx = Ctx { route, client, session: session_id.clone(), progress: None };
    let mut replies = Vec::new();
    for m in msgs {
        if let Some(r) = router::handle(&reg, m, &ctx).await {
            replies.push(r);
        }
    }
    let mut resp = if replies.is_empty() {
        StatusCode::ACCEPTED.into_response()
    } else if batch {
        Json(json!(replies)).into_response()
    } else {
        Json(json!(replies[0])).into_response()
    };
    if let Some(id) = session_id.and_then(|s| HeaderValue::from_str(&s).ok()) {
        resp.headers_mut().insert(SESSION_HEADER, id);
    }
    resp
}

/// 用 SSE 回一个请求：进度通知和最终结果都走同一个通道，结果发出后所有发送端都释放，流自然结束。
fn stream_reply(reg: Arc<Registry>, msg: Message, route: Route, client: String, session_id: Option<String>) -> Response {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<Message>();
    let ctx = Ctx { route, client, session: session_id.clone(), progress: Some(tx.clone()) };
    tokio::spawn(async move {
        if let Some(r) = router::handle(&reg, msg, &ctx).await {
            let _ = tx.send(r);
        }
    });
    let stream = futures::stream::unfold(rx, |mut rx| async move {
        let m = rx.recv().await?;
        Some((Ok::<_, std::convert::Infallible>(SseEvent::default().event("message").data(serde_json::to_string(&m).unwrap_or_default())), rx))
    });
    let mut resp = Sse::new(stream).into_response();
    if let Some(id) = session_id.and_then(|s| HeaderValue::from_str(&s).ok()) {
        resp.headers_mut().insert(SESSION_HEADER, id);
    }
    resp
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 三种地址() {
        assert_eq!(route_of("/mcp"), Some(Route::Default));
        assert_eq!(route_of("/s/ios/mcp"), Some(Route::Named("ios".into())));
        assert_eq!(route_of("/servers/iterm/mcp/"), Some(Route::Single("iterm".into())));
        assert_eq!(route_of("/servers/iterm"), None);
    }
}
