import SwiftUI

/// Liquid Glass 主题的窗口工具栏：在根视图声明一次，**工具项集合固定**，切换分区只改内容、文字和是否可用。
///
/// 为什么：每个页面各自声明 `.toolbar`/`.searchable` 时，切页会让 NSToolbar 删掉再新建所有工具项
/// （2026-11-14 实测 MCP 页、服务页每次切入 131～136ms，见 docs/perf/REPORT-01-baseline.md）。
/// HIG 也要求工具栏分组和位置在各处保持一致。
///
/// 规则：这里的 ToolbarContentBuilder 里不写 `if`/`switch`（那会增删工具项），条件只放在工具项内部的视图里。
struct GlassToolbar: ToolbarContent {
    let store: AppStore
    let nav: Navigator

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            GlassFilterMenu(nav: nav)
        }
        ToolbarItem(placement: .principal) {
            GlassSectionPicker(nav: nav)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            GlassMainAction(store: store, nav: nav)
            GlassMoreMenu(store: store, nav: nav)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("添加 MCP…") {
                    nav.route = .mcps
                    nav.request = .addMCP
                }
                Button("新建服务…") {
                    nav.route = .services
                    nav.request = .createService
                }
            } label: { Label("添加", systemImage: "plus") }
            .help("添加 MCP 或新建服务")
            .disabled(!(store.core?.canManage ?? false))
        }
    }
}

/// 左侧筛选：只对 MCP 页生效，其他分区置灰（不隐藏，保持位置稳定）。
private struct GlassFilterMenu: View {
    @Bindable var nav: Navigator

    var body: some View {
        Menu {
            Picker("筛选", selection: $nav.mcpFilter) {
                ForEach(Navigator.MCPFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("筛选", systemImage: nav.mcpFilter == .all
                  ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("筛选 MCP：\(nav.mcpFilter.title)")
        .disabled(nav.route != .mcps)
    }
}

/// 中间的分段控件：同一个 Picker 实例，按分区换段，不重建控件；没有分段的分区把它隐藏但保留占位。
private struct GlassSectionPicker: View {
    @Bindable var nav: Navigator

    private struct Segment: Identifiable { let id: String; let title: String }

    private var segments: [Segment] {
        switch nav.route {
        case .mcps:
            [.init(id: "overview", title: String(localized: "概况")), .init(id: "tools", title: String(localized: "工具")),
             .init(id: "resources", title: "Resources"), .init(id: "logs", title: String(localized: "日志")), .init(id: "calls", title: String(localized: "调用"))]
        case .services:
            [.init(id: "members", title: String(localized: "组成")), .init(id: "tools", title: String(localized: "工具")),
             .init(id: "instructions", title: String(localized: "说明")), .init(id: "calls", title: String(localized: "调用"))]
        case .calls:
            Navigator.CallFilter.allCases.map { .init(id: $0.rawValue, title: $0.title) }
        case .overview, .settings:
            []
        }
    }

    private var selection: Binding<String> {
        Binding {
            switch nav.route {
            case .mcps: nav.mcpTab.rawValue
            case .services: nav.serviceTab.rawValue
            case .calls: nav.callFilter.rawValue
            case .overview, .settings: ""
            }
        } set: { v in
            switch nav.route {
            case .mcps: if let t = Navigator.MCPTab(rawValue: v) { nav.mcpTab = t }
            case .services: if let t = Navigator.ServiceTab(rawValue: v) { nav.serviceTab = t }
            case .calls: if let f = Navigator.CallFilter(rawValue: v) { nav.callFilter = f }
            case .overview, .settings: break
            }
        }
    }

    var body: some View {
        let segs = segments
        Picker("视图", selection: selection) {
            ForEach(segs) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // 按内容撑开，不让工具栏把分段标题压成"聚…"
        .fixedSize()
        .opacity(segs.isEmpty ? 0 : 1)
        .allowsHitTesting(!segs.isEmpty)
        .accessibilityHidden(segs.isEmpty)
        .disabled(nav.route == .mcps && nav.selectedMCP == nil)
    }
}

/// 右侧主操作：位置固定，含义随分区变化。
private struct GlassMainAction: View {
    let store: AppStore
    let nav: Navigator

    var body: some View {
        let a = action
        Button(action: a.run) { Label(a.title, systemImage: a.symbol) }
            .help(a.title)
            .disabled(!a.enabled)
    }

    private struct Action { var title: String; var symbol: String; var enabled: Bool; var run: () -> Void }

    private var action: Action {
        let running = store.core?.canManage ?? false
        switch nav.route {
        case .overview, .settings:
            return Action(title: store.core?.restartTitle ?? String(localized: "重新检测"), symbol: "arrow.triangle.2.circlepath",
                          enabled: !store.isBusy("core-restart")) { store.restartCore() }
        case .mcps:
            guard let m = store.mcp(nav.selectedMCP) else {
                return Action(title: String(localized: "重启"), symbol: "arrow.clockwise", enabled: false) {}
            }
            let backoff: Bool = { if case .backoff = m.state { true } else { false } }()
            return Action(title: backoff ? String(localized: "立即重试") : String(localized: "重启 \(m.name)"), symbol: "arrow.clockwise",
                          enabled: running && m.state != .stopped
                              && !store.isBusy("restart:\(m.name)") && !store.isBusy("retry:\(m.name)")) {
                backoff ? store.retryNow(m.name) : store.restart(m.name)
            }
        case .services:
            let s = store.service(nav.selectedService)
            return Action(title: String(localized: "重命名"), symbol: "pencil", enabled: running && s != nil && s?.isDefault == false) {
                if let s { nav.request = .renameService(s.name) }
            }
        case .calls:
            let filtered = nav.callFilter != .all || !nav.callSearch.isEmpty
            return Action(title: String(localized: "清除筛选"), symbol: "line.3.horizontal.decrease.circle", enabled: filtered) {
                nav.callFilter = .all
                nav.callSearch = ""
            }
        }
    }
}

/// "更多"菜单：位置固定，菜单项随分区变化（菜单项不是工具项，变化不触发工具栏重建）。
private struct GlassMoreMenu: View {
    let store: AppStore
    let nav: Navigator

    var body: some View {
        Menu {
            let port = store.core?.port ?? ConfigFile.defaultPort
            switch nav.route {
            case .mcps:
                if let m = store.mcp(nav.selectedMCP) {
                    Button("复制单独地址") {
                        Clipboard.copy(Format.mcpURL(m.name, port: port))
                        store.showToast(String(localized: "已复制 \(m.name) 的单独地址"))
                    }
                    Button(m.inDefault ? "从默认服务移除" : "加入默认服务") { store.setDefault(m.name, on: !m.inDefault) }
                }
            case .services:
                if let s = store.service(nav.selectedService) {
                    Button("复制地址") {
                        Clipboard.copy(Format.serviceURL(s, port: port))
                        store.showToast(String(localized: "已复制 \(s.name) 的地址"))
                    }
                    Divider()
                    Button("删除服务…", role: .destructive) { nav.request = .deleteService(s.name) }
                        .disabled(s.isDefault)
                }
            case .overview, .calls, .settings:
                Button(store.core?.restartTitle ?? String(localized: "重新检测")) { store.restartCore() }
            }
        } label: {
            Label("更多", systemImage: "ellipsis")
        }
        .help("更多")
    }
}
