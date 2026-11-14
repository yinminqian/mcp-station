import Foundation
import Observation

/// 页面与选中项。两套主题共用同一个实例，所以切换主题后停留在原页面、选中项也保留。
@MainActor @Observable
final class Navigator {
    enum Route: String, CaseIterable, Identifiable {
        case overview, mcps, services, calls, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: String(localized: "概览")
            case .mcps: "MCP"
            case .services: String(localized: "服务")
            case .calls: String(localized: "调用记录")
            case .settings: String(localized: "设置")
            }
        }

        var symbol: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .mcps: "puzzlepiece.extension"
            case .services: "point.3.connected.trianglepath.dotted"
            case .calls: "clock.arrow.circlepath"
            case .settings: "gearshape"
            }
        }
    }

    enum MCPTab: String, CaseIterable, Identifiable {
        case overview, tools, resources, logs, calls
        var id: String { rawValue }
    }

    enum CallFilter: String, CaseIterable, Identifiable {
        case all = "全部", errors = "错误", slow = "慢调用"
        var id: String { rawValue }
        /// 给人看的名字（翻译过的）；rawValue 是固定的标识。
        var title: String { String(localized: String.LocalizationValue(rawValue)) }

        /// 慢调用的门槛，两套主题共用。
        static let slowThreshold: Duration = .seconds(2)

        static func isSlow(_ c: CallRecord) -> Bool { (c.duration ?? .zero) >= slowThreshold }

        func matches(_ c: CallRecord) -> Bool {
            switch self {
            case .all: true
            case .errors: c.isError
            case .slow: Self.isSlow(c)
            }
        }
    }

    enum MCPFilter: String, CaseIterable, Identifiable {
        case all = "全部", attention = "需要关注", stopped = "已停止"
        var id: String { rawValue }
        var title: String { String(localized: String.LocalizationValue(rawValue)) }
    }

    enum ServiceTab: String, CaseIterable, Identifiable {
        case members, tools, instructions, calls
        var id: String { rawValue }
    }

    /// 需要界面弹出输入或确认的操作。工具栏、菜单栏命令发出请求，当前主题负责呈现。
    enum Request: Identifiable, Equatable {
        case addMCP
        case createService
        case renameService(String)
        case deleteService(String)

        var id: String {
            switch self {
            case .addMCP: "add-mcp"
            case .createService: "create"
            case .renameService(let n): "rename:\(n)"
            case .deleteService(let n): "delete:\(n)"
            }
        }
    }

    var route: Route = .overview
    var selectedMCP: String?
    var selectedService: String? = String(localized: "默认")
    var mcpTab: MCPTab = .overview
    var mcpFilter: MCPFilter = .all
    var serviceTab: ServiceTab = .members
    var callFilter: CallFilter = .all
    /// 搜索文字按页面分开：MCP 页和调用记录页各一份，切页不会带着上一页的筛选。
    var mcpSearch = ""
    var callSearch = ""
    var request: Request?

    func show(mcp name: String) {
        selectedMCP = name
        mcpTab = .overview
        route = .mcps
    }

    func show(service name: String) {
        selectedService = name
        route = .services
    }
}
