import SwiftUI

/// 「聚合后的工具」：客户端实际看到的名字是 `<MCP 名>__<工具名>`。
struct BentoServiceToolsTab: View {
    let service: ServiceSummary

    private struct Row: Identifiable {
        let id: String
        let summary: String
    }

    var body: some View {
        let rows = service.members.flatMap { mcp in
            mcp.tools.map { Row(id: "\(mcp.name)__\($0.name)", summary: $0.summary) }
        }
        if rows.isEmpty {
            BentoCard { BentoEmptyState(icon: .tools, text: String(localized: "这个服务里还没有工具")) }
        } else {
            BentoCard(padding: 0) {
                List(rows) { BentoToolRow(name: $0.id, summary: $0.summary, nameWidth: 340) }
                    .bentoCardList()
            }
        }
    }
}

/// 「合并后的说明」：每个 MCP 的使用说明前面加小标题后拼在一起。目前只知道各自的长度。
struct BentoServiceInstructionsTab: View {
    let service: ServiceSummary

    var body: some View {
        ScrollView {
            VStack(spacing: BentoSpace.s12) {
                BentoCard {
                    VStack(alignment: .leading, spacing: 0) {
                        BentoSectionLabel(String(localized: "拼接顺序（共 \(Format.count(service.instructionsLength)) 字）"))
                            .padding(.bottom, BentoSpace.s4)
                        ForEach(service.members) { mcp in
                            HStack(spacing: BentoSpace.s12) {
                                Text("## \(mcp.name)").bentoText(.mono)
                                Spacer()
                                Text(mcp.instructionsLength > 0 ? "\(Format.count(mcp.instructionsLength)) 字" : "没有说明")
                                    .bentoText(.body, mcp.instructionsLength > 0 ? BentoColor.Ink.primary : BentoColor.Ink.tertiary)
                            }
                            .frame(minHeight: BentoSpace.s32)
                        }
                        if service.members.isEmpty {
                            BentoEmptyState(icon: .document, text: String(localized: "这个服务里还没有 MCP"))
                        }
                    }
                }
                BentoNote(tag: String(localized: "说明"), text: String(localized: "客户端连上时在 initialize 里拿到这段合并后的说明。如果客户端对长度有上限，后面的会被截掉。"),
                          tone: .surface)
            }
        }
        .scrollIndicators(.never)
    }
}
