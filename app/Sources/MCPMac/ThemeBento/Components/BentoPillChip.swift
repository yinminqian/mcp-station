import SwiftUI

/// 小药丸：计数、状态、标签（「24 工具」「1 个等待重试」「默认已关」）。
/// 内容可以是任意视图（比如带倒计时的文字）；纯文字用下面的便捷初始化。
struct BentoPillChip<Content: View>: View {
    var tone: BentoTone = .surface
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: BentoSpace.s4) { content }
            .bentoText(.label, tone.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, BentoSpace.s10)
            .frame(height: BentoSpace.s24)
            .background(tone.fill, in: Capsule())
    }
}

extension BentoPillChip where Content == BentoPillLabel {
    init(_ title: String, tone: BentoTone = .surface, icon: BentoIcon? = nil, dot: BentoStatus? = nil) {
        self.init(tone: tone) { BentoPillLabel(title: title, icon: icon, dot: dot) }
    }
}

struct BentoPillLabel: View {
    var title: String
    var icon: BentoIcon?
    var dot: BentoStatus?

    var body: some View {
        if let dot { BentoStatusDot(status: dot) }
        if let icon {
            icon.image.font(.system(size: BentoMetric.iconSizeSmall, weight: .semibold))
        }
        Text(title)
            .contentTransition(.numericText())
            .animation(BentoMotion.snappy, value: title)
    }
}
