import SwiftUI

/// 调用记录表：白卡片里的一张表，最新的在最上面。
///
/// 自己从 `store.calls` 取数（大约每秒变一次），所以放它的页面不用读调用记录，也就不会跟着重绘。
/// 表体是原生 List（行复用）；行不带悬停和动画、行高固定——ScrollView + LazyVStack 加每行悬停动画滚起来掉帧
/// （2026-11-14 用户反馈"帧率不高"，方案出自 Fable 评审）。
/// 调用页、MCP 详情的「调用」页签、服务详情的「调用」页签共用，各自传筛选条件。
struct BentoCallTable: View {
    let matches: (CallRecord) -> Bool
    /// 只看某个 MCP 或某个服务时，把那一列省掉。
    var showsMCP = true
    var showsService = true
    /// 最多显示多少条；再早的没必要渲染。
    var limit = 200

    @Environment(AppStore.self) private var store
    /// 地方窄时省掉「客户端」一列，把宽度留给工具名。
    @State private var showsClient = true


    var body: some View {
        let rows = Array(store.calls.reversed().lazy.filter(matches).prefix(limit))
        let layout = BentoCallLayout(showsMCP: showsMCP, showsService: showsService, showsClient: showsClient)
        BentoCard(padding: 0) {
            VStack(spacing: 0) {
                header(layout)
                    .padding([.horizontal, .top], BentoSpace.s8)
                List(rows) { record in
                    BentoCallRow(record: record, layout: layout)
                }
                .bentoCardList(underHeader: true)
                // 空状态盖在上面，不用 if/else 换掉 List：现建的原生列表第一帧是空的，会闪
                .overlay(alignment: .top) {
                    if rows.isEmpty { BentoEmptyState(icon: .calls, text: String(localized: "没有符合条件的调用")) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= BentoMetric.callTableCompactWidth } action: { showsClient = $0 }
    }

    private func header(_ layout: BentoCallLayout) -> some View {
        BentoCallColumns(layout: layout) {
            Text("时间")
        } mcp: {
            Text("MCP")
        } tool: {
            Text("工具")
        } service: {
            Text("服务")
        } client: {
            Text("客户端")
        } duration: {
            Text("耗时")
        } outcome: {
            Text("结果")
        }
        .bentoText(.label, BentoColor.Ink.tertiary)
        .frame(height: BentoSpace.s32)
        .accessibilityHidden(true)
    }
}

/// 显示哪些列。
private struct BentoCallLayout: Equatable {
    var showsMCP: Bool
    var showsService: Bool
    var showsClient: Bool
}

private struct BentoCallRow: View {
    let record: CallRecord
    let layout: BentoCallLayout

    private var errorMessage: String? {
        if case .error(let message) = record.outcome { message } else { nil }
    }

    var body: some View {
        let isSlow = Navigator.CallFilter.isSlow(record)
        BentoCallColumns(layout: layout) {
            Text(Format.time(record.time)).bentoText(.mono, BentoColor.Ink.secondary)
        } mcp: {
            Text(record.mcp).bentoText(.bodyStrong)
        } tool: {
            VStack(alignment: .leading, spacing: 0) {
                Text(record.tool).bentoText(.mono)
                if let errorMessage {
                    Text(errorMessage).bentoText(.label, BentoTone.rose.ink)
                }
            }
        } service: {
            Text(record.service).bentoText(.body, BentoColor.Ink.secondary)
        } client: {
            Text(record.client).bentoText(.body, BentoColor.Ink.secondary)
        } duration: {
            Text(Format.duration(record.duration))
                .bentoText(.mono, isSlow ? BentoTone.peach.ink : BentoColor.Ink.secondary)
        } outcome: {
            HStack(spacing: BentoSpace.s6) {
                // 纯色圆点：BentoStatusDot 带闪动动画，调用行用不上，只会抬高建行成本
                Circle()
                    .fill((record.isError ? BentoStatus.error : isSlow ? .warn : .ok).color)
                    .frame(width: BentoMetric.statusDot, height: BentoMetric.statusDot)
                Text(record.isError ? "失败" : "成功")
                    .bentoText(.body, record.isError ? BentoTone.rose.ink : BentoColor.Ink.secondary)
            }
        }
        .lineLimit(1)
        .frame(height: BentoSpace.s36)
        .help(errorMessage ?? "")
        .accessibilityElement(children: .combine)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
}

/// 表头和每一行共用的列布局，保证对得齐。
private struct BentoCallColumns<Time: View, MCP: View, Tool: View, Service: View, Client: View, Took: View, Outcome: View>: View {
    let layout: BentoCallLayout
    @ViewBuilder var time: Time
    @ViewBuilder var mcp: MCP
    @ViewBuilder var tool: Tool
    @ViewBuilder var service: Service
    @ViewBuilder var client: Client
    @ViewBuilder var duration: Took
    @ViewBuilder var outcome: Outcome

    var body: some View {
        HStack(spacing: BentoSpace.s12) {
            time.frame(width: 68, alignment: .leading)
            if layout.showsMCP { mcp.frame(width: 116, alignment: .leading) }
            tool.frame(maxWidth: .infinity, alignment: .leading)
            if layout.showsService { service.frame(width: 56, alignment: .leading) }
            if layout.showsClient { client.frame(width: 128, alignment: .leading) }
            duration.frame(width: 56, alignment: .trailing)
            outcome.frame(width: 60, alignment: .leading)
        }
        .padding(.horizontal, BentoSpace.s12)
    }
}
