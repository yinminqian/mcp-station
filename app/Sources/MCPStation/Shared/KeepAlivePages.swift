import AppKit
import SwiftUI

/// 页面常驻容器（AppKit 层）：每个页面第一次打开时创建一个独立的 NSHostingView，之后一直保留；
/// 未选中的页面从窗口里取下——不布局、不绘制、不收事件，也不跟着别的页面更新。
///
/// 为什么不用 switch：每个分支是新的视图身份，切页就销毁旧页、从零重建，带原生表格/表单的页面每次 200～300ms
/// （docs/perf/REPORT-02-toolbar.md）。
///
/// 为什么不用 SwiftUI 的 ZStack 常驻（docs/perf/REPORT-03-keepalive.md）：所有页面在同一张视图图里，
/// 隐藏页照样跟着每秒的数据刷新布局、提交图层（空闲 CPU 翻倍、内存多 100MB），根部变化还要逐个下发给
/// 所有常驻页的上千个原生视图（每次切页约 45ms）；切换 allowsHitTesting 再多约 100ms。
///
/// 为什么不用 NSTabViewController（docs/perf/REPORT-04-appkit-container.md）：NSTabView 每次切换都为新页
/// 重算整页的键盘焦点环（`_setDefaultKeyViewLoop`），连带约束更新和表格行高重算，调用记录页一次 81～105ms。
/// 这里只做"挂上 / 取下子视图"，用 autoresizing 填满，不加约束。
///
/// 约定：
/// - `make` 只在页面第一次被选中时调用一次。页面需要的环境（store、nav 等）必须在 `make` 里显式注入——
///   不转发外层环境，否则等于把"环境值逐个下发"原样搬回来。
/// - 页面里不要声明 `.toolbar` / `.searchable` / `.navigationTitle`：它们由各主题的根视图统一声明。
struct KeepAlivePages<ID: Hashable>: NSViewRepresentable {
    let selection: ID
    let make: (ID) -> AnyView

    func makeNSView(context: Context) -> PagesContainerView<ID> {
        PagesContainerView(make: make)
    }

    func updateNSView(_ view: PagesContainerView<ID>, context: Context) {
        view.show(selection)
    }
}

final class PagesContainerView<ID: Hashable>: NSView {
    private let make: (ID) -> AnyView
    private var hosts: [ID: NSHostingView<AnyView>] = [:]
    private var current: ID?

    init(make: @escaping (ID) -> AnyView) {
        self.make = make
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError(String(localized: "不从 nib 创建")) }

    /// 换页：容器里始终只挂当前这一页，直接替换、不做过渡动画（macOS 侧边栏切换内容的惯例）。
    /// 页面背景是透明的，任何淡入淡出都会让两页内容叠在一起显示（2026-11-14 用户反馈"重影"）。
    func show(_ id: ID) {
        guard current != id else { return }
        let incoming = host(for: id)
        let outgoing = current.flatMap { hosts[$0] }
        current = id
        incoming.frame = bounds
        if let outgoing, outgoing.superview === self {
            replaceSubview(outgoing, with: incoming)
        } else {
            addSubview(incoming)
        }
    }

    private func host(for id: ID) -> NSHostingView<AnyView> {
        if let h = hosts[id] { return h }
        let h = NSHostingView(rootView: make(id))
        // 不把页面内容的固有尺寸报给 AppKit：页面填满容器即可，避免撑大窗口最小尺寸或引起重入布局
        h.sizingOptions = []
        h.autoresizingMask = [.width, .height]
        hosts[id] = h
        return h
    }
}
