import SwiftUI

/// 药丸按钮。色调决定主次：`.ink` 是主按钮（黑底白字），`.surface` 是次按钮，`.rose` 是危险操作。
struct BentoButtonStyle: ButtonStyle {
    enum Size { case regular, small }

    var tone: BentoTone = .surface
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        BentoPressable(configuration: configuration, tone: tone, shape: Capsule()) {
            configuration.label
                .labelStyle(BentoLabelStyle())
                .bentoText(size == .regular ? .bodyStrong : .label, tone.ink)
                .lineLimit(1)
                .padding(.horizontal, size == .regular ? BentoSpace.s16 : BentoSpace.s12)
                .frame(height: size == .regular ? BentoMetric.controlHeight : BentoMetric.controlHeightSmall)
        }
    }
}

/// 只有图标的圆形按钮。调用处必须给 `accessibilityLabel`（`BentoIconButton` 会代劳）。
struct BentoIconButtonStyle: ButtonStyle {
    var tone: BentoTone = .surface
    var size: CGFloat = BentoMetric.railButton

    func makeBody(configuration: Configuration) -> some View {
        BentoPressable(configuration: configuration, tone: tone, shape: Circle()) {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(tone.ink)
                .frame(width: size, height: size)
        }
    }
}

extension ButtonStyle where Self == BentoButtonStyle {
    static var bentoPrimary: BentoButtonStyle { BentoButtonStyle(tone: .ink) }
    static var bentoSecondary: BentoButtonStyle { BentoButtonStyle(tone: .surface) }
    static func bento(_ tone: BentoTone, size: BentoButtonStyle.Size = .regular) -> BentoButtonStyle {
        BentoButtonStyle(tone: tone, size: size)
    }
}

/// 图标按钮：图标 + 无障碍标签 + 悬停提示一次配齐。
struct BentoIconButton: View {
    let icon: BentoIcon
    let label: String
    var tone: BentoTone = .surface
    var size: CGFloat = BentoMetric.railButton
    let action: () -> Void

    var body: some View {
        Button(action: action) { icon.image }
            .buttonStyle(BentoIconButtonStyle(tone: tone, size: size))
            .accessibilityLabel(label)
            .help(label)
    }
}

/// 按钮里「图标 + 文字」的排法。
struct BentoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: BentoSpace.s6) {
            configuration.icon.font(.system(size: BentoMetric.iconSizeSmall + 1, weight: .semibold))
            configuration.title
        }
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, bento icon: BentoIcon) {
        self.init { Text(title) } icon: { icon.image }
    }
}

extension BentoTone {
    /// 悬停时盖在上面的一层：浅色底压暗一点，深色底提亮一点。
    var hoverVeil: Color {
        isDark ? BentoColor.Ink.inverse.opacity(BentoOpacity.hoverVeilOnDark)
               : BentoColor.Ink.black.opacity(BentoOpacity.hoverVeil)
    }
}

/// 按钮共用的底色、悬停蒙层、按下缩放、禁用变淡。
private struct BentoPressable<S: Shape, Label: View>: View {
    let configuration: ButtonStyleConfiguration
    let tone: BentoTone
    let shape: S
    @ViewBuilder var label: Label

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .background(tone.fill, in: shape)
            .overlay(shape.fill(tone.hoverVeil).opacity(hovering && isEnabled ? 1 : 0))
            .scaleEffect(configuration.isPressed ? BentoMotion.pressedScale : 1)
            .opacity(isEnabled ? 1 : BentoOpacity.dimmed)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(BentoMotion.hover, value: hovering)
            .animation(BentoMotion.hover, value: configuration.isPressed)
    }
}
