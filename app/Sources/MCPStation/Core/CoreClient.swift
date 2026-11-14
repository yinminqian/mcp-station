import Foundation

/// App 与后台 core 之间的唯一接口。
///
/// 现在由 `LocalCore` 实现：配置真实读写 config.json，各 MCP 在 App 里真实握手检测。
/// 网关（core）做好后换成 HTTP 实现（`/control/*`，见 docs/ARCHITECTURE.md §4.1），界面代码不需要改。
///
/// 状态以「推」为主：`updates()` 按粒度推送变化，store 只替换变了的那一块，
/// 这样调用记录每秒刷新时，MCP 列表不会跟着重绘。
protocol CoreClient: Sendable {
    func updates() -> AsyncStream<CoreUpdate>

    func setDefault(mcp: String, on: Bool) async throws
    func restart(mcp: String) async throws
    func retryNow(mcp: String) async throws
    func addMCP(_ draft: MCPDraft) async throws

    func createService(name: String, mcps: [String]) async throws
    func setServiceMembers(service: String, mcps: [String]) async throws
    func renameService(_ name: String, to newName: String) async throws
    func deleteService(_ name: String) async throws

    func restartCore() async throws
    /// 改网关端口（写进配置）。
    func setPort(_ port: Int) async throws

    /// 导入一份配置（本软件导出的文件，或 Claude / Cursor 等的 `mcpServers`），合并进当前配置。返回给人看的结果。
    func importConfig(_ data: Data) async throws -> String
    /// 当前配置的完整内容（含密钥明文）。
    func exportConfig() async throws -> Data

    /// 直接调一次某个 MCP 的工具（`tools/call`），结果记进调用记录。参数是一段 JSON 对象文本。
    func callTool(mcp: String, tool: String, argumentsJSON: String) async throws -> ToolCallResult
}

enum CoreUpdate: Sendable {
    /// 首次连接或重连后的完整状态。
    case snapshot(CoreStatus, [MCPServer], [NamedService], [CallRecord])
    case core(CoreStatus)
    case mcp(MCPServer)
    case services([NamedService])
    case calls([CallRecord])
    /// 一次内存采样：后台服务自身 + 各 MCP。合成一条推送，避免每 5 秒推 14 次。
    case memory(core: Int64?, mcps: [String: Int64])
}

enum CoreError: LocalizedError {
    case notRunning
    case unknownMCP(String)
    case invalidName(String)
    case duplicateName(String)
    case duplicateMCP(String)
    case missingField(String)
    case invalidPort(Int)

    var errorDescription: String? {
        switch self {
        case .notRunning: "后台服务没有运行"
        case .unknownMCP(let n): "找不到 MCP「\(n)」"
        case .invalidName(let n): "名字「\(n)」不合法：只能用字母、数字、- 和 _"
        case .duplicateName(let n): "已经有叫「\(n)」的服务了"
        case .duplicateMCP(let n): "已经有叫「\(n)」的 MCP 了"
        case .missingField(let f): "请填写「\(f)」"
        case .invalidPort(let p): "端口 \(p) 不行：要在 1024 到 65535 之间"
        }
    }
}
