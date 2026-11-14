import SwiftUI

// 这套主题自己加的一层「长相」：MCP 的分组、图标、色调，服务的图标和色调。
// core 的数据里没有这些概念，所以放在主题里，用一张小表维护；表里没有的按启动方式兜底。

/// 概览页的分组筛选。
enum BentoGroup: String, CaseIterable, Identifiable {
    case all, dev, data, design, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "全部")
        case .dev: String(localized: "开发")
        case .data: String(localized: "数据")
        case .design: String(localized: "设计")
        case .system: String(localized: "系统")
        }
    }

    var icon: BentoIcon {
        switch self {
        case .all: .groupAll
        case .dev: .groupDev
        case .data: .groupData
        case .design: .groupDesign
        case .system: .groupSystem
        }
    }

    func contains(_ mcp: MCPServer) -> Bool {
        self == .all || BentoCatalog.look(of: mcp).group == self
    }
}

struct BentoMCPLook {
    var group: BentoGroup
    var tone: BentoTone
    var icon: BentoIcon
}

enum BentoCatalog {
    private static let known: [String: BentoMCPLook] = [
        "XcodeBuildMCP": BentoMCPLook(group: .dev, tone: .lavender, icon: .package),
        "metro": BentoMCPLook(group: .dev, tone: .lavender, icon: .brand),
        "mobile": BentoMCPLook(group: .dev, tone: .sky, icon: .phone),
        "chrome-devtools": BentoMCPLook(group: .dev, tone: .sky, icon: .browser),
        "clickhouse": BentoMCPLook(group: .data, tone: .mint, icon: .database),
        "obsidian": BentoMCPLook(group: .data, tone: .lavender, icon: .note),
        "pencil": BentoMCPLook(group: .design, tone: .sky, icon: .groupDesign),
        "wordcraft": BentoMCPLook(group: .design, tone: .sky, icon: .document),
        "desktop": BentoMCPLook(group: .system, tone: .mint, icon: .terminal),
        "iterm": BentoMCPLook(group: .system, tone: .mint, icon: .terminal),
        "peekaboo": BentoMCPLook(group: .system, tone: .sky, icon: .eye),
    ]

    private static let knownServiceIcons: [String: BentoIcon] = [
        "ios": .phone,
        "data": .database,
    ]

    static func look(of mcp: MCPServer) -> BentoMCPLook {
        if let look = known[mcp.name] { return look }
        return switch mcp.kind {
        case .http: BentoMCPLook(group: .data, tone: .sky, icon: .http)
        case .npx, .uvx: BentoMCPLook(group: .dev, tone: .lavender, icon: .package)
        case .command: BentoMCPLook(group: .system, tone: .mint, icon: .terminal)
        }
    }

    static func icon(of service: ServiceSummary) -> BentoIcon {
        service.isDefault ? .services : knownServiceIcons[service.name] ?? .services
    }
}

extension MCPServer {
    /// 卡片的色调：状态优先（等待重试 peach、配置错误 rose、已停止灰），正常时用表里的颜色。
    var bentoCardTone: BentoTone {
        switch state {
        case .backoff: .peach
        case .configError: .rose
        case .stopped: .sunken
        case .ready, .starting: BentoCatalog.look(of: self).tone
        }
    }
}

/// 每个服务的色调。默认服务固定 lavender，命名服务按顺序轮流取色；
/// 概览的柱状图、服务卡片、MCP 卡片上的服务圆章都用这同一份，颜色才对得上。
struct BentoServiceTones {
    private let byName: [String: BentoTone]

    init(_ services: [ServiceSummary]) {
        var map: [String: BentoTone] = [:]
        var named = 0
        for service in services {
            if service.isDefault {
                map[service.name] = .lavender
            } else {
                map[service.name] = BentoTone.serviceCycle[named % BentoTone.serviceCycle.count]
                named += 1
            }
        }
        byName = map
    }

    subscript(name: String) -> BentoTone { byName[name] ?? .stone }
}
