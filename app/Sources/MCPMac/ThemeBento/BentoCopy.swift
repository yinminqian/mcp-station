import Foundation

/// 这套主题里重复出现的几句文案。只拼字，不做业务判断。
enum BentoCopy {
    /// 「被 默认、ios 使用」；没开默认开关时补一句「默认已关」。
    static func usage(usedBy: [String], inDefault: Bool) -> String {
        guard !usedBy.isEmpty else { return "没有服务用到" }
        let base = "被 \(usedBy.joined(separator: "、")) 使用"
        return inDefault ? base : base + " · 默认已关"
    }

    /// 状态一句话；等待重试时带上已经试了几次。
    static func stateLine(_ state: MCPState) -> String {
        if case .backoff(_, _, let attempts) = state {
            return "\(Format.stateLabel(state)) · 已重试 \(attempts) 次"
        }
        return Format.stateLabel(state)
    }

    static func address(port: Int) -> String { "127.0.0.1:\(port)" }

    /// 服务的健康状况：「3 个都正常」/「1 个不正常」/「还没有 MCP」。
    static func health(_ service: ServiceSummary) -> (text: String, status: BentoStatus) {
        let count = service.members.count
        if count == 0 { return ("还没有 MCP", .idle) }
        if service.healthy == count { return ("\(count) 个都正常", .ok) }
        return ("\(count - service.healthy) 个不正常", .warn)
    }

    /// 登录时打开：要等网关（LaunchAgent）接入后才做。
    static let loginItemLater = "网关接入后开放"
}
