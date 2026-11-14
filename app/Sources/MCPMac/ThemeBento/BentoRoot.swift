import SwiftUI

/// Pastel Bento 主题的主窗口：左边侧边栏（窄窗口时收成图标条），右边按当前页面挂内容。
///
/// 这里只做版式。它不读调用记录、统计这类每秒变化的数据，这些只在用到的叶子视图里读，
/// 这样调用记录刷新时整个窗口不会跟着重绘。
struct BentoRoot: View {
    @Environment(AppStore.self) private var store
    /// 窗口窄于 `sidebarCollapseBelow` 时，侧边栏收成只有图标。
    @State private var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            BentoRail(isCompact: isCompact)
                .padding(.leading, BentoMetric.windowInset)
                .padding(.top, BentoMetric.titleBarInset)
                .padding(.bottom, BentoMetric.windowInset)
            BentoPageHost()
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < BentoMetric.sidebarCollapseBelow } action: { isCompact = $0 }
        .background(BentoColor.Bg.window)
        .overlay(alignment: .top) { BentoWindowTitle() }
        .overlay(alignment: .bottom) { BentoToastHost() }
        .ignoresSafeArea()
        .toggleStyle(.bento)
        .environment(\.bentoCoreRunning, store.core?.canManage ?? false)
        .environment(\.colorScheme, .light)
    }
}

/// 按 `Navigator.route` 切换页面，直接切换、不做过渡动画。
private struct BentoPageHost: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(CopyFeedback.self) private var copy

    var body: some View {
        // 页面常驻（AppKit 层，见 Shared/KeepAlivePages）
        KeepAlivePages(selection: nav.route) { [store, nav, copy] route in
            AnyView(BentoPage(route: route)
                .environment(store).environment(nav).environment(copy))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BentoPage: View {
    let route: Navigator.Route
    @Environment(AppStore.self) private var store

    var body: some View {
        content
            .toggleStyle(.bento)
            .environment(\.bentoCoreRunning, store.core?.canManage ?? false)
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .overview: BentoOverviewPage()
        case .mcps: BentoMCPsPage()
        case .services: BentoServicesPage()
        case .calls: BentoCallsPage()
        case .settings: BentoSettingsPage()
        }
    }
}

/// 透明标题栏正中的小标题。
/// 后台服务没运行、又不在概览页时，这里换成一条提示和「重启」。
private struct BentoWindowTitle: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        let showsCoreDown = nav.route != .overview && BentoStatus(core: store.core) == .error
        ZStack {
            if showsCoreDown {
                BentoCoreDownBadge().transition(.opacity)
            } else {
                Text("MCP Mac — \(nav.route.title)")
                    .bentoText(.label, BentoColor.Ink.tertiary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .frame(height: BentoMetric.titleBarInset)
        .animation(BentoMotion.smooth, value: showsCoreDown)
    }
}

extension View {
    /// 页面内容的外边距：左边和图标栏隔开，上面让出红绿灯，右下贴窗口内边距。
    func bentoPageInsets() -> some View {
        padding(.leading, BentoSpace.s20)
            .padding(.top, BentoMetric.titleBarInset)
            .padding(.trailing, BentoMetric.windowInset)
            .padding(.bottom, BentoMetric.windowInset)
    }
}
