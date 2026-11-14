import SwiftUI

/// 分段选择：一条胶囊底上，选中项是黑色块，切换时黑块滑过去。标签页、筛选、客户端类型都用它。
///
/// 黑块只有一个（画在整条的背景里，用 matchedGeometryEffect 跟着选中项的位置和大小走），所以滑动时不会出现
/// "旧块淡出、新块淡入"叠在一起的重影——之前每项各画一个黑块再做过渡，就重影了（2026-11-14 用户反馈）。
struct BentoSegmentedPills<Item: Hashable, ItemLabel: View>: View {
    let items: [Item]
    @Binding var selection: Item
    /// 底条的颜色：放在暖灰面板上用白色，放在白卡片上用暖灰。
    var track: Color = BentoColor.Bg.surface
    @ViewBuilder var label: (Item) -> ItemLabel

    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: BentoSpace.s2) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    label(item)
                        .bentoText(isSelected ? .bodyStrong : .body,
                                   isSelected ? BentoColor.Ink.inverse : BentoColor.Ink.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, BentoSpace.s16)
                        .frame(height: BentoSpace.s36)
                        .contentShape(Capsule())
                        .matchedGeometryEffect(id: item, in: space)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background {
            Capsule()
                .fill(BentoColor.Ink.black)
                .matchedGeometryEffect(id: selection, in: space, isSource: false)
        }
        .padding(BentoSpace.s4)
        .background(track, in: Capsule())
        .animation(reduceMotion ? nil : BentoMotion.snappy, value: selection)
    }
}

extension BentoSegmentedPills where ItemLabel == Text {
    init(_ items: [Item], selection: Binding<Item>, track: Color = BentoColor.Bg.surface,
         title: @escaping (Item) -> String) {
        self.init(items: items, selection: selection, track: track) { Text(title($0)) }
    }
}

/// 带数字的标签（「工具 · 23」）：数字等宽，宽度按至少 3 位数预留。
/// 数字在两位、一位之间变（重新检测时 23 → 0 → 23）时，页签和整条分段不会跟着忽宽忽窄（2026-11-14 用户反馈"抖"）。
struct BentoCountLabel: View {
    let title: String
    var count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        if let count {
            let digits = max(3, String(count).count)
            ZStack {
                Text("\(title) · \(String(repeating: "8", count: digits))").hidden()
                Text("\(title) · \(count)")
            }
            .monospacedDigit()
        } else {
            Text(title)
        }
    }
}

/// 页签内容：所有页签一开始就建好、一直留着，切换只是换哪个显示。
/// 不用 switch：每切一次都重建，「工具」页签里的原生列表现建时第一帧是空的，看起来会闪一下（2026-11-14 用户反馈）。
struct BentoTabStack<Tab: Hashable, Content: View>: View {
    let tabs: [Tab]
    let selection: Tab
    @ViewBuilder var content: (Tab) -> Content

    var body: some View {
        ZStack {
            ForEach(tabs, id: \.self) { tab in
                let shown = tab == selection
                content(tab)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
        .transaction { $0.animation = nil }
    }
}
