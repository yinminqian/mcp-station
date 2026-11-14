import SwiftUI

/// 卡片：一块圆角色块。粉彩卡片、白卡片、深色日志块都是它，只是色调不同。
struct BentoCard<Content: View>: View {
    var tone: BentoTone = .surface
    var radius: CGFloat = BentoRadius.lg
    var padding: CGFloat = BentoSpace.s20
    /// 选中时描一圈黑边。
    var isSelected = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.fill, in: shape)
            .overlay(shape.strokeBorder(BentoColor.Ink.black, lineWidth: BentoMetric.selectionStroke)
                .opacity(isSelected ? 1 : 0))
            .animation(BentoMotion.hover, value: isSelected)
    }
}

/// 整张卡片可点时的反馈：悬停上浮并出现投影，按下微缩。
struct BentoCardButtonStyle: ButtonStyle {
    var radius: CGFloat = BentoRadius.lg

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, radius: radius)
    }

    private struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        let radius: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .contentShape(shape)
                .shadow(color: BentoColor.Ink.black.opacity(hovering ? BentoOpacity.shadow : 0),
                        radius: BentoSpace.s12, y: BentoSpace.s6)
                .offset(y: hovering && !reduceMotion ? BentoMotion.hoverLift : 0)
                .scaleEffect(configuration.isPressed ? BentoMotion.pressedScale : 1)
                .onHover { hovering = $0 }
                .animation(BentoMotion.hover, value: hovering)
                .animation(BentoMotion.hover, value: configuration.isPressed)
        }
    }
}

extension List {
    /// 卡片里的整块列表：系统 List（底层 NSTableView，行复用，滚动手感和系统列表一致），去掉系统底色，
    /// 铺满卡片、按卡片圆角裁切；留白放在内容边距里，所以内容滚到卡片边缘自然消失在圆角下，滚动条贴着卡片边缘、上下避开圆角。
    /// 不要在卡片上加内边距再套列表：内容会在离边缘一段距离处被平直切断，和圆角对不上（2026-11-14 用户反馈）。
    /// 不要用 ScrollView + LazyVStack 做长列表：行不复用、滚动时现建，滑起来不顺（同日用户反馈，方案出自 Fable 评审）。
    /// `underHeader`：列表上方紧挨着卡片里的表头时传 true——顶部不留白、不裁圆角。
    func bentoCardList(radius: CGFloat = BentoRadius.lg, underHeader: Bool = false) -> some View {
        let top: CGFloat = underHeader ? 0 : radius
        return self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins([.horizontal, .bottom], BentoSpace.s8, for: .scrollContent)
            .contentMargins(.top, underHeader ? 0 : BentoSpace.s8, for: .scrollContent)
            .contentMargins(.bottom, radius / 2, for: .scrollIndicators)
            .contentMargins(.top, top / 2, for: .scrollIndicators)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: radius,
                                              bottomTrailingRadius: radius, topTrailingRadius: top, style: .continuous))
    }
}

extension ButtonStyle where Self == BentoCardButtonStyle {
    static func bentoCard(radius: CGFloat = BentoRadius.lg) -> BentoCardButtonStyle {
        BentoCardButtonStyle(radius: radius)
    }
}

/// 详情区的大面板（右侧那块暖灰底）。
struct BentoPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BentoColor.Bg.panel, in: RoundedRectangle(cornerRadius: BentoRadius.xl, style: .continuous))
    }
}

extension View {
    /// 列表行的悬停底色（白卡片里的一行）。
    func bentoRowHover(radius: CGFloat = BentoRadius.sm) -> some View {
        modifier(BentoRowHover(radius: radius))
    }
}

private struct BentoRowHover: ViewModifier {
    let radius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(BentoColor.Bg.panel.opacity(hovering ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(BentoMotion.hover, value: hovering)
    }
}
