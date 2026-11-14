import Charts
import SwiftUI

/// 概览：顶部四张指标卡片，下面左边是分组表单（需要关注 / 调用方 / 服务），右边是最近调用的原生表格。
struct GlassOverviewPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        VStack(spacing: 0) {
            GlassSummaryStrip()
                .padding(16)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                GlassAttentionForm()
                    .frame(width: 340)
                Divider()
                GlassRecentCalls()
            }
        }
    }
}

/// 顶部四张指标卡片：MCP、每分钟调用、错误、内存。每张是"图标 + 小标题 / 大数字 / 拉满宽度的趋势 / 一行说明"，
/// 四张等宽等高；窗口窄时折成 2×2。（2026-11-14 用户反馈原来一个框里竖线分隔"有点简陋"，要分成块、做得好一点。）
private struct GlassSummaryStrip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let a = mcp, b = calls, c = errors, d = memory
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { a; b; c; d }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { a; b }
                GridRow { c; d }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mcp: some View {
        let active = store.activeMCPs.count, bad = store.attention.count, stopped = store.mcps.count - active
        var detail = bad > 0 ? "\(bad) 个需要关注" : "无需关注"
        if stopped > 0 { detail += " · \(stopped) 个已停止" }
        return GlassMetricCard(symbol: bad > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                               tint: bad > 0 ? .orange : .green, title: "MCP 正常",
                               value: "\(store.healthyCount) / \(active)", detail: detail) {
            HealthBar(healthy: store.healthyCount, attention: bad, total: active)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var calls: some View {
        let s = store.stats
        return GlassMetricCard(symbol: "waveform.path.ecg", tint: .blue, title: "每分钟调用",
                               value: Format.count(s.perMinute),
                               detail: "峰值 \(s.peakPerMinute) · 最近 1 小时 \(Format.count(s.total1h))") {
            Sparkline(values: s.perMinuteSeries, color: .blue)
        }
        .help("趋势：最近 30 分钟每分钟调用数")
    }

    private var errors: some View {
        let s = store.stats, src = s.errorSources
        let detail = src.count > 1 ? "\(src[0]) 等 \(src.count) 个 MCP" : src.first ?? "没有出错的 MCP"
        return GlassMetricCard(symbol: "xmark.octagon.fill", tint: s.errors1h > 0 ? .red : .secondary,
                               title: "错误 · 最近 1 小时", value: Format.count(s.errors1h), detail: detail) {
            Sparkline(values: s.errorSeries, color: .red)
        }
        .help(src.joined(separator: "、"))
    }

    private var memory: some View {
        let top = store.memoryRanking.first
        // 各 MCP 最近若干次采样按次序相加，得到合计的趋势
        let histories = store.mcps.map(\.memoryHistory).filter { !$0.isEmpty }
        let n = histories.map(\.count).max() ?? 0
        let totals = (0..<n).map { i in histories.reduce(0.0) { acc, h in
            let j = i - (n - h.count)
            return acc + (j >= 0 ? Double(h[j]) : 0)
        } }
        return GlassMetricCard(symbol: "memorychip.fill", tint: .purple, title: "内存合计",
                               value: store.memoryRanking.isEmpty ? "—" : Format.bytes(store.totalMemory),
                               detail: top.map { "最高 \($0.name) \(Format.bytes($0.memory))" } ?? "没有在跑的本地 MCP") {
            if totals.count > 1 { Sparkline(values: totals, color: .purple, baselineAtZero: false) }
        }
    }
}

/// 一张指标卡片：系统的分组底色和圆角，各张等高。
private struct GlassMetricCard<Trend: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let detail: String
    @ViewBuilder var trend: Trend

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.identity)
            trend
                .frame(height: 26)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(14)
        .frame(minWidth: 0, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct HealthBar: View {
    var healthy: Int, attention: Int, total: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, t = max(1, CGFloat(total))
            HStack(spacing: 2) {
                Capsule().fill(.green).frame(width: max(0, w * CGFloat(healthy) / t - 2))
                if attention > 0 { Capsule().fill(.orange).frame(width: max(4, w * CGFloat(attention) / t - 2)) }
                Capsule().fill(.quaternary)
            }
        }
        .frame(height: 6)
        .animation(.smooth, value: healthy)
    }
}

/// 趋势小图（调用量、错误数、内存）。
struct Sparkline: View {
    var values: [Double]
    var color: Color
    /// 计数类从 0 起；内存这种只看波动的从最小值附近起，免得画成一条平线。
    var baselineAtZero = true

