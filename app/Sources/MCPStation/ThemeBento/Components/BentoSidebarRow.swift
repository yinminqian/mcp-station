import SwiftUI

/// 侧边栏的一个导航项：图标 + 文字。选中时整行铺淡色底，图标和文字换成色调的深色，文字加粗。
/// （没有换实心图标：有几个入口的 SF Symbol 没有实心版，混着用会不一致；要换得改图标表，会波及侧边栏以外。）
struct BentoSidebarRow: View {
    let icon: BentoIcon
    let title: String
    var isSelected = false
    /// 右侧的数字（有几个 MCP 需要处理）；0 不显示。收窄时变成右上角的小圆点。
    var count = 0
    var isDimmed = false
    var isCompact = false
    let action: () -> Void

    var body: some View {
        let tone = BentoSidebarRowStyle.tone
        Button(action: action) {
            Label {
                Text(title).bentoText(isSelected ? .bodyStrong : .body,
                                      isSelected ? tone.ink : BentoColor.Ink.primary)
            } icon: {
                icon.image
                    .font(.system(size: BentoMetric.iconSize, weight: .medium))
                    .foregroundStyle(isSelected ? tone.ink : BentoColor.Ink.secondary)
            }
            .opacity(isDimmed && !isSelected ? BentoOpacity.dimmed : 1)
        }
        .buttonStyle(BentoSidebarRowStyle(isSelected: isSelected, isCompact: isCompact))
        .overlay(alignment: isCompact ? .topTrailing : .trailing) { badge }
        .animation(BentoMotion.snappy, value: count)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count) 个需要处理" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isCompact ? title : "")
    }

    @ViewBuilder private var badge: some View {
        if count > 0 {
            Group {
                if isCompact {
                    BentoStatusDot(status: .warn, size: BentoSpace.s8)
                } else {
                    BentoPillChip("\(count)", tone: .peach)
                }
            }
            .padding(BentoSpace.s6)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

/// 侧边栏行的底：选中铺色调底，悬停盖一层蒙层，按下微缩（宽行不做大幅缩放回弹，会显得整条在晃）。
/// 导航行和后台状态行共用。
struct BentoSidebarRowStyle: ButtonStyle {
    /// 选中行的色调。mint / peach / rose 在这个 App 里是"正常 / 提醒 / 出错"的状态色，这里用默认服务的 lavender。
    static let tone = BentoTone.lavender

    var isSelected = false
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isSelected: isSelected, isCompact: isCompact)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let isCompact: Bool
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: BentoRadius.sm, style: .continuous)
            configuration.label
                .labelStyle(BentoSidebarLabelStyle(isCompact: isCompact))
                .padding(.horizontal, BentoSpace.s14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: BentoSpace.s36)
                .background(BentoSidebarRowStyle.tone.fill.opacity(isSelected ? 1 : 0), in: shape)
                .overlay(shape.fill(BentoTone.panel.hoverVeil).opacity(hovering && !isSelected ? 1 : 0))
                .scaleEffect(configuration.isPressed ? BentoMotion.pressedScale : 1)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(BentoMotion.hover, value: hovering)
                .animation(BentoMotion.hover, value: isSelected)
                .animation(BentoMotion.hover, value: configuration.isPressed)
        }
    }
}

/// 行里「图标位 + 文字」的排法；收窄时只留图标位（14 + 20 + 14 正好是窄条的内宽）。
private struct BentoSidebarLabelStyle: LabelStyle {
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: BentoSpace.s14) {
            configuration.icon.frame(width: BentoSpace.s20)
            if !isCompact { configuration.title.lineLimit(1) }
        }
    }
}
