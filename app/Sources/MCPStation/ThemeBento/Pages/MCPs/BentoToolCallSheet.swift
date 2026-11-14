import SwiftUI

/// 试调用一个工具的弹窗：填参数（JSON）→ 调用 → 看返回内容。每次调用都会记进调用记录。
/// 从 MCP 详情的「工具」列表打开（右键「试调用…」或双击一行）。
struct BentoToolCallSheet: View {
    let mcp: String
    let tool: ToolInfo

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var arguments = ""
    @State private var result: ToolCallResult?

    var body: some View {
        let busy = store.isBusy("call:\(mcp)")
        VStack(alignment: .leading, spacing: BentoSpace.s14) {
            VStack(alignment: .leading, spacing: BentoSpace.s2) {
                Text("试调用").bentoText(.label, BentoColor.Ink.secondary)
                Text("\(mcp) · \(tool.name)").bentoText(.title).lineLimit(1)
                if !tool.summary.isEmpty {
                    Text(tool.summary).bentoText(.label, BentoColor.Ink.secondary).lineLimit(2)
                }
            }

            section("参数（JSON）") {
                TextField("", text: $arguments, prompt: Text("{}"), axis: .vertical)
                    .lineLimit(6, reservesSpace: true)
                    .bentoField(multiline: true)
            }
            if let schema = tool.inputSchema {
                section("参数说明") { box(schema, height: 96) }
            }
            section(resultTitle) {
                box(result?.text ?? (busy ? "正在调用…" : "点「调用」后在这里显示返回内容"), height: 160,
                    tint: result?.isError == true ? BentoTone.rose.ink : BentoColor.Ink.primary)
            }

            HStack {
                Text("每次调用都会记进「调用记录」").bentoText(.label, BentoColor.Ink.tertiary)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.bento(.panel))
                    .keyboardShortcut(.cancelAction)
                Button(busy ? "调用中…" : "调用") { run() }
                    .buttonStyle(.bento(.ink))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(busy)
            }
        }
        .padding(BentoSpace.s24)
        .frame(width: 560)
        .background(BentoColor.Bg.window)
        .environment(\.colorScheme, .light)
        .onAppear { arguments = Self.template(tool.inputSchema) }
    }

    private var resultTitle: String {
        guard let result else { return "结果" }
        let ms = Int(result.duration.components.seconds * 1000 + result.duration.components.attoseconds / 1_000_000_000_000_000)
        return "结果 · \(result.isError ? "出错" : "成功") · \(ms) ms"
    }

    private func run() {
        result = nil
        Task { result = await store.callTool(mcp: mcp, tool: tool.name, argumentsJSON: arguments) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: BentoSpace.s6) {
            Text(title).bentoText(.label, BentoColor.Ink.secondary)
            content()
        }
    }

    /// 只读的等宽文字框，可以选中复制，内容多了在框里滚动。
    private func box(_ text: String, height: CGFloat, tint: Color = BentoColor.Ink.secondary) -> some View {
        ScrollView {
            Text(text)
                .bentoText(.mono, tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BentoSpace.s10)
        }
        .frame(height: height)
        .background(BentoColor.Bg.panel, in: RoundedRectangle(cornerRadius: BentoRadius.md, style: .continuous))
    }

    /// 按 inputSchema 生成参数模板：只列必填项，按类型填空值（有 default 就用 default）。
    static func template(_ schema: String?) -> String {
        guard let schema, let obj = try? JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any],
              let props = obj["properties"] as? [String: Any] else { return "{}" }
        var out: [String: Any] = [:]
        for key in obj["required"] as? [String] ?? [] {
            let p = props[key] as? [String: Any] ?? [:]
            if let d = p["default"] { out[key] = d; continue }
            switch p["type"] as? String {
            case "string": out[key] = ""
            case "integer", "number": out[key] = 0
            case "boolean": out[key] = false
            case "array": out[key] = [Any]()
            case "object": out[key] = [String: Any]()
            default: out[key] = NSNull()
            }
        }
        guard !out.isEmpty,
              let d = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }
}
