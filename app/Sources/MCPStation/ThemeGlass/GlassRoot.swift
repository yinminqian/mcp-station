import SwiftUI

/// Liquid Glass 主题：macOS 原生的侧边栏 + 内容区。玻璃材质全部由系统控件提供，不手画。
struct GlassRoot: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        NavigationSplitView {
            GlassSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            GlassDetail()
        }
        // 工具栏和搜索框挂在这一层：GlassRoot 的 body 不读 nav.route，切页时它不会重新求值，
        // 工具栏声明也就不会被重新提交。挂在会随切页重新求值的 GlassDetail 上时，
        // SwiftUI 每次都会重建整条 NSToolbar（2026-11-14 实测反而更慢）。
        .toolbar { GlassToolbar(store: store, nav: nav) }
        .searchable(text: searchText, placement: .toolbar, prompt: "搜索 MCP 或工具")
        .overlay(alignment: .bottom) { GlassToast() }
    }

    /// 调用记录页搜调用，其余搜 MCP；在没有列表的分区里输入，直接带到 MCP 页。
    private var searchText: Binding<String> {
        Binding {
            nav.route == .calls ? nav.callSearch : nav.mcpSearch
        } set: { v in
            if nav.route == .calls {
                nav.callSearch = v
            } else {
                nav.mcpSearch = v
                if !v.isEmpty && nav.route != .mcps { nav.route = .mcps }
            }
        }
    }
}

private struct GlassDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(CopyFeedback.self) private var copy

    var body: some View {
        ZStack {
            if store.core == nil {
                ProgressView().controlSize(.small)
            } else {
                // 页面常驻：切页只改显示，不销毁重建（见 KeepAlivePages）
                KeepAlivePages(selection: nav.route) { [store, nav, copy] route in
                    AnyView(GlassPage(route: route)
                        .environment(store).environment(nav).environment(copy))
                }
            }
            // 后台服务没运行时盖在上面，不替换常驻页面；恢复后各页原样还在
            if let core = store.core, case .stopped(let reason) = core.state, nav.route != .settings {
                GlassCoreDownPage(core: core, reason: reason)
                    .background(.background)
            }
        }
        .frame(minWidth: 640)
        // 标题随分区变化，留在这里；工具栏和搜索框在 GlassRoot（见那里的说明）
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .modifier(GlassRequestPresenter())
    }

    private var title: String {
        if case .stopped = store.core?.state, nav.route != .settings { return "概览" }
        return nav.route.title
    }

    private var subtitle: String {
        if case .stopped = store.core?.state, nav.route != .settings { return "后台服务没有运行" }
        switch nav.route {
        case .overview: return store.attention.isEmpty ? "一切正常" : "\(store.attention.count) 个 MCP 需要关注"
        case .mcps: return "\(store.mcps.count) 个 · \(store.attention.isEmpty ? "全部正常" : "\(store.attention.count) 个异常")"
        case .services: return "\(store.services.count) 个"
        case .calls: return "最近 \(Format.count(store.calls.count)) 条"
        case .settings: return ""
        }
    }
}

