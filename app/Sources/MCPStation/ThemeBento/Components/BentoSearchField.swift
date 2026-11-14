import SwiftUI

/// 搜索框：胶囊形，带放大镜和清除按钮。
struct BentoSearchField: View {
    let prompt: String
    @Binding var text: String
    var fill: Color = BentoColor.Bg.surface

    var body: some View {
        HStack(spacing: BentoSpace.s8) {
            BentoIcon.search.image
                .font(.system(size: BentoMetric.iconSize, weight: .medium))
                .foregroundStyle(BentoColor.Ink.tertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(BentoTextStyle.body.font)
                .foregroundStyle(BentoColor.Ink.primary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    BentoIcon.clear.image.foregroundStyle(BentoColor.Ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, BentoSpace.s14)
        .frame(height: BentoMetric.controlHeight)
        .background(fill, in: Capsule())
        .animation(BentoMotion.hover, value: text.isEmpty)
    }
}
