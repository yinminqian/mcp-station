//! 请求路由：把客户端发来的 MCP 请求翻译成对某个上游的调用，再把结果翻译回去。从 mcp-rust 的 router 改来。
//!
//! - 客户端的 initialize 不转发给上游（上游早就握过手了，再握一次是协议错误），由网关用握手结果本地应答：
//!   单个 MCP 的地址原样给它的 serverInfo 和 instructions；聚合地址把各成员的 instructions 按小标题拼起来。
//! - 工具和 prompt 在聚合地址里加 `<名字>__` 前缀，调用时还原；resources 用 URI 标识，不改名，读的时候按 URI 找归属。
//! - 上游挂了，它的工具仍然列出，调用时才报"不可用"——从列表里抹掉会让客户端以为工具被删了（mcp-rust 原注释）。

use crate::calls::NewCall;
use crate::jsonrpc::{code, Id, Message};
use crate::registry::{Member, Registry, Route};
use crate::upstream::{self, State};
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub struct Ctx {
    pub route: Route,
    pub client: String,
}

/// 内核刚启动、MCP 还在冷启动时，客户端要清单最多等这么久。
const SETTLE: Duration = Duration::from_secs(20);
const KNOWN_PROTOCOLS: [&str; 3] = ["2025-06-18", "2025-03-26", "2024-11-05"];

/// 处理一条客户端报文。返回 None 表示这是通知，不用回。
pub async fn handle(reg: &Arc<Registry>, msg: Message, ctx: &Ctx) -> Option<Message> {
    let id = msg.id.clone()?;
    let Some(members) = reg.members(&ctx.route) else {
        return Some(Message::error(id, code::INVALID_REQUEST, "这个地址对应的服务不存在了"));
    };
    let reply = match msg.method_str() {
        "initialize" => {
            reg.wait_settled(&members, SETTLE).await;
            initialize(reg, id, &msg, &members, &ctx.route)
        }
        "ping" => Message::response(id, json!({})),
        "logging/setLevel" => Message::response(id, json!({})),
        "tools/list" => {
            reg.wait_settled(&members, SETTLE).await;
            Message::response(id, json!({ "tools": list(reg, &members, |c| &c.tools, true) }))
        }
        "prompts/list" => {
            reg.wait_settled(&members, SETTLE).await;
            Message::response(id, json!({ "prompts": list(reg, &members, |c| &c.prompts, true) }))
        }
        "resources/list" => {
            reg.wait_settled(&members, SETTLE).await;
            Message::response(id, json!({ "resources": list(reg, &members, |c| &c.resources, false) }))
        }
        "resources/templates/list" => {
            reg.wait_settled(&members, SETTLE).await;
            Message::response(id, json!({ "resourceTemplates": list(reg, &members, |c| &c.templates, false) }))
        }
        "tools/call" => tools_call(reg, id, msg, &members, ctx).await,
        "prompts/get" => match by_name(&members, &msg) {
            Some((m, original)) => forward_renamed(reg, &m.name, id, msg, &original, upstream::LIST_TIMEOUT).await,
            None => Message::error(id, code::INVALID_PARAMS, format!("没有这个 prompt：{}", msg.param_name().unwrap_or(""))),
        },
        "resources/read" => {
            let uri = msg.params.as_ref().and_then(|p| p.get("uri")).and_then(Value::as_str).unwrap_or("").to_string();
            match resource_owner(reg, &members, &uri) {
                Some(owner) => forward(reg, &owner, id, msg, upstream::LIST_TIMEOUT).await,
                None => Message::error(id, code::INVALID_PARAMS, format!("没有哪个 MCP 提供 {uri}")),
            }
        }
        other => Message::error(id, code::METHOD_NOT_FOUND, format!("MCP Station 还不支持 {other}")),
    };
    Some(reply)
}

fn initialize(reg: &Registry, id: Id, msg: &Message, members: &[Member], route: &Route) -> Message {
    let proposed = msg.params.as_ref().and_then(|p| p.get("protocolVersion")).and_then(Value::as_str).unwrap_or("");
    let protocol = if KNOWN_PROTOCOLS.contains(&proposed) { proposed } else { upstream::PROTOCOL_VERSION };
    let statuses: Vec<(String, upstream::Status)> = members.iter().filter_map(|m| Some((m.name.clone(), reg.catalog(&m.name)?.1))).collect();
    let has = |cap: &str| statuses.iter().any(|(_, s)| s.capabilities.get(cap).is_some());
    let mut caps = json!({ "tools": { "listChanged": false } });
    if has("prompts") {
        caps["prompts"] = json!({ "listChanged": false });
    }
    if has("resources") {
        caps["resources"] = json!({ "listChanged": false });
    }
    let mut result = json!({ "protocolVersion": protocol, "capabilities": caps });
    match route {
        Route::Single(_) => {
            let st = statuses.first().map(|(_, s)| s);
            let info = st.map(|s| s.server_info.clone()).filter(|i| i.get("name").is_some());
            result["serverInfo"] = info.unwrap_or_else(|| json!({ "name": "MCP Station", "version": env!("CARGO_PKG_VERSION") }));
            if let Some(i) = st.and_then(|s| s.instructions.clone()) {
                result["instructions"] = json!(i);
            }
        }
        _ => {
            result["serverInfo"] = json!({ "name": "MCP Station", "version": env!("CARGO_PKG_VERSION") });
            let merged: Vec<String> = statuses
                .iter()
                .filter_map(|(n, s)| Some(format!("## {n}\n\n{}", s.instructions.as_ref()?.trim())))
                .collect();
            if !merged.is_empty() {
                result["instructions"] = json!(merged.join("\n\n"));
            }
        }
    }
    Message::response(id, result)
}