/// 新建 / 重命名 / 删除服务的输入与确认。请求来自工具栏或菜单栏命令（Navigator.request）。
private struct GlassRequestPresenter: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert(alertTitle, isPresented: naming, presenting: nav.request) { req in
                TextField("名字（字母、数字、- 和 _）", text: $draft)
                Button("取消", role: .cancel) {}
                Button(req == .createService ? "创建" : "重命名") { commit(req) }
                    .keyboardShortcut(.defaultAction)
            } message: { req in
                if req == .createService { Text("创建后地址是 /s/<名字>/mcp，再在右边勾选它包含的 MCP。") }
            }
            .confirmationDialog(deleteTitle, isPresented: deleting, presenting: nav.request) { req in
                Button("删除", role: .destructive) {
                    if case .deleteService(let n) = req {
                        store.deleteService(n)
                        nav.selectedService = "默认"
                    }
                }
            } message: { _ in
                Text("连在这个地址上的客户端会断开。它包含的 MCP 如果没有别的服务用到，会被停掉。")
            }
            .sheet(isPresented: adding) { GlassAddMCPSheet() }
            .onChange(of: nav.request) { _, req in
                switch req {
                case .createService: draft = ""
                case .renameService(let n): draft = n
                default: break
                }
            }
    }

    private var alertTitle: String {
        if case .renameService = nav.request { return "重命名服务" }
        return "新建服务"
    }

    private var deleteTitle: String {
        if case .deleteService(let n) = nav.request { return "删除服务「\(n)」？" }
        return ""
    }

    private var naming: Binding<Bool> {
        Binding {
            switch nav.request {
            case .createService, .renameService: true
            default: false
            }
        } set: { if !$0 { nav.request = nil } }
    }

    private var adding: Binding<Bool> {
        Binding { nav.request == .addMCP } set: { if !$0 { nav.request = nil } }
    }

    private var deleting: Binding<Bool> {
        Binding {
            if case .deleteService = nav.request { true } else { false }
        } set: { if !$0 { nav.request = nil } }
    }

    private func commit(_ req: Navigator.Request) {
        let name = draft.trimmingCharacters(in: .whitespaces)
        Task {
            switch req {
            case .createService:
                if await store.createService(name) { nav.selectedService = name; nav.serviceTab = .members }
            case .renameService(let old):
                if await store.renameService(old, to: name) { nav.selectedService = name }
            case .addMCP, .deleteService:
                break
            }
        }
    }
}

/// 单个页面。每个 route 在 KeepAlivePages 里有自己固定的身份，这里的 switch 只决定"这个身份是哪种页面"。
private struct GlassPage: View {
    let route: Navigator.Route

    var body: some View {
        switch route {
        case .overview: GlassOverviewPage()
        case .mcps: GlassMCPPage()
        case .services: GlassServicesPage()
        case .calls: GlassCallsPage()
        case .settings: GlassSettingsPage()
        }
    }
}

private struct GlassSidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        let running = store.core?.canManage ?? false
        List(selection: Binding(get: { nav.route }, set: { if let r = $0 { nav.route = r } })) {
            ForEach(Navigator.Route.allCases) { route in
                let enabled = running || route == .overview || route == .settings
                Label(route.title, systemImage: route.symbol)
                    .badge(route == .mcps && running ? store.attention.count : 0)
                    .foregroundStyle(enabled ? .primary : .tertiary)
                    .tag(route)
                    .selectionDisabled(!enabled)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassCoreBadge()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }
}

/// 侧边栏底部的后台服务状态。
private struct GlassCoreBadge: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let core = store.core {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(color(core.state)).frame(width: 7, height: 7)
                    Text(title(core.state)).font(.callout)
                }
                Group {
                    switch core.state {
                    case .running(let pid, let since):
                        Text("127.0.0.1:\(String(core.port)) · pid \(String(pid))")
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            Text("已运行 \(Format.uptime(since: since, now: ctx.date))")
                        }
                    case .notInstalled:
                        Text("配置和检测可用，客户端还连不上")
                    case .restarting:
                        Text("正在重启…")
                    case .stopped(let r):
                        Text(r.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth, value: core.state)
        }
    }

    private func title(_ s: CoreState) -> String {
        switch s {
        case .running: "后台服务运行中"
        case .notInstalled: "网关还没接入"
        case .restarting: "后台服务重启中"
        case .stopped: "后台服务没有运行"
        }
    }

    private func color(_ s: CoreState) -> Color {
        switch s {
        case .running: .green
        case .notInstalled: .gray
        case .restarting: .yellow
        case .stopped: .red
        }
    }
}

/// 操作失败时从底部浮起的提示。
private struct GlassToast: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if let t = store.toast {
                Label(t.text, systemImage: t.style == .error ? "exclamationmark.triangle.fill" : "info.circle")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(t.id)
            }
        }
        .animation(.snappy, value: store.toast)
    }
}
