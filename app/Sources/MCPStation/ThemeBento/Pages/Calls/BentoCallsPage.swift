import SwiftUI

/// 调用记录页：近一小时的汇总、筛选、记录表。
///
/// 页面本身不读调用记录；汇总和表格各自是叶子视图，记录每秒刷新时只有它们重绘。
struct BentoCallsPage: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        let filter = nav.callFilter
        let query = nav.callSearch.trimmingCharacters(in: .whitespaces)

        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            HStack(spacing: BentoSpace.s12) {
                Text("调用记录").bentoText(.headline, BentoColor.Ink.black)
                Spacer()
                BentoSearchField(prompt: "搜索 MCP 或工具", text: $nav.callSearch, fill: BentoColor.Bg.panel)
                    .frame(width: BentoMetric.listColumnWidth)
            }
            .frame(height: BentoMetric.controlHeight)
            .padding(.leading, BentoSpace.s4)

            BentoPanel {
                VStack(alignment: .leading, spacing: BentoSpace.s12) {
                    BentoCallSummary()
                    BentoSegmentedPills(Navigator.CallFilter.allCases, selection: $nav.callFilter, title: \.rawValue)
                    BentoCallTable(matches: { record in
                        filter.matches(record) && (query.isEmpty
                            || record.mcp.localizedCaseInsensitiveContains(query)
                            || record.tool.localizedCaseInsensitiveContains(query))
                    })
                }
                .padding(BentoSpace.s20)
            }
        }
        .bentoPageInsets()
    }
}

/// 近一小时的四个数字。
private struct BentoCallSummary: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let stats = store.stats
        HStack(spacing: BentoSpace.s12) {
            BentoStatTile(title: "调用数", value: Format.count(stats.total1h), tone: .lavender, caption: "近 1 小时")
            BentoStatTile(title: "错误", value: Format.count(stats.errors1h),
                          tone: stats.errors1h > 0 ? .rose : .mint,
                          caption: stats.errorSources.isEmpty ? "没有失败" : stats.errorSources.joined(separator: "、"))
            BentoStatTile(title: "平均耗时", value: Format.duration(stats.avgDuration), tone: .surface, caption: "近 1 小时")
            BentoStatTile(title: "P95", value: Format.duration(stats.p95Duration), tone: .surface,
                          caption: "慢调用门槛 \(Format.duration(Navigator.CallFilter.slowThreshold))")
        }
    }
}
