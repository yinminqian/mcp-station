import Charts
import SwiftUI

/// 概览页的调用卡片：最近几个小时的调用数，按服务堆叠。和内存卡并排、同一副骨架（小标题 / 大数字 / 明细）。
///
/// 概览页只有这张卡片读 `store.stats`（大约每秒变一次），重绘只发生在这里。
struct BentoCallChartCard: View {
    /// 堆叠和图例的顺序（默认服务在最下面）。固定顺序，柱子里的色块才不会每次刷新都换位置。
    let serviceOrder: [String]
    let tones: BentoServiceTones

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @State private var hovered: String?

    var body: some View {
        let columns = BentoChartColumn.make(store.stats.hourly, order: serviceOrder)
        let focus = columns.first { $0.label == hovered } ?? columns.last
        let isHovering = hovered != nil && focus != nil
        let total = isHovering ? focus?.total ?? 0 : columns.reduce(0) { $0 + $1.total }
        let errors = isHovering ? focus?.errors ?? 0 : columns.reduce(0) { $0 + $1.errors }

        BentoCard(radius: BentoRadius.xl, padding: BentoSpace.s16) {
            VStack(alignment: .leading, spacing: BentoSpace.s8) {
                HStack(spacing: BentoSpace.s8) {
                    BentoSectionLabel(isHovering ? String(localized: "调用 · \(focus?.label ?? "") 点这一小时") : String(localized: "调用 · 近 \(columns.count) 小时"))
                        .lineLimit(1)
                        .layoutPriority(1)
                    // 卡片窄到放不下图例时整个不显示（右栏「我的服务」的颜色和它一致）
                    ViewThatFits(in: .horizontal) {
                        legend(columns)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack(alignment: .center, spacing: BentoSpace.s10) {
                    Text("\(Format.count(total)) 次")
                        .bentoText(.headline, BentoColor.Ink.black)
                        .monospacedDigit()
                    Button {
                        nav.callFilter = .errors
                        nav.route = .calls
                    } label: {
                        BentoPillChip(errors == 0 ? String(localized: "没有失败") : String(localized: "\(Format.count(errors)) 次失败"),
                                      tone: errors == 0 ? .panel : .rose)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(errors > 0)
                    .help(errors > 0 ? "查看失败的调用" : "")
                }

                // 至少 chartHeight；旁边的内存卡更高时，多出来的高度给柱子
                BentoCallChart(columns: columns, tones: tones, focus: focus?.label, hovered: $hovered)
                    .frame(minHeight: BentoMetric.chartHeight, idealHeight: BentoMetric.chartHeight, maxHeight: .infinity)
            }
        }
    }

    private func legend(_ columns: [BentoChartColumn]) -> some View {
        let present = Set(columns.flatMap { $0.segments.map(\.service) })
        // 服务以外的来源（比如「试调用」）排在服务后面，也要有图例，不然那块颜色没人认识
        let names = serviceOrder.filter(present.contains) + present.subtracting(serviceOrder).sorted()
        return HStack(spacing: BentoSpace.s12) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: BentoSpace.s6) {
                    Circle().fill(tones[name].fill)
                        .frame(width: BentoSpace.s10, height: BentoSpace.s10)
                    Text(name).bentoText(.label, BentoColor.Ink.secondary)
                }
            }
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}


/// 一根柱子：一个小时，里面按服务分段。
struct BentoChartColumn: Identifiable, Hashable {
    struct Segment: Identifiable, Hashable {
        var id: String { service }
        let service: String
        let from: Int
        let to: Int
    }

    var id: String { label }
    /// 两位数的小时，「09」。
    let label: String
    let segments: [Segment]
    let total: Int
    let errors: Int

    /// 把 store 的小时统计排成柱子。`order` 以外的服务（比如已经删掉的）按名字排在最上面。
    static func make(_ hourly: [HourBucket], order: [String]) -> [BentoChartColumn] {
        hourly.map { bucket in
            let extra = bucket.byService.keys.filter { !order.contains($0) }.sorted()
            var running = 0
            let segments = (order + extra).compactMap { service -> Segment? in
                guard let count = bucket.byService[service], count > 0 else { return nil }
                defer { running += count }
                return Segment(service: service, from: running, to: running + count)
            }
            return BentoChartColumn(label: String(format: "%02d", bucket.hour), segments: segments,
                                    total: running, errors: bucket.errors)
        }
    }
}

/// 堆叠柱状图。当前（或鼠标指着的）那一小时背后铺一圈浅底，横轴上它的小时变成黑色药丸。
///
/// 横轴不用 Charts 自带的：小时、药丸、浅底都在同一层里按 `ChartProxy` 量出来的位置画，中心线才是同一条。
/// 2026-11-14 用户反馈浅底和药丸没对齐，方案出自 Fable 评审。
private struct BentoCallChart: View {
    let columns: [BentoChartColumn]
    let tones: BentoServiceTones
    let focus: String?
    @Binding var hovered: String?

    /// 柱宽占一格的比例。
    private static let barRatio = 0.74
    /// 分段之间的缝。
    private static let gap = BentoSpace.s2
    /// 空小时那截矮桩的高度（点）。
    private static let stub = BentoSpace.s4
    /// 小时药丸的高度。
    private static let pill = BentoSpace.s20
    /// 药丸离柱子底的距离：浅底往下伸出 4pt，再留 4pt。
    private static let pillTop = BentoSpace.s8

    var body: some View {
        // 横轴自己画、高度固定，所以绘图区高度 = 总高 - 横轴高，缝和矮桩才能按真实点数换算
        GeometryReader { geometry in
            chart(plotHeight: max(1, geometry.size.height - Self.pillTop - Self.pill))
        }
    }

    private func chart(plotHeight: CGFloat) -> some View {
        let peak = max(1, columns.map(\.total).max() ?? 1)
        let unitsPerPoint = Double(peak) / Double(plotHeight)
        // 分段之间留缝：把缝的点数换算成数据单位，从每段顶上减掉。
        let gapUnits = Double(Self.gap) * unitsPerPoint
        let stubUnits = Double(Self.stub) * unitsPerPoint

        return Chart(columns) { column in
            // 没有调用、或者少到画不出来的小时，都画一截矮桩：七个小时的位置一直都在，看得出是条时间轴
            if Self.top(of: column, gapUnits: gapUnits) < stubUnits {
                BarMark(x: .value("小时", column.label),
                        yStart: .value("起", 0.0), yEnd: .value("止", stubUnits),
                        width: .ratio(Self.barRatio))
                    .clipShape(RoundedRectangle(cornerRadius: BentoRadius.xs, style: .continuous))
                    .foregroundStyle(column.segments.first.map { tones[$0.service].fill }
                        ?? (column.label == focus ? BentoColor.Ink.tertiary : BentoColor.Bg.sunken))
            } else {
                ForEach(column.segments) { segment in
                    BarMark(x: .value("小时", column.label),
                            yStart: .value("起", Double(segment.from)),
                            yEnd: .value("止", max(Double(segment.from), Double(segment.to) - gapUnits)),
                            width: .ratio(Self.barRatio))
                        .clipShape(RoundedRectangle(cornerRadius: BentoRadius.xs + 1, style: .continuous))
                        .foregroundStyle(tones[segment.service].fill)
                }
            }
        }
        // 横轴固定七个小时：只有一个小时有数据时，柱子也只占一格宽，不会撑满整张图
        .chartXScale(domain: columns.map(\.label))
        .chartYScale(domain: 0...Double(peak))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    // 柱子底的真实位置，量出来的，不假设它就是 plot.maxY
                    let baseline = plot.minY + (proxy.position(forY: 0.0) ?? plot.height)
                    focusBand(proxy: proxy, plot: plot, baseline: baseline, gapUnits: gapUnits, stubUnits: stubUnits)
                    hourLabels(proxy: proxy, plot: plot, baseline: baseline)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: plot.width, height: plot.height)
                        .offset(x: plot.minX, y: plot.minY)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): hovered = proxy.value(atX: point.x, as: String.self)
                            case .ended: hovered = nil
                            }
                        }
                }
            }
        }
        // 横轴那一行画在图的下面，这里给它留位置
        .padding(.bottom, Self.pillTop + Self.pill)
        .animation(BentoMotion.snappy, value: focus)
        .accessibilityLabel("最近 \(columns.count) 小时的调用数")
    }

    /// 这一小时实际画到多高（数据单位），一段都画不出来时是 0。柱子和浅底都用它，才对得齐。
    private static func top(of column: BentoChartColumn, gapUnits: Double) -> Double {
        column.segments.last { Double($0.to) - gapUnits > Double($0.from) }.map { Double($0.to) - gapUnits } ?? 0
    }

    /// 选中那一小时：柱子背后一圈浅底，四边各大出 pad，跟着柱子的实际高度（空的小时就包住那截矮桩）。
    @ViewBuilder
    private func focusBand(proxy: ChartProxy, plot: CGRect, baseline: CGFloat, gapUnits: Double, stubUnits: Double) -> some View {
        if let column = columns.first(where: { $0.label == focus }),
           let x = proxy.position(forX: column.label),
           let y = proxy.position(forY: max(Self.top(of: column, gapUnits: gapUnits), stubUnits)) {
            let pad = Self.gap * 2
            // 一格的宽度直接量相邻两格的中心距，和 BarMark 的 .ratio 用的是同一个基准
            let centers = columns.compactMap { proxy.position(forX: $0.label) }
            let step = centers.count > 1 ? centers[1] - centers[0] : plot.width
            let top = plot.minY + y
            RoundedRectangle(cornerRadius: BentoRadius.sm, style: .continuous)
                .fill(BentoColor.Bg.panel)
                .frame(width: step * Self.barRatio + pad * 2, height: baseline - top + pad * 2)
                .position(x: plot.minX + x, y: (top + baseline) / 2)
                .allowsHitTesting(false)
        }
    }

    /// 横轴上的小时。和浅底用同一个中心 x、同一条柱底线；选中的那个垫一颗黑色药丸。
    private func hourLabels(proxy: ChartProxy, plot: CGRect, baseline: CGFloat) -> some View {
        ForEach(columns) { column in
            if let x = proxy.position(forX: column.label) {
                let isFocus = column.label == focus
                // 不用 bentoText：它的固定行高会把数字往下挤，在药丸里不居中
                Text(column.label)
                    .font(BentoTextStyle.label.font)
                    .monospacedDigit()
                    .foregroundStyle(isFocus ? BentoColor.Ink.inverse : BentoColor.Ink.tertiary)
                    .padding(.horizontal, BentoSpace.s6)
                    .frame(height: Self.pill)
                    .background(isFocus ? BentoColor.Ink.black : .clear, in: Capsule())
                    .position(x: plot.minX + x, y: baseline + Self.pillTop + Self.pill / 2)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }
}
