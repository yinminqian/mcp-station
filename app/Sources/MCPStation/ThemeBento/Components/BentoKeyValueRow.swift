import SwiftUI

/// 「名称 — 值」一行，右边可以带一个附加内容（复制按钮、提示）。
struct BentoKeyValueRow<Value: View, Trailing: View>: View {
    let key: String
    @ViewBuilder var value: Value
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: BentoSpace.s12) {
            Text(key)
                .bentoText(.body, BentoColor.Ink.secondary)
                .frame(width: BentoMetric.keyColumnWidth, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: BentoSpace.s32)
    }
}

extension BentoKeyValueRow where Trailing == EmptyView {
    init(key: String, @ViewBuilder value: () -> Value) {
        self.init(key: key, value: value) { EmptyView() }
    }
}

extension BentoKeyValueRow where Value == BentoValueText, Trailing == EmptyView {
    init(_ key: String, _ value: String, monospaced: Bool = false) {
        self.init(key: key) { BentoValueText(value, monospaced: monospaced) }
    }
}

/// 值的文字：普通或等宽，可选中复制。
struct BentoValueText: View {
    let value: String
    var monospaced = false

    init(_ value: String, monospaced: Bool = false) {
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        Text(value)
            .bentoText(monospaced ? .mono : .body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 敏感值一行：默认打码，点一下显示，再点隐藏。
struct BentoSecretRow: View {
    let key: String
    let value: String

    @State private var revealed = false

    private static let mask = String(repeating: "•", count: 12)

    var body: some View {
        Button {
            withAnimation(BentoMotion.hover) { revealed.toggle() }
        } label: {
            BentoKeyValueRow(key: key) {
                Text(revealed ? value : Self.mask)
                    .bentoText(.mono)
                    .contentTransition(.opacity)
            } trailing: {
                Label(revealed ? String(localized: "点击隐藏") : String(localized: "点击显示"), bento: revealed ? .conceal : .reveal)
                    .labelStyle(BentoLabelStyle())
                    .bentoText(.label, BentoColor.Ink.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key)，\(revealed ? String(localized: "已显示") : String(localized: "已隐藏"))")
        .accessibilityHint(revealed ? "点击隐藏" : "点击显示")
    }
}
