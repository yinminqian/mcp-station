import SwiftUI

/// 复制按钮：点完图标变成对勾，一会儿恢复。状态在共享的 `CopyFeedback` 里，这里只管外观。
struct BentoCopyButton: View {
    enum Style {
        /// 只有图标的圆形小按钮。
        case icon
        /// 「复制」文字药丸。
        case labeled
    }

    let text: String
    /// 同一屏有多个复制按钮时用来区分谁被点了。
    let key: String
    var style: Style = .icon
    var tone: BentoTone = .surface
    var label = "复制"

    @Environment(CopyFeedback.self) private var feedback

    var body: some View {
        let copied = feedback.isCopied(key)
        let button = Button {
            feedback.copy(text, key: key)
        } label: {
            Label(copied ? "已复制" : label, bento: copied ? .copied : .copy)
                .contentTransition(.symbolEffect(.replace))
        }
        Group {
            switch style {
            case .icon: button.buttonStyle(BentoIconButtonStyle(tone: tone, size: BentoMetric.controlHeightSmall))
            case .labeled: button.buttonStyle(.bento(tone, size: .small))
            }
        }
        .accessibilityLabel(copied ? "已复制" : label)
        .help(label)
    }
}
