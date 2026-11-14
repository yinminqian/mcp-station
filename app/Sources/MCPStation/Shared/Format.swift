import Foundation

/// 两套主题共用的文案格式化。只做格式，不做业务判断。
enum Format {
    static func uptime(since: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(since)))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        if m > 0 { return "\(m) 分钟" }
        return "刚刚"
    }

    static func duration(_ d: Duration?) -> String {
        guard let d else { return "—" }
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        return ms >= 1000 ? String(format: "%.1fs", ms / 1000) : "\(Int(ms))ms"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func time(_ d: Date) -> String { clock.string(from: d) }

    /// 内存：小于 1 GB 用整数 MB，否则保留一位小数的 GB。
    static func bytes(_ b: Int64?) -> String {
        guard let b else { return "—" }
        let mb = Double(b) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return mb < 1 ? "<1 MB" : "\(Int(mb.rounded())) MB"
    }

    static func count(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    /// 状态的一句话描述（不含倒计时，倒计时由视图用 TimelineView 单独渲染）。
    static func stateLabel(_ s: MCPState) -> String {
        switch s {
        case .starting: "启动中"
        case .ready: "正常"
        case .backoff: "等待重试"
        case .configError: "配置错误"
        case .stopped: "已停止"
        }
    }

    static func serviceURL(_ s: ServiceSummary, port: Int, host: String = "127.0.0.1") -> String {
        "http://\(host):\(port)\(s.path)"
    }

    static func mcpURL(_ name: String, port: Int, host: String = "127.0.0.1") -> String {
        "http://\(host):\(port)/servers/\(name)/mcp"
    }

    static func clientCommand(service: ServiceSummary, client: ClientTarget, port: Int) -> String {
        let url = serviceURL(service, port: port, host: client == .container ? "host.docker.internal" : "127.0.0.1")
        let name = service.isDefault ? "mac" : "mac-\(service.name)"
        switch client {
        case .local, .container:
            return "claude mcp add --transport http \(name) \(url)"
        case .json:
            return """
            {
              "mcpServers": {
                "\(name)": { "type": "http", "url": "\(url)" }
              }
            }
            """
        }
    }
}

enum ClientTarget: String, CaseIterable, Identifiable {
    case local = "Claude Code"
    case container = "Docker 容器里"
    case json = "JSON 配置"
    var id: String { rawValue }
}
