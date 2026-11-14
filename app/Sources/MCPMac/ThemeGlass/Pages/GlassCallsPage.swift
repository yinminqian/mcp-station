import SwiftUI

/// 调用记录：版式照搬"活动监视器"——工具栏分段筛选、整宽表格、底部汇总条。
struct GlassCallsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        let rows = filtered
        VStack(spacing: 0) {
            Table(rows) {
                TableColumn("时间") { c in Text(Format.time(c.time)).monospacedDigit() }.width(70)
                TableColumn("MCP") { c in Text(c.mcp) }.width(min: 100, ideal: 130)
                TableColumn("工具") { c in Text(c.tool).font(.system(size: 11, design: .monospaced)) }
                    .width(min: 140, ideal: 200)
                TableColumn("服务") { c in Text(c.service) }.width(60)
                TableColumn("客户端") { c in Text(c.client).foregroundStyle(.secondary) }.width(min: 90, ideal: 130)
                TableColumn("耗时") { c in
                    Text(Format.duration(c.duration)).monospacedDigit()
                        .foregroundStyle(Navigator.CallFilter.isSlow(c) ? Color.orange : .primary)
                }
                .width(60)
                TableColumn("结果") { c in
                    HStack(spacing: 4) {
                        CallOutcomeIcon(call: c)
                        if case .error(let e) = c.outcome { Text(e).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                .width(min: 40, ideal: 160)
            }
            .alternatingRowBackgrounds()
            .overlay {
                if rows.isEmpty { ContentUnavailableView("没有符合条件的调用", systemImage: "line.3.horizontal.decrease") }
            }

            Divider()
            GlassCallSummary()
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.background)
        }
    }

    private var filtered: [CallRecord] {
        let q = nav.callSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return store.calls.reversed().filter(nav.callFilter.matches)
        .filter { q.isEmpty || $0.mcp.lowercased().contains(q) || $0.tool.lowercased().contains(q) || $0.client.lowercased().contains(q) }
    }
}

/// 底部汇总条：带边框的小框，右对齐的"标签：数值"。
private struct GlassCallSummary: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let s = store.stats
        HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每分钟调用").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Sparkline(values: s.perMinuteSeries, color: .accentColor).frame(width: 150, height: 34)
                }
                .padding(10)
                Divider()
                pairs([("调用数（1 小时）", Format.count(s.total1h)), ("错误", "\(s.errors1h)")])
                Divider()
                pairs([("平均耗时", Format.duration(s.avgDuration)), ("P95", Format.duration(s.p95Duration))])
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .fixedSize()
            Spacer()
        }
    }

    private func pairs(_ items: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            ForEach(items, id: \.0) { k, v in
                GridRow {
                    Text(k + "：")
                    Text(v).monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .padding(10)
    }
}