/// 把各成员的某一类清单拼起来。`rename` 为真时 name 加前缀（工具、prompt）。
fn list(reg: &Registry, members: &[Member], pick: impl Fn(&upstream::Catalog) -> &Vec<Value>, rename: bool) -> Vec<Value> {
    let mut out = Vec::new();
    for m in members {
        let Some((cat, _)) = reg.catalog(&m.name) else { continue };
        for item in pick(&cat) {
            let mut item = item.clone();
            if rename && !m.prefix.is_empty() {
                if let Some(n) = item.get("name").and_then(Value::as_str) {
                    item["name"] = json!(format!("{}{n}", m.prefix));
                }
            }
            out.push(item);
        }
    }
    out
}

fn by_name(members: &[Member], msg: &Message) -> Option<(Member, String)> {
    Registry::resolve(members, msg.param_name()?)
}

/// 哪个成员提供这个 URI：先查 resources 的精确 URI，再按模板的固定前缀匹配，只有一个成员有 resources 时就是它。
fn resource_owner(reg: &Registry, members: &[Member], uri: &str) -> Option<String> {
    let cats: Vec<(String, upstream::Catalog)> = members.iter().filter_map(|m| Some((m.name.clone(), reg.catalog(&m.name)?.0))).collect();
    if let Some((n, _)) = cats.iter().find(|(_, c)| c.resources.iter().any(|r| r.get("uri").and_then(Value::as_str) == Some(uri))) {
        return Some(n.clone());
    }
    let template_hit = cats.iter().find(|(_, c)| {
        c.templates.iter().any(|t| {
            let tpl = t.get("uriTemplate").and_then(Value::as_str).unwrap_or("");
            let fixed = tpl.split('{').next().unwrap_or("");
            !fixed.is_empty() && uri.starts_with(fixed)
        })
    });
    if let Some((n, _)) = template_hit {
        return Some(n.clone());
    }
    let with: Vec<&String> = cats.iter().filter(|(_, c)| !c.resources.is_empty() || !c.templates.is_empty()).map(|(n, _)| n).collect();
    (with.len() == 1).then(|| with[0].clone())
}

async fn tools_call(reg: &Arc<Registry>, id: Id, msg: Message, members: &[Member], ctx: &Ctx) -> Message {
    let exposed = msg.param_name().unwrap_or("").to_string();
    let Some((m, tool)) = by_name(members, &msg) else {
        return Message::error(id, code::TOOL_UNRESOLVED, format!("没有这个工具：{exposed}"));
    };
    let timeout = reg.config().entry(&m.name).and_then(Result::ok).and_then(|e| e.x.and_then(|x| x.timeout_secs)).map_or(Duration::from_secs(600), Duration::from_secs);
    let started = Instant::now();
    let reply = forward_renamed(reg, &m.name, id, msg, &tool, timeout).await;
    let error = reply
        .error
        .as_ref()
        .map(|e| e.get("message").and_then(Value::as_str).unwrap_or("出错").to_string())
        .or_else(|| {
            let r = reply.result.as_ref()?;
            r.get("isError").and_then(Value::as_bool).filter(|b| *b)?;
            let text: Vec<&str> = r.get("content")?.as_array()?.iter().filter_map(|c| c.get("text").and_then(Value::as_str)).collect();
            Some(if text.is_empty() { "工具返回出错".to_string() } else { text.join("\n") })
        });
    reg.record_call(NewCall {
        mcp: &m.name,
        tool: &tool,
        route: ctx.route.kind(),
        service: ctx.route.service(),
        client: &ctx.client,
        ms: started.elapsed().as_millis() as u64,
        error,
    });
    reply
}

async fn forward_renamed(reg: &Registry, mcp: &str, id: Id, mut msg: Message, original: &str, timeout: Duration) -> Message {
    if !msg.set_param_name(original) {
        return Message::error(id, code::INVALID_PARAMS, "params 不是对象");
    }
    forward(reg, mcp, id, msg, timeout).await
}

/// 转给上游。id 由上游 actor 换成网关自己的、回来再换回来。
pub async fn forward(reg: &Registry, mcp: &str, id: Id, mut msg: Message, timeout: Duration) -> Message {
    let Some(h) = reg.handle(mcp) else {
        return Message::error(id, code::UPSTREAM_UNAVAILABLE, format!("{mcp} 没在运行（没有服务用到它，在 MCP Station 里打开它的开关）"));
    };
    if h.shared.state() == State::ConfigError {
        let why = h.status().error.unwrap_or_default();
        return Message::error(id, code::UPSTREAM_UNAVAILABLE, format!("{mcp} 配置有问题：{why}"));
    }
    msg.id = Some(id.clone());
    match h.call(msg, timeout).await {
        Ok(mut resp) => {
            resp.id = Some(id);
            resp
        }
        Err(e) => Message::error_with_data(id, e.rpc_code(), e.to_string(), json!({ "mcp": mcp })),
    }
}
