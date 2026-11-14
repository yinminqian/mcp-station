//! Streamable HTTP 上游（远端 MCP）。从 mcp-rust 搬来：同一套监督结构，一轮连接是一个上游会话（initialize 拿到的
//! Mcp-Session-Id），会话失效（404）就重新握手。请求不在 actor 里串行等，每个请求独立 task，慢调用不堵别的调用。
//! 新增：`x.caCert` 信任自签证书；401/403、地址不是 MCP 服务（404/405）、请求头写错算配置错误，不重试。

use super::{after_run, fetch_catalog, gw_id, initialize_params, Command, Handshake, Inbound, Rpc, RunOutcome, Shared, Spec, INIT_TIMEOUT, MAX_MESSAGE_BYTES, PROTOCOL_VERSION};
use crate::error::UpstreamError;
use crate::jsonrpc::{code, Id, Kind, Message};
use futures::StreamExt;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, ACCEPT, CONTENT_TYPE};
use reqwest::StatusCode;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{broadcast, mpsc};
use tokio_util::sync::CancellationToken;

const SESSION_HEADER: &str = "mcp-session-id";
const PROTOCOL_HEADER: &str = "mcp-protocol-version";

pub(crate) async fn supervisor(
    spec: Spec,
    mut rx: mpsc::Receiver<Command>,
    sh: Arc<Shared>,
    inbound: broadcast::Sender<Inbound>,
    shutdown: CancellationToken,
) {
    loop {
        if shutdown.is_cancelled() {
            return;
        }
        let outcome = match prepare(&spec) {
            Ok((client, url)) => run_once(&spec, &client, url, &mut rx, &sh, &inbound, &shutdown).await,
            Err(why) => RunOutcome::ConfigError(why),
        };
        if !after_run(outcome, &sh, &mut rx, &shutdown).await {
            return;
        }
    }
}

/// 地址、请求头、CA 证书：这里出错都是配置问题。
fn prepare(spec: &Spec) -> Result<(reqwest::Client, String), String> {
    let url = spec.expand(spec.entry.url.as_deref().unwrap_or_default())?;
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return Err(format!("地址不对：{url}"));
    }
    let mut headers = HeaderMap::new();
    for (k, v) in spec.entry.headers.clone().unwrap_or_default() {
        let name = HeaderName::from_bytes(k.as_bytes()).map_err(|e| format!("请求头名「{k}」不对：{e}"))?;
        let mut val = HeaderValue::from_str(&spec.expand(&v)?).map_err(|e| format!("请求头「{k}」的值不对：{e}"))?;
        val.set_sensitive(true);
        headers.insert(name, val);
    }
    headers.insert(ACCEPT, HeaderValue::from_static("application/json, text/event-stream"));
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    let mut b = reqwest::Client::builder().default_headers(headers).connect_timeout(Duration::from_secs(10));
    if let Some(ca) = spec.entry.x.as_ref().and_then(|x| x.ca_cert.as_deref()) {
        let path = if let Some(rest) = ca.strip_prefix("~/") { crate::platform::home_dir().join(rest) } else { ca.into() };
        let raw = std::fs::read(&path).map_err(|e| format!("读不了 CA 证书 {}：{e}", path.display()))?;
        let cert = reqwest::Certificate::from_pem(&raw)
            .or_else(|_| reqwest::Certificate::from_der(&raw))
            .map_err(|e| format!("CA 证书 {} 不是 PEM 或 DER：{e}", path.display()))?;
        b = b.add_root_certificate(cert);
    }
    Ok((b.build().map_err(|e| format!("建不了 HTTP 客户端：{e}"))?, url))
}

#[derive(Clone)]
struct Conn {
    client: reqwest::Client,
    url: String,
    session_id: Option<String>,
    protocol: String,
}

impl Conn {
    fn post(&self, msg: &Message) -> reqwest::RequestBuilder {
        let mut req = self.client.post(&self.url).json(msg);
        if let Some(sid) = &self.session_id {
            req = req.header(SESSION_HEADER, sid);
        }
        req.header(PROTOCOL_HEADER, &self.protocol)
    }
}

