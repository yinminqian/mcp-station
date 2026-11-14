import SwiftUI

/// 圆形底上的一个图标。卡片左上角、服务行、提示卡片都用它。
struct BentoIconCircle: View {
    var icon: BentoIcon
    var size: CGFloat = BentoMetric.iconCircle
    var fill: Color = BentoColor.Bg.surface
    var ink: Color = BentoColor.Ink.black

    var body: some View {
        icon.image
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

extension BentoIconCircle {
    /// 粉彩卡片上的图标：半透明白底，图标用卡片的字色。
    init(_ icon: BentoIcon, on tone: BentoTone, size: CGFloat = BentoMetric.iconCircle) {
        self.init(icon: icon, size: size,
                  fill: BentoColor.Bg.surface.opacity(BentoOpacity.chipOnTint), ink: tone.ink)
    }
}
