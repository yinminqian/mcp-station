import SwiftUI

/// 输入一个名字的小气泡（新建服务、重命名）。提交成功才关闭；失败的原因由 store 用 toast 提示。
struct BentoNamePopover: View {
    let title: String
    let actionTitle: String
    var initial = ""
    /// 返回是否成功。
    let submit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var submitting = false
    @FocusState private var focused: Bool

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            Text(title).bentoText(.title)
            TextField("名字", text: $name)
                .textFieldStyle(.plain)
                .font(BentoTextStyle.mono.font)
                .foregroundStyle(BentoColor.Ink.primary)
                .padding(.horizontal, BentoSpace.s14)
                .frame(height: BentoMetric.controlHeight)
                .background(BentoColor.Bg.surface, in: Capsule())
                .focused($focused)
                .onSubmit(send)
            Text("只能用字母、数字、- 和 _；它会出现在地址 /s/<名字>/mcp 里")
                .bentoText(.label, BentoColor.Ink.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bento(.panel, size: .small))
                Button(actionTitle, action: send)
                    .buttonStyle(.bento(.ink, size: .small))
                    .disabled(trimmed.isEmpty || trimmed == initial || submitting)
            }
        }
        .padding(BentoSpace.s20)
        .frame(width: 320)
        .background(BentoColor.Bg.window)
        .environment(\.colorScheme, .light)
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func send() {
        let value = name.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != initial, !submitting else { return }
        submitting = true
        Task {
            let ok = await submit(value)
            submitting = false
            if ok { dismiss() }
        }
    }
}
