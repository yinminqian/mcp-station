//! 错误类型。每个错误都要能回答「客户端该看到什么 JSON-RPC 错误码」。（从 mcp-rust 搬来，去掉了熔断和 toml。）

use crate::jsonrpc::code;

#[derive(Debug, thiserror::Error)]
pub enum UpstreamError {
    #[error("{slug} 不可用：{reason}")]
    Unavailable { slug: String, reason: String },

    #[error("{slug} 超时（{elapsed_ms}ms > {limit_ms}ms）：{method}")]
    Timeout { slug: String, method: String, elapsed_ms: u64, limit_ms: u64 },

    #[error("{0} 传输层错误：{1}")]
    Transport(String, #[source] std::io::Error),
}

impl UpstreamError {
    /// 映射到 JSON-RPC 错误码。客户端靠这个决定要不要重试。
    pub fn rpc_code(&self) -> i64 {
        match self {
            UpstreamError::Timeout { .. } => code::UPSTREAM_TIMEOUT,
            _ => code::UPSTREAM_UNAVAILABLE,
        }
    }
}
