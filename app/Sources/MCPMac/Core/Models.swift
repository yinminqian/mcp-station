import Foundation

// 与 core 控制接口（docs/ARCHITECTURE.md §4.1）一一对应的数据模型。
// 界面只依赖这些值类型；它们来自 CoreClient，不在界面里拼。

/// MCP 的启动方式。界面上的"类型"由它推出，不单独存。
enum MCPKind: String, Codable, Sendable, CaseIterable {
    case npx, uvx, command, http

    var label: String {
        switch self {
        case .npx: "npx"
        case .uvx: "uvx"
        case .command: "命令"
        case .http: "HTTP"
        }
    }

    /// 启动目标叫什么：既是定义里那一行的名字，也是新增表单里的输入框标题。
    var targetLabel: String {
        switch self {
        case .npx, .uvx: "包"
        case .command: "命令"
        case .http: "地址"
        }
    }

    var targetPrompt: String {
        switch self {
        case .npx: "@modelcontextprotocol/server-filesystem"
        case .uvx: "mcp-server-fetch"
        case .command: "/opt/homebrew/bin/python3"
        case .http: "https://example.com/mcp"
        }
    }

    /// 每行一条的附加配置：本地进程是环境变量，HTTP 上游是请求头。
    var extraLabel: String { self == .http ? "请求头" : "环境变量" }
    var extraPrompt: String { self == .http ? "每行一个，如 Authorization: Bearer xxx" : "每行一个，如 API_KEY=xxx" }
}

/// 新增 MCP 时填的定义，对应 `POST /control/mcps` 的请求体（docs/ARCHITECTURE.md §4.1）。
struct MCPDraft: Sendable, Equatable {
    var name = ""
    var kind: MCPKind = .npx
    /// npx / uvx 是包名，命令是可执行文件，HTTP 是地址。
    var target = ""
    /// 启动参数，空格分开。HTTP 上游不用。
    var args = ""
    /// 每行一条：环境变量 `KEY=VALUE`，或 HTTP 请求头 `名字: 值`。
    var extra = ""
    /// 新加的 MCP 默认加入默认服务（docs/ARCHITECTURE.md §1）。
    var inDefault = true
}

/// 上游的运行状态。和 `/control/status` 的 state 字段对应。
enum MCPState: Hashable, Sendable {
    case starting
    case ready
    /// 失败后等待重试。`retryAt` 用绝对时间，界面自己算倒计时，core 不需要每秒推送。
    case backoff(reason: String, retryAt: Date, attempts: Int)
    case configError(String)
    /// 没有任何服务用到它，所以没在运行。
    case stopped

    var isHealthy: Bool { if case .ready = self { true } else { false } }
    var needsAttention: Bool {
        switch self {
        case .backoff, .configError: true
        default: false
        }
    }
}

struct ToolInfo: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var summary: String
    /// 参数的 JSON Schema（tools/list 返回的 inputSchema，已排好版）。试调用时用来生成参数模板。
    var inputSchema: String? = nil
    /// 完整说明（summary 只留第一行）。网关的 tools/list 原样给客户端。
    var description: String? = nil
}

/// 试调用一个工具的结果。
struct ToolCallResult: Sendable {
    var isError: Bool
    /// 返回内容里的文字（图片等非文字内容写成占位说明），过长时截断。
    var text: String
    var duration: Duration
}

struct LogLine: Identifiable, Hashable, Sendable {
    enum Level: Sendable { case info, warn, error }
    let id: Int
    var time: Date
    var level: Level
    var text: String
}

/// 定义里的一行（类型、地址、证书…）。`secret` 为真时界面默认打码。
struct DefinitionField: Identifiable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var value: String
    var secret = false
    var monospaced = false
}

struct MCPServer: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var kind: MCPKind
    var definition: [DefinitionField]
    var tools: [ToolInfo]
    var resourceCount: Int
    var promptCount: Int
    var instructionsLength: Int
    /// 开关：是否在默认服务里。
    var inDefault: Bool
    var state: MCPState
    var pid: Int?
    var startedAt: Date?
    var restarts: Int
    var stderr: [LogLine]
    /// 进程组（含 npx/uvx 留下的孙子进程）的 RSS 合计，字节。没在运行或 HTTP 上游（无本地进程）时为 nil。
    var memory: Int64? = nil
    /// 最近 30 次采样（每 5 秒一次），画趋势用。
    var memoryHistory: [Int64] = []

    var toolCount: Int { tools.count }
}

/// 命名服务。默认服务不在这里，它由各 MCP 的开关推出。
struct NamedService: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var mcpNames: [String]
    var sessions: Int
}

struct CallRecord: Identifiable, Hashable, Sendable, Codable {
    enum Outcome: Hashable, Sendable, Codable {
        case ok
        case error(String)
    }
    let id: Int
    var time: Date
    var mcp: String
    var tool: String
    var service: String
    var client: String
    var duration: Duration?
    var outcome: Outcome

    var isError: Bool { if case .error = outcome { true } else { false } }
}

enum CoreState: Equatable, Sendable {
    case running(pid: Int, since: Date)
    /// 网关还没接入：配置可以管理、各 MCP 可以检测，但客户端还连不上服务地址。
    case notInstalled
    /// 后台服务没在运行。`reason` 来自 core.log / launchctl，不依赖 core 本身。
    case stopped(reason: CoreDownReason)
    case restarting
}

struct CoreDownReason: Equatable, Sendable {
    var title: String
    var detail: String
    var occupiedBy: String?
    var lastExitCode: Int
    var logTail: [String]
}

struct CoreStatus: Equatable, Sendable {
    var version: String
    var port: Int
    var state: CoreState
    var defaultSessions: Int
    /// 后台服务自身的 RSS，字节。
    var memory: Int64? = nil

    var isRunning: Bool { if case .running = state { true } else { false } }
    /// "重启"按钮叫什么：网关没接入时它的作用是重新读配置、重新检测。
    var restartTitle: String { state == .notInstalled ? "重新检测" : "重启后台服务" }
    /// 能不能改配置、检测 MCP。网关没接入时也可以。
    var canManage: Bool {
        switch state {
        case .running, .notInstalled: true
        case .stopped, .restarting: false
        }
    }
}

/// 安装布局（docs/ARCHITECTURE.md §2）。core 挂掉时界面也要能显示，所以是常量，不从 core 取。
enum CoreInstall {
    static let launchdLabel = "com.example.mcp-mac.core"
    static let supportDir = "~/Library/Application Support/MCP Mac"
    static let binaryPath = supportDir + "/bin/mcp-core"
    static let configPath = supportDir + "/config.json"
    static let logPath = supportDir + "/logs/core.log"
}
