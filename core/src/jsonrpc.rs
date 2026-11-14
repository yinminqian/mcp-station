//! JSON-RPC 2.0 编解码 —— 网关的地基。
//!
//! # 为什么不用强类型的 Request/Response/Notification 三态 enum
//!
//! 网关的职责是「透传 + 改写」,不是「实现 MCP 双端」。如果把消息建模成
//!
//!     enum Message { Request{id,method,params}, Response{id,result}, Notification{method,params} }
//!
//! 那么 serde 反序列化时字段组合稍有偏差(上游多带一个字段、协议升级新增一种
//! 消息形态、某个 server 发了 id+method+result 的非标准组合)就直接反序列化失败,
//! 表现成「升级了某个上游之后网关整条链路报错」——而网关本来完全不需要理解那些字段。
//!
//! 所以这里用**扁平结构 + Option 字段**:任何在 JSON-RPC 2.0 语法上说得通的报文
//! 都能进来、能被路由、能原样出去。网关只解析它必须理解的东西(id / method),
//! params / result / error 一律以 `Value` 原样搬运。协议出新版本,这个文件不用改。

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// JSON-RPC 请求 id。规范允许 string / number / null,其中 null 仅用于
/// 「无法确定 id 的错误响应」。我们把 null 归到 `Null` 而不是 None,因为
/// None 表示「字段不存在」(= notification),两者语义完全不同,混淆会导致
/// 把一个错误响应错认成通知而丢掉。
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Id {
    Num(i64),
    Str(String),
    Null,
}

impl Id {
    pub fn as_gateway(n: u64) -> Self {
        // 网关向上游发请求时用自己的 id 空间(见 module 文档里的 id 重写),
        // 统一带前缀便于在上游日志里一眼认出是网关发的。
        Id::Str(format!("gw-{n}"))
    }
}

impl std::fmt::Display for Id {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Id::Num(n) => write!(f, "{n}"),
            Id::Str(s) => write!(f, "{s}"),
            Id::Null => write!(f, "null"),
        }
    }
}

/// 一条 JSON-RPC 报文。
///
/// 字段全部 Option,靠 `kind()` 判定形态而不是靠反序列化成功与否。
/// `#[serde(default)]` + `skip_serializing_if` 保证:进来什么样,出去还是什么样,
/// 不会因为经过网关而多出 `"params": null` 这类上游可能不接受的字段。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub jsonrpc: String,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<Id>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub params: Option<Value>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<Value>,

    /// 协议未来新增的顶层字段落在这里,原样带走。
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

/// 报文形态。注意判定顺序:先看 method 再看 id。
/// 因为「有 method 且有 id」是 request,「有 method 无 id」是 notification,
/// 「无 method 有 id」是 response。三者互斥,不需要看 result/error 是否存在
/// —— 有些 server 会发 `{id, result: null}`,按 result 判定会误判成 request。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Request,
    Notification,
    Response,
    /// 语法上说不通(既无 method 又无 id)。不 panic、不丢弃,交给调用方决定
    /// 记日志还是回 InvalidRequest —— 静默丢弃是最难排查的一类故障。
    Malformed,
}

impl Message {
    pub fn kind(&self) -> Kind {
        match (&self.method, &self.id) {
            (Some(_), Some(_)) => Kind::Request,
            (Some(_), None) => Kind::Notification,
            (None, Some(_)) => Kind::Response,
            (None, None) => Kind::Malformed,
        }
    }

    pub fn request(id: Id, method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id: Some(id),
            method: Some(method.into()),
            params,
            result: None,
            error: None,
            extra: Default::default(),
        }
    }

    pub fn notification(method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id: None,
            method: Some(method.into()),
            params,
            result: None,
            error: None,
            extra: Default::default(),
        }
    }

    pub fn response(id: Id, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id: Some(id),
            method: None,
            params: None,
            result: Some(result),
            error: None,
            extra: Default::default(),
        }
    }

    pub fn error(id: Id, code: i64, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id: Some(id),
            method: None,
            params: None,
            result: None,
            error: Some(json!({ "code": code, "message": message.into() })),
            extra: Default::default(),
        }
    }

    /// 带 `data` 的错误响应。上游挂掉/超时这类情况要把上下文塞进 data,
    /// 否则客户端只看到一句 "internal error",排查得从头来。
    pub fn error_with_data(id: Id, code: i64, message: impl Into<String>, data: Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id: Some(id),
            method: None,
            params: None,
            result: None,
            error: Some(json!({ "code": code, "message": message.into(), "data": data })),
            extra: Default::default(),
        }
    }

    pub fn method_str(&self) -> &str {
        self.method.as_deref().unwrap_or("")
    }

    /// 取 `params.name`(tools/call、prompts/get 都用这个字段带名字)。
    pub fn param_name(&self) -> Option<&str> {
        self.params.as_ref()?.get("name")?.as_str()
    }

    /// 改写 `params.name`。共享单例上游模型下,下游看到的是加了前缀的名字,
    /// 转发给上游前必须还原成原名。改不动就返回 false 让调用方回 InvalidParams,
    /// 而不是静默转发一个上游不认识的名字。
    pub fn set_param_name(&mut self, name: &str) -> bool {
        match self.params.as_mut().and_then(Value::as_object_mut) {
            Some(obj) => {
                obj.insert("name".into(), Value::String(name.into()));
                true
            }
            None => false,
        }
    }
}

/// JSON-RPC 标准错误码 + MCP 约定的网关自用码。
/// 自用码取 -32000..-32099 这段「server error」区间,规范明确留给实现方。
#[allow(dead_code)]
pub mod code {
    pub const PARSE_ERROR: i64 = -32700;
    pub const INVALID_REQUEST: i64 = -32600;
    pub const METHOD_NOT_FOUND: i64 = -32601;
    pub const INVALID_PARAMS: i64 = -32602;
    pub const INTERNAL_ERROR: i64 = -32603;

    /// 上游连接不可用(进程挂了 / 熔断打开 / 还没 initialize 完)。
    pub const UPSTREAM_UNAVAILABLE: i64 = -32000;
    /// 上游在超时时间内没回。
    pub const UPSTREAM_TIMEOUT: i64 = -32001;
    /// 工具名解析不到任何上游。
    pub const TOOL_UNRESOLVED: i64 = -32002;
}
