import SwiftUI

/// 日志块里的一行。MCP 的 stderr 和 core.log 的尾部都先转成它。
struct BentoLogLine: Identifiable, Hashable {
    let id: Int
    var time: String
    var level: LogLine.Level
    var text: String

    init(_ line: LogLine) {
        id = line.id
        time = Format.time(line.time)
        level = line.level
        text = line.text
    }

    /// 解析 core.log 的一行原文：「09:41:02 error 绑定…」。行可能重复，所以 id 用行号。
    init(raw: String, index: Int) {
        id = index
        var rest = raw[...]
        func nextWord() -> Substring? {
            guard let space = rest.firstIndex(of: " ") else { return nil }
            defer { rest = rest[rest.index(after: space)...] }
            return rest[..<space]
        }
        time = nextWord().map(String.init) ?? ""
        if rest.hasPrefix("error ") {
            _ = nextWord(); level = .error
        } else if rest.hasPrefix("warn ") {
            _ = nextWord(); level = .warn
        } else {
            level = .info
        }
        text = String(rest)
    }
}

/// 深色日志块：标题 + 等宽日志行，错误和警告的级别词上色。
struct BentoLogBlock: View {
    let title: String
    let lines: [BentoLogLine]
    /// 占满可用高度并在块内滚动（日志页）；否则按内容高度（概况里的最后几行）。
    var fillsHeight = false

    var body: some View {
        BentoCard(tone: .inverse, radius: BentoRadius.lg) {
            VStack(alignment: .leading, spacing: BentoSpace.s10) {
                Label(title, bento: .terminal)
                    .labelStyle(BentoLabelStyle())
                    .bentoText(.label, BentoColor.Ink.inverseMuted)
                if lines.isEmpty {
                    Text("还没有日志")
                        .bentoText(.mono, BentoColor.Ink.inverseMuted)
                } else if fillsHeight {
                    ScrollView {
                        rows.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // 一打开停在最新的一行；内容不满一屏时仍从顶上排起
                    .defaultScrollAnchor(.bottom)
                    .defaultScrollAnchor(.top, for: .alignment)
                } else {
                    rows
                }
            }
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { BentoLogRow(line: $0) }
        }
    }
}

private struct BentoLogRow: View {
    let line: BentoLogLine

    var body: some View {
        let time = Text(line.time).foregroundStyle(BentoColor.Ink.inverseMuted)
        Group {
            switch line.level {
            case .info: Text("\(time) \(line.text)")
            case .warn: Text("\(time) \(Text("warn").foregroundStyle(BentoColor.Log.warn)) \(line.text)")
            case .error: Text("\(time) \(Text("error").foregroundStyle(BentoColor.Log.error)) \(line.text)")
            }
        }
        .bentoText(.mono, BentoColor.Ink.inverse)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
