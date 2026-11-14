import SwiftUI

/// 概览页的内存卡片：合计（后台服务 + 所有 MCP），和占用最多的几个 MCP。
/// 和调用卡并排、同一副骨架（小标题 / 大数字 / 明细），所以两张卡逐行对齐；比调用卡矮时自己拉到一样高。
struct BentoMemoryCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    /// 列出占用最多的几个。
    private static let topCount = 6

    var body: some View {
        let top = Array(store.memoryRanking.prefix(Self.topCount))
        let peak = top.first?.memory ?? 0
        BentoCard(radius: BentoRadius.xl, padding: BentoSpace.s16) {
            VStack(alignment: .leading, spacing: BentoSpace.s8) {
                BentoSectionLabel(String(localized: "内存 · 合计"))
                // 一个采样都没有时显示「—」，不是「<1 MB」
                BentoMemoryText(bytes: top.isEmpty ? nil : store.totalMemory)
                    .bentoText(.headline, BentoColor.Ink.black)
                VStack(alignment: .leading, spacing: BentoSpace.s4) {
                    if top.isEmpty {
                        Text(store.mcps.contains { $0.state == .ready } ? "正在采样…" : "没有在跑的本地 MCP").bentoText(.label, BentoColor.Ink.tertiary)
                    }
                    ForEach(top) { mcp in
                        Button {
                            nav.show(mcp: mcp.name)
                        } label: {
                            BentoMemoryRow(mcp: mcp, share: peak > 0 ? Double(mcp.memory ?? 0) / Double(peak) : 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// 一行：名字、相对最大者的比例条、数值。
private struct BentoMemoryRow: View {
    let mcp: MCPServer
    let share: Double

    var body: some View {
        HStack(spacing: BentoSpace.s8) {
            Text(mcp.name)
                .bentoText(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(BentoColor.Bg.panel)
                .frame(width: BentoSpace.s48 + BentoSpace.s24, height: BentoSpace.s6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(BentoCatalog.look(of: mcp).tone.ink)
                        .scaleEffect(x: max(0.04, share), anchor: .leading)
                }
                .accessibilityHidden(true)
            BentoMemoryText(bytes: mcp.memory)
                .bentoText(.label, BentoColor.Ink.secondary)
                .frame(width: BentoSpace.s48 + BentoSpace.s4, alignment: .trailing)
        }
        .frame(height: BentoSpace.s20)
        .contentShape(Rectangle())
        .bentoRowHover(radius: BentoRadius.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看 \(mcp.name)")
    }
}
