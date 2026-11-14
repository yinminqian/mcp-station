import SwiftUI

/// 「概况」：状态说明、定义、最近几行日志。
struct BentoMCPOverviewTab: View {
    let mcp: MCPServer
    let usedBy: [String]
    /// 除它以外还有几个 MCP 正常（用来说明「别的不受影响」）。
    let othersHealthy: Int
    let port: Int?

    /// 概况里带几行日志；完整的在「日志」页签。
    private static let logTail = 6

    var body: some View {
        ScrollView {
            VStack(spacing: BentoSpace.s12) {
                BentoMCPStateCard(mcp: mcp, othersHealthy: othersHealthy)
                definition
                let tail = mcp.stderr.suffix(Self.logTail)
                BentoLogBlock(title: tail.isEmpty ? "最近日志（stderr）" : "最近日志（stderr 最后 \(tail.count) 行）",
                              lines: tail.map(BentoLogLine.init))
            }
        }
        .scrollIndicators(.never)
    }

    private var definition: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: 0) {
                BentoSectionLabel("定义").padding(.bottom, BentoSpace.s4)
                BentoKeyValueRow("类型", mcp.kind.label)
                ForEach(mcp.definition) { field in
                    if field.secret {
                        BentoSecretRow(key: field.key, value: field.value)
                    } else {
                        BentoKeyValueRow(field.key, field.value, monospaced: field.monospaced)
                    }
                }
                BentoKeyValueRow("用到它的服务", usedBy.isEmpty ? "没有" : usedBy.joined(separator: "、"))
                if let port {
                    let url = Format.mcpURL(mcp.name, port: port)
                    BentoKeyValueRow(key: "单独地址") {
                        BentoValueText(url, monospaced: true)
                    } trailing: {
                        BentoCopyButton(text: url, key: "mcp-url:\(mcp.name)", tone: .panel, label: "复制单独地址")
                    }
                }
            }
        }
    }
}

/// 按状态换内容的那张卡片：等待重试（带倒计时）、配置错误、启动中、已停止、正常运行。
private struct BentoMCPStateCard: View {
    let mcp: MCPServer
    let othersHealthy: Int

    var body: some View {
        switch mcp.state {
        case let .backoff(reason, retryAt, attempts):
            BentoAlertCard(tone: .peach, bounce: attempts) {
                BentoCountdown(target: retryAt) { seconds in
                    seconds > 0 ? "连不上上游，\(seconds) 秒后自动重试（已重试 \(attempts) 次）"
                                : "正在重试…（已重试 \(attempts) 次）"
                }
            } message: {
                Text(reason)
                if othersHealthy > 0 {
                    Text("其他 \(othersHealthy) 个 MCP 不受影响").bentoText(.label, BentoTone.peach.ink)
                }
            }
        case .configError(let message):
            BentoAlertCard(tone: .rose) {
                Text("配置有问题，没有启动")
            } message: {
                Text(message)
            }
        case .starting:
            BentoAlertCard(tone: .sky, icon: .clock) {
                Text("正在启动…")
            } message: {
                Text("握手完成后就能用了。")
            }
        case .stopped:
            BentoAlertCard(tone: .sunken, icon: .info) {
                Text("没有在运行")
            } message: {
                Text("没有任何服务用到它，所以没启动。打开左边的开关（加入默认服务），或者把它加进某个服务，它就会启动。")
            }
        case .ready:
            BentoMCPRuntimeCard(mcp: mcp)
        }
    }
}

/// 正常运行时的几项运行数据；内存带最近一段的趋势线。
private struct BentoMCPRuntimeCard: View {
    let mcp: MCPServer

    var body: some View {
        let tone = BentoTone.mint
        BentoCard(tone: tone, radius: BentoRadius.xl) {
            HStack(alignment: .top, spacing: BentoSpace.s12) {
                BentoIconCircle(.check, on: tone)
                fact("进程") { Text(verbatim: mcp.pid.map { "pid \($0)" } ?? "无本地进程") }
                fact("已运行") {
                    if let startedAt = mcp.startedAt { BentoUptime(since: startedAt, prefix: "") } else { Text("—") }
                }
                fact("重启次数") { Text("\(mcp.restarts) 次") }
                fact("内存") {
                    HStack(spacing: BentoSpace.s8) {
                        BentoMemoryText(bytes: mcp.memory).fixedSize()
                        if mcp.memoryHistory.count > 1 {
                            BentoSparkline(values: mcp.memoryHistory, color: tone.ink)
                                .frame(minWidth: BentoSpace.s24, maxWidth: BentoSpace.s48 + BentoSpace.s32, maxHeight: BentoSpace.s18)
                        }
                    }
                }
            }
        }
    }

    private func fact(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BentoSectionLabel(title, color: BentoTone.mint.ink)
            value().bentoText(.bodyStrong).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 「工具」：名字 + 一句话说明。右键「试调用…」或双击一行，可以直接调一次这个工具。
struct BentoMCPToolsTab: View {
    let mcp: String
    let tools: [ToolInfo]
    @State private var trying: ToolInfo?

    var body: some View {
        if tools.isEmpty {
            BentoCard { BentoEmptyState(icon: .tools, text: "还没拿到工具列表") }
        } else {
            BentoCard(padding: 0) {
                List(tools) { tool in
                    BentoToolRow(name: tool.name, summary: tool.summary) { trying = tool }
                }
                .bentoCardList()
                .sheet(item: $trying) { BentoToolCallSheet(mcp: mcp, tool: $0) }
            }
        }
    }
}

/// 工具列表的一行（放在 List 里）。MCP 详情和服务的「聚合后的工具」共用。
struct BentoToolRow: View {
    let name: String
    let summary: String
    /// 名字一列的宽度；聚合后的名字带 MCP 前缀，要宽一些。
    var nameWidth: CGFloat = 260
    /// 试调用这个工具；不传就没有这个入口（比如服务的聚合工具列表）。
    var onTry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BentoSpace.s16) {
            // 不开 textSelection、不加悬停底色：系统列表没有这两样，滚动时逐行触发会卡、会闪。复制走右键菜单。
            Text(name)
                .bentoText(.mono)
                .frame(width: nameWidth, alignment: .leading)
            Text(summary)
                .bentoText(.body, BentoColor.Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
        .padding(.horizontal, BentoSpace.s12)
        .frame(height: BentoSpace.s36)
        .contentShape(Rectangle())
        .help("\(name)\n\(summary)")
        .onTapGesture(count: 2) { onTry?() }
        .contextMenu {
            if let onTry { Button("试调用…") { onTry() } }
            Button("拷贝工具名") { Clipboard.copy(name) }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
}

/// 「Resources」：除工具外它还提供什么。目前只有数量。
struct BentoMCPCapabilitiesTab: View {
    let mcp: MCPServer

    var body: some View {
        VStack(spacing: BentoSpace.s12) {
            BentoCard {
                VStack(alignment: .leading, spacing: 0) {
                    BentoSectionLabel("除了工具，它还提供").padding(.bottom, BentoSpace.s4)
                    BentoKeyValueRow("Resources", "\(mcp.resourceCount) 个")
                    BentoKeyValueRow("Prompts", "\(mcp.promptCount) 个")
                    BentoKeyValueRow("使用说明", mcp.instructionsLength > 0
                        ? "\(Format.count(mcp.instructionsLength)) 字" : "没有")
                }
            }
            BentoNote(tag: "说明", text: "聚合进服务时：resources 的 URI 保持原样，prompts 的名字加上「\(mcp.name)__」前缀，使用说明前面加「## \(mcp.name)」小标题后拼在一起。",
                      tone: .surface)
        }
    }
}
