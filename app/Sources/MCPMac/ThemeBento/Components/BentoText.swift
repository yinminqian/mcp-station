import SwiftUI

/// 小节标题（「常用 MCP」「我的服务」「定义」）。
struct BentoSectionLabel: View {
    let title: String
    var color: Color = BentoColor.Ink.secondary

    init(_ title: String, color: Color = BentoColor.Ink.secondary) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .bentoText(.label, color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 说明条：黑色小标签 + 一段说明文字。
struct BentoNote: View {
    let tag: String
    let text: String
    var tone: BentoTone = .panel

    var body: some View {
        BentoCard(tone: tone, radius: BentoRadius.lg, padding: BentoSpace.s12) {
            HStack(alignment: .firstTextBaseline, spacing: BentoSpace.s10) {
                BentoPillChip(tag, tone: .ink)
                Text(text)
                    .bentoText(.body, tone.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 列表为空时的占位。
struct BentoEmptyState: View {
    let icon: BentoIcon
    let text: String

    var body: some View {
        VStack(spacing: BentoSpace.s10) {
            BentoIconCircle(icon: icon, fill: BentoColor.Bg.sunken, ink: BentoColor.Ink.secondary)
            Text(text).bentoText(.body, BentoColor.Ink.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BentoSpace.s32)
    }
}

/// 数字块：小标题 + 大数字（调用数、错误、耗时）。
struct BentoStatTile: View {
    let title: String
    let value: String
    var tone: BentoTone = .surface
    var caption: String?

    var body: some View {
        BentoCard(tone: tone, radius: BentoRadius.lg, padding: BentoSpace.s16) {
            VStack(alignment: .leading, spacing: BentoSpace.s4) {
                BentoSectionLabel(title, color: tone.mutedInk)
                Text(value)
                    .bentoText(.headline, tone.ink)
                    .monospacedDigit()
                if let caption {
                    Text(caption)
                        .bentoText(.label, tone.mutedInk)
                        .lineLimit(1)
                        .help(caption)
                }
            }
        }
    }
}
