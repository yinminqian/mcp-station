import SwiftUI

/// 左侧导航栏：品牌、四个主页面，底部是设置和后台服务状态。每项是"图标 + 文字"，选中整行铺淡色底。
/// 窗口窄（`isCompact`，由 `BentoRoot` 按窗口宽度决定）时收成只有图标的窄条，图标位置不动。
/// 2026-11-14 按用户给的参考图（图标 + 文字、选中淡色底）重做，方案出自 Fable 评审。
struct BentoRail: View {
    var isCompact = false

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @State private var showsCore = false

    private static let mainRoutes: [Navigator.Route] = [.overview, .mcps, .services, .calls]

    var body: some View {
        let coreDown = store.core?.canManage == false

        VStack(alignment: .leading, spacing: BentoSpace.s4) {
            brand
            ForEach(Self.mainRoutes) { route in
                BentoSidebarRow(icon: route.bentoIcon, title: route.title,
                                isSelected: nav.route == route,
                                count: route == .mcps && !coreDown ? store.attention.count : 0,
                                isDimmed: coreDown && route != .overview,
                                isCompact: isCompact) { nav.route = route }
            }
            Spacer(minLength: BentoSpace.s8)
            BentoSidebarRow(icon: .settings, title: Navigator.Route.settings.title,
                            isSelected: nav.route == .settings, isCompact: isCompact) { nav.route = .settings }
            coreStatus
        }
        .padding(.horizontal, BentoSpace.s8)
        .padding(.vertical, BentoSpace.s12)
        .frame(width: isCompact ? BentoMetric.railWidth : BentoMetric.sidebarWidth)
        .background(BentoColor.Bg.panel, in: RoundedRectangle(cornerRadius: BentoRadius.xl, style: .continuous))
    }

    /// 圆标和下面各行的图标同一条中轴，名字和各行文字左对齐。
    private var brand: some View {
        HStack(spacing: BentoSpace.s8) {
            BentoIconCircle(icon: .brand, size: BentoSpace.s32,
                            fill: BentoColor.Ink.black, ink: BentoColor.Ink.inverse)
            if !isCompact {
                VStack(alignment: .leading, spacing: 0) {
                    Text("MCP Station").bentoText(.title, BentoColor.Ink.black)
                    Text("本机 MCP 网关").bentoText(.label, BentoColor.Ink.secondary)
                }
                .lineLimit(1)
            }
        }
        .frame(height: BentoSpace.s40)
        .padding(.leading, BentoSpace.s8)
        .padding(.bottom, BentoSpace.s16)
    }

    /// 「● 网关还没接入」，点开气泡看详情和重新检测。收窄时只剩圆点。
    private var coreStatus: some View {
        let headline = store.core.bentoHeadline
        return Button { showsCore = true } label: {
            Label {
                Text(headline).bentoText(.label, BentoColor.Ink.secondary)
            } icon: {
                BentoStatusDot(status: BentoStatus(core: store.core), size: BentoSpace.s8)
            }
        }
        .buttonStyle(BentoSidebarRowStyle(isCompact: isCompact))
        .popover(isPresented: $showsCore, arrowEdge: .trailing) { BentoCorePopover() }
        .accessibilityLabel(headline)
        .help(isCompact ? headline : "")
    }
}

/// 点底部状态行弹出的气泡：后台服务的状态和重新检测。
private struct BentoCorePopover: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let core = store.core
        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            HStack(spacing: BentoSpace.s8) {
                BentoStatusDot(status: BentoStatus(core: core))
                Text(core.bentoHeadline).bentoText(.title)
            }
            BentoCoreDetailLine(core: core).bentoText(.body, BentoColor.Ink.secondary)
            if let core {
                Text("127.0.0.1:\(String(core.port)) · v\(core.version)")
                    .bentoText(.mono, BentoColor.Ink.secondary)
            }
            BentoRestartCoreButton(tone: .ink)
        }
        .padding(BentoSpace.s20)
        .frame(minWidth: 240, alignment: .leading)
        .background(BentoColor.Bg.window)
        .environment(\.colorScheme, .light)
    }
}
