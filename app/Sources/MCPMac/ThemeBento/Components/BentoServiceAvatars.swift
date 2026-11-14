import SwiftUI

/// 用到某个 MCP 的服务，每个服务一个小圆章（名字的首字），叠在一起。
struct BentoServiceAvatars: View {
    let names: [String]
    let tones: BentoServiceTones
    /// 圆章外圈的颜色，用所在卡片的底色，叠放时才分得开。
    var ring: Color = BentoColor.Bg.surface

    var body: some View {
        HStack(spacing: -BentoSpace.s8) {
            ForEach(names, id: \.self) { name in
                Text(name.prefix(1))
                    .bentoText(.label, BentoColor.Ink.inverse)
                    .tracking(0)
                    .frame(width: BentoMetric.avatar, height: BentoMetric.avatar)
                    .background(tones[name].ink, in: Circle())
                    .overlay(Circle().strokeBorder(ring, lineWidth: BentoMetric.selectionStroke))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(names.isEmpty ? "没有服务用到" : "被 \(names.joined(separator: "、")) 使用")
    }
}