/// 握手阶段的一问一答。
struct HttpRpc<'a> {
    conn: Conn,
    next: u64,
    inbound: &'a broadcast::Sender<Inbound>,
    name: Arc<str>,
    /// 状态码说明是配置问题（认证失败、地址不是 MCP 服务）。
    config_error: bool,
}

impl Rpc for HttpRpc<'_> {
    async fn rpc(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value, String> {
        self.next += 1;
        let id = gw_id(self.next);
        let msg = Message::request(id.clone(), method, Some(params));
        let fut = async {
            let resp = self.conn.post(&msg).send().await.map_err(|e| format!("连不上 {}：{e}", self.conn.url))?;
            let status = resp.status();
            if !status.is_success() {
                if matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN | StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED)
                    && self.conn.session_id.is_none()
                {
                    self.config_error = true;
                }
                return Err(status_error(status, resp).await);
            }
            if method == "initialize" {
                self.conn.session_id = resp.headers().get(SESSION_HEADER).and_then(|v| v.to_str().ok()).map(str::to_string);
            }
            read_reply(resp, &id, &self.name, self.inbound, &self.conn).await
        };
        let reply = tokio::time::timeout(timeout, fut).await.map_err(|_| format!("{} 秒内没有回应", timeout.as_secs()))??;
        if let Some(e) = &reply.error {
            return Err(format!("{method} 出错：{}", e.get("message").and_then(Value::as_str).unwrap_or("未知错误")));
        }
        Ok(reply.result.unwrap_or(json!({})))
    }
}

async fn handshake(io: &mut HttpRpc<'_>, sh: &Shared) -> Result<(Handshake, super::Catalog), String> {
    let init = io.rpc("initialize", initialize_params(), INIT_TIMEOUT).await.map_err(|e| format!("initialize 没有完成：{e}"))?;
    if let Some(v) = init.get("protocolVersion").and_then(Value::as_str) {
        io.conn.protocol = v.to_string();
    }
    let hs = Handshake::parse(&init);
    match io.conn.post(&Message::notification("notifications/initialized", None)).send().await {
        Ok(r) if r.status().is_success() => {}
        Ok(r) => return Err(format!("notifications/initialized 被拒：HTTP {}", r.status())),
        Err(e) => return Err(format!("发 notifications/initialized 失败：{e}")),
    }
    let catalog = fetch_catalog(io, &hs.capabilities, sh).await?;
    Ok((hs, catalog))
}

