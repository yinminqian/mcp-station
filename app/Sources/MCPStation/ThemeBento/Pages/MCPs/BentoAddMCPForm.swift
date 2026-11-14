import SwiftUI

/// 添加 MCP 的弹窗表单（sheet）：MCP 页列表上方的"添加 MCP"按钮，或菜单栏"添加 MCP…"⌘N。
/// 提交成功才关闭并选中新加的 MCP；失败原因由 store 用 toast 提示，表单保持打开方便改。
struct BentoAddMCPForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MCPDraft()
    @FocusState private var nameFocused: Bool

    var body: some View {
        let submitting = store.isBusy("add-mcp")
        VStack(alignment: .leading, spacing: BentoSpace.s14) {
            Text("添加 MCP").bentoText(.title)
            BentoSegmentedPills(MCPKind.allCases, selection: $draft.kind, title: \.label)

            field(String(localized: "名字")) {
                TextField("", text: $draft.name, prompt: Text("字母、数字、- 和 _"))
                    .bentoField()
                    .focused($nameFocused)
            }
            field(draft.kind.targetLabel) {
                TextField("", text: $draft.target, prompt: Text(draft.kind.targetPrompt))
                    .bentoField()
            }
            // 每种类型都是同样几栏，切换类型时弹窗高度不变：HTTP 不用参数，这一栏留着但置灰
            field(String(localized: "参数")) {
                TextField("", text: draft.kind == .http ? .constant("") : $draft.args,
                          prompt: Text(draft.kind == .http ? "HTTP 类型不用参数" : "可选，空格分开"))
                    .bentoField()
                    .disabled(draft.kind == .http)
                    .opacity(draft.kind == .http ? BentoOpacity.dimmed : 1)
            }
            field(draft.kind.extraLabel) {
                TextField("", text: $draft.extra, prompt: Text(draft.kind.extraPrompt), axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                    .bentoField(multiline: true)
            }

            HStack {
                VStack(alignment: .leading, spacing: BentoSpace.s2) {
                    Text("加入默认服务").bentoText(.bodyStrong, BentoColor.Ink.primary)
                    Text("连在默认地址 /mcp 上的客户端都能用到它").bentoText(.label, BentoColor.Ink.secondary)
                }
                Spacer()
                Toggle("加入默认服务", isOn: $draft.inDefault).toggleStyle(.bento)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bento(.panel))
                    .keyboardShortcut(.cancelAction)
                Button("添加", action: submit)
                    .buttonStyle(.bento(.ink))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || submitting)
            }
        }
        .padding(BentoSpace.s24)
        .frame(width: 460)
        .background(BentoColor.Bg.window)
        .environment(\.colorScheme, .light)
        .onAppear { nameFocused = true }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BentoSpace.s6) {
            Text(title).bentoText(.label, BentoColor.Ink.secondary)
            content()
        }
    }

    private var canSubmit: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        Task {
            guard await store.addMCP(draft) else { return }
            nav.mcpSearch = ""
            nav.selectedMCP = name
            dismiss()
        }
    }
}

extension View {
    /// 输入框外观：单行是胶囊，多行是圆角矩形，等宽字。添加 MCP、试调用的表单共用。
    func bentoField(multiline: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(BentoTextStyle.mono.font)
            .foregroundStyle(BentoColor.Ink.primary)
            .padding(.horizontal, BentoSpace.s14)
            .padding(.vertical, multiline ? BentoSpace.s10 : 0)
            .frame(minHeight: BentoMetric.controlHeight)
            .background(BentoColor.Bg.surface,
                        in: RoundedRectangle(cornerRadius: multiline ? BentoRadius.md : BentoMetric.controlHeight / 2,
                                             style: .continuous))
    }
}
