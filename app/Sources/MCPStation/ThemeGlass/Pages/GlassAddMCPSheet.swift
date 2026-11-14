import SwiftUI

/// 添加 MCP：系统设置式分组表单，放在 sheet 里。由工具栏"+"菜单或菜单栏"添加 MCP…"（⌘N）打开。
/// 提交成功才关闭并选中新加的 MCP；失败原因由 store 用 toast 提示，表单保持打开方便改。
struct GlassAddMCPSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MCPDraft()
    @FocusState private var nameFocused: Bool

    var body: some View {
        let submitting = store.isBusy("add-mcp")
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("名字", text: $draft.name, prompt: Text("字母、数字、- 和 _"))
                        .focused($nameFocused)
                    Picker("类型", selection: $draft.kind) {
                        ForEach(MCPKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(draft.kind.targetLabel, text: $draft.target, prompt: Text(draft.kind.targetPrompt))
                        .monospaced()
                    // 每种类型都是同样几栏，切换类型时 sheet 高度不变：HTTP 不用参数，这一栏留着但置灰
                    TextField("参数", text: draft.kind == .http ? .constant("") : $draft.args,
                              prompt: Text(draft.kind == .http ? "HTTP 类型不用参数" : "可选，空格分开"))
                        .monospaced()
                        .disabled(draft.kind == .http)
                } header: {
                    Text("添加 MCP")
                }
                Section {
                    TextField(draft.kind.extraLabel, text: $draft.extra, prompt: Text(draft.kind.extraPrompt), axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .monospaced()
                } footer: {
                    Text("名字里带 KEY、TOKEN、SECRET、PASSWORD、Authorization 的值，详情页里默认打码。")
                }
                Section {
                    Toggle("加入默认服务", isOn: $draft.inDefault)
                } footer: {
                    Text("打开后，连在默认地址 /mcp 上的客户端都能用到它。")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || submitting)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .onAppear { nameFocused = true }
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
            nav.mcpFilter = .all
            nav.selectedMCP = name
            nav.mcpTab = .overview
            dismiss()
        }
    }
}