async fn run_once(
    spec: &Spec,
    client: &reqwest::Client,
    url: String,
    rx: &mut mpsc::Receiver<Command>,
    sh: &Arc<Shared>,
    inbound: &broadcast::Sender<Inbound>,
    shutdown: &CancellationToken,
) -> RunOutcome {
    sh.set_starting(format!("正在连接 {url}"));
    let mut io = HttpRpc {
        conn: Conn { client: client.clone(), url, session_id: None, protocol: PROTOCOL_VERSION.into() },
        next: 0,
        inbound,
        name: spec.name.clone(),
        config_error: false,
    };
    let ready = async {
        let r = handshake(&mut io, sh).await;
        r.map_err(|why| (why, io.config_error))
    };
    let (hs, catalog) = tokio::select! {
        r = ready => match r {
            Ok(v) => v,
            Err((why, true)) => return RunOutcome::ConfigError(why),
            Err((why, false)) => return RunOutcome::Failed(why),
        },
        _ = shutdown.cancelled() => return RunOutcome::Shutdown,
    };
    sh.set_ready(None, hs, catalog);
    let conn = io.conn;

    // 请求 task 发现会话失效时报回来，由 actor 决定重新握手（不算失败、不退避）。
    let (lost_tx, mut lost_rx) = mpsc::channel::<String>(1);
    let mut next = io.next;
    // 还在跑的请求：客户端带下来的 id → （上游认识的 id，请求 task）。取消时用。
    let mut inflight: std::collections::HashMap<Id, (Id, tokio::task::AbortHandle)> = Default::default();
    let outcome = loop {
        tokio::select! {
            biased;
            _ = shutdown.cancelled() => break RunOutcome::Shutdown,
            Some(why) = lost_rx.recv() => {
                sh.log("warn", format!("{why}，重新握手"));
                break RunOutcome::Restart;
            }
            cmd = rx.recv() => match cmd {
                None => break RunOutcome::Shutdown,
                Some(Command::Restart) => break RunOutcome::Restart,
                Some(Command::Notify(msg)) => {
                    let conn = conn.clone();
                    tokio::spawn(async move { let _ = conn.post(&msg).send().await; });
                }
                Some(Command::Cancel { id, reason }) => {
                    if let Some((up_id, task)) = inflight.remove(&id) {
                        task.abort(); // 调用方会收到"处理请求时退出"
                        let (conn, note) = (conn.clone(), super::cancelled(&up_id, &reason));
                        tokio::spawn(async move { let _ = conn.post(&note).send().await; });
                    }
                }
                Some(Command::Call { mut msg, timeout, reply }) => {
                    next += 1;
                    let id = gw_id(next);
                    let downstream_id = msg.id.replace(id.clone());
                    inflight.retain(|_, (_, t)| !t.is_finished());
                    let key = downstream_id.clone();
                    let up_id = id.clone();
                    let (conn, name, inbound, lost_tx) = (conn.clone(), spec.name.clone(), inbound.clone(), lost_tx.clone());
                    let task = tokio::spawn(async move {
                        let method = msg.method_str().to_string();
                        let started = Instant::now();
                        let out = match tokio::time::timeout(timeout, call(&conn, &msg, &id, &name, &inbound)).await {
                            Err(_) => Err(UpstreamError::Timeout {
                                slug: name.to_string(), method,
                                elapsed_ms: started.elapsed().as_millis() as u64, limit_ms: timeout.as_millis() as u64,
                            }),
                            Ok(Err(CallError::SessionLost)) => {
                                let _ = lost_tx.try_send("上游回 404（会话不存在了）".into());
                                Err(UpstreamError::Unavailable { slug: name.to_string(), reason: "上游会话失效，正在重新握手".into() })
                            }
                            Ok(Err(CallError::Other(why))) => Err(UpstreamError::Unavailable { slug: name.to_string(), reason: why }),
                            Ok(Ok(mut m)) => {
                                m.id = downstream_id;
                                Ok(m)
                            }
                        };
                        let _ = reply.send(out);
                    });
                    if let Some(k) = key {
                        inflight.insert(k, (up_id, task.abort_handle()));
                    }
                }
            },
        }
    };
    // 有状态的上游：显式结束旧会话，失败也无所谓。
    if let Some(sid) = &conn.session_id {
        let _ = tokio::time::timeout(Duration::from_secs(3), conn.client.delete(&conn.url).header(SESSION_HEADER, sid).send()).await;
    }
    outcome
}

enum CallError {
    SessionLost,
    Other(String),
}

async fn call(conn: &Conn, msg: &Message, want: &Id, name: &str, inbound: &broadcast::Sender<Inbound>) -> Result<Message, CallError> {
    let resp = conn.post(msg).send().await.map_err(|e| CallError::Other(format!("请求失败：{e}")))?;
    let status = resp.status();
    if status == StatusCode::NOT_FOUND && conn.session_id.is_some() {
        return Err(CallError::SessionLost);
    }
    if !status.is_success() {
        return Err(CallError::Other(status_error(status, resp).await));
    }
    read_reply(resp, want, name, inbound, conn).await.map_err(CallError::Other)
}