    init(values: [Int], color: Color) {
        self.values = values.map(Double.init)
        self.color = color
    }

    init(values: [Double], color: Color, baselineAtZero: Bool) {
        self.values = values
        self.color = color
        self.baselineAtZero = baselineAtZero
    }

    var body: some View {
        let hi = max(values.max() ?? 1, baselineAtZero ? 1 : 0)
        let lo = baselineAtZero ? 0 : (values.min() ?? 0) * 0.97
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("序号", i), yStart: .value("下限", lo), yEnd: .value("值", v))
                .foregroundStyle(color.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("序号", i), y: .value("值", v))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: lo...max(hi, lo + 1))
        .accessibilityLabel("趋势")
    }
}

private struct GlassAttentionForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        Form {
            Section("需要关注") {
                if store.attention.isEmpty {
                    Label("所有 MCP 都正常", systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                ForEach(store.attention) { m in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name)
                            Group {
                                if m.state == .starting {
                                    // 正在重试：出结果前留在这里，成功才移走（见 AppStore.retrying）
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.mini)
                                        Text("正在重试…")
                                    }
                                } else {
                                    GlassStateText(state: m.state)
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("查看") { nav.show(mcp: m.name) }
                            .controlSize(.small)
                    }
                }
            }
            Section {
                let clients = Self.clients(store.calls)
                if clients.isEmpty {
                    Text("最近 1 小时没有客户端调用").foregroundStyle(.secondary)
                }
                ForEach(clients, id: \.name) { c in
                    Button {
                        nav.callFilter = .all
                        nav.callSearch = c.name
                        nav.route = .calls
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                if c.errors > 0 {
                                    Text("\(c.errors) 次失败").foregroundStyle(.red)
                                }
                                Text("\(c.count) 次").monospacedDigit()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Label(c.name, systemImage: c.name == "MCP Mac" ? "hammer" : "person.crop.circle")
                                    .foregroundStyle(.primary)
                                Text("最近一次 \(Format.time(c.last))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("在调用记录里只看 \(c.name) 的调用")
                }
            } header: {
                Text("调用方 · 最近 1 小时")
            }
            Section("服务") {
                ForEach(store.services) { s in
                    Button {
                        nav.show(service: s.name)
                    } label: {
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(s.members.count) 个 · \(s.toolCount) 工具").monospacedDigit()
                                Text(s.sessions > 0 ? "\(s.sessions) 个连接" : "没有连接")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).foregroundStyle(.primary)
                                Text(s.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 最近 1 小时按客户端（initialize 报的 clientInfo）归类：次数、失败数、最近一次。
    private static func clients(_ calls: [CallRecord]) -> [(name: String, count: Int, errors: Int, last: Date)] {
        let since = Date.now.addingTimeInterval(-3600)
        let recent = calls.filter { $0.time >= since }
        return Dictionary(grouping: recent, by: \.client).map { name, cs in
            (name, cs.count, cs.filter(\.isError).count, cs.map(\.time).max() ?? .distantPast)
        }
        .sorted { $0.count > $1.count }
    }
}

private struct GlassRecentCalls: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let calls = Array(store.calls.suffix(60).reversed())
        VStack(alignment: .leading, spacing: 0) {
            Text("最近调用")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            Table(calls) {
                TableColumn("时间") { c in Text(Format.time(c.time)).monospacedDigit() }.width(64)
                TableColumn("MCP") { c in Text(c.mcp) }.width(min: 90, ideal: 120)
                TableColumn("工具") { c in Text(c.tool).font(.system(size: 11, design: .monospaced)).help(c.tool) }
                TableColumn("调用方") { c in Text(c.client).foregroundStyle(.secondary) }.width(min: 80, ideal: 130)
                TableColumn("服务") { c in Text(c.service).foregroundStyle(.secondary) }.width(min: 56, ideal: 70)
                TableColumn("耗时") { c in Text(Format.duration(c.duration)).monospacedDigit() }.width(56)
                TableColumn("") { c in CallOutcomeIcon(call: c) }.width(18)
            }
            .alternatingRowBackgrounds()
        }
    }
}

struct CallOutcomeIcon: View {
    var call: CallRecord
    var body: some View {
        Image(systemName: call.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(call.isError ? .red : .green)
            .help(call.isError ? { if case .error(let e) = call.outcome { e } else { "" } }() : "成功")
    }
}