/// 从一次 POST 的响应里取出目标响应。上游可以回 JSON（一条报文），也可以回 SSE（先推通知，最后是响应）。
async fn read_reply(resp: reqwest::Response, want: &Id, name: &str, inbound: &broadcast::Sender<Inbound>, conn: &Conn) -> Result<Message, String> {
    let is_sse = resp.headers().get(CONTENT_TYPE).and_then(|v| v.to_str().ok()).is_some_and(|ct| ct.starts_with("text/event-stream"));
    let mut stream = resp.bytes_stream();
    let mut buf: Vec<u8> = Vec::new();
    while let Some(chunk) = stream.next().await {
        buf.extend_from_slice(&chunk.map_err(|e| format!("读响应失败：{e}"))?);
        if buf.len() > MAX_MESSAGE_BYTES {
            return Err("响应超过上限".into());
        }
        if is_sse {
            while let Some((data, rest)) = take_event(&buf) {
                buf = rest;
                let Some(data) = data else { continue };
                let Ok(m) = serde_json::from_str::<Message>(&data) else { continue };
                if let Some(found) = route(m, want, name, inbound, conn) {
                    return Ok(found);
                }
            }
        }
    }
    if is_sse {
        return Err("SSE 流结束了，没有收到对应的响应".into());
    }
    let v: Value = serde_json::from_slice(&buf).map_err(|e| format!("响应不是合法 JSON：{e}"))?;
    let items = match v {
        Value::Array(a) => a,
        other => vec![other],
    };
    for it in items {
        let m: Message = serde_json::from_value(it).map_err(|e| format!("响应不是合法 JSON-RPC：{e}"))?;
        if let Some(found) = route(m, want, name, inbound, conn) {
            return Ok(found);
        }
    }
    Err("响应里没有对应 id 的结果".into())
}

fn route(m: Message, want: &Id, name: &str, inbound: &broadcast::Sender<Inbound>, conn: &Conn) -> Option<Message> {
    match m.kind() {
        Kind::Response if m.id.as_ref() == Some(want) => return Some(m),
        Kind::Notification => {
            let _ = inbound.send(Inbound::Notification(m));
        }
        Kind::Request => {
            tracing::warn!(mcp = %name, method = %m.method_str(), "上游发来了请求，网关没有声明这个能力，回 MethodNotFound");
            let err = Message::error(m.id.clone().unwrap_or(Id::Null), code::METHOD_NOT_FOUND, format!("MCP Station 不支持 {}", m.method_str()));
            let conn = conn.clone();
            tokio::spawn(async move {
                let _ = conn.post(&err).send().await;
            });
        }
        _ => {}
    }
    None
}

/// 从缓冲里切出一个完整的 SSE 事件，返回（data，剩余缓冲）。兼容 CRLF；没有 data 的事件（心跳）返回 None。
fn take_event(buf: &[u8]) -> Option<(Option<String>, Vec<u8>)> {
    let text = std::str::from_utf8(buf).ok()?;
    let norm = text.replace("\r\n", "\n");
    let end = norm.find("\n\n")?;
    let (event, rest) = norm.split_at(end);
    let data: Vec<&str> = event.lines().filter_map(|l| l.strip_prefix("data:")).map(|d| d.strip_prefix(' ').unwrap_or(d)).collect();
    Some(((!data.is_empty()).then(|| data.join("\n")), rest[2..].as_bytes().to_vec()))
}

/// 非 2xx 的说明，带上响应体前 300 字（401/403 时上游一般会写清楚原因）。
async fn status_error(status: StatusCode, resp: reqwest::Response) -> String {
    let body = resp.text().await.unwrap_or_default();
    let body: String = body.chars().take(300).collect();
    let hint = match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => "（认证失败，检查请求头里的令牌）",
        StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED => "（这个地址不是 MCP 服务）",
        _ => "",
    };
    format!("HTTP {status}{hint}：{}", body.trim())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sse_按空行切分_兼容crlf() {
        let (data, rest) = take_event(b"event: message\ndata: {\"a\":\ndata: 1}\n\nrest").unwrap();
        assert_eq!(data.as_deref(), Some("{\"a\":\n1}"));
        assert_eq!(rest, b"rest");
        let (data, rest) = take_event(b": keepalive\r\n\r\ndata: x\r\n\r\n").unwrap();
        assert_eq!(data, None);
        assert_eq!(take_event(&rest).unwrap().0.as_deref(), Some("x"));
        assert!(take_event(b"data: half").is_none());
    }
}
