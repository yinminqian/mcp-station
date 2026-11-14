import SwiftUI

/// 服务的一行卡片：图标、名字、地址、「几个 MCP · 多少工具」，右边可以再放一个操作。
/// 概览右栏和菜单栏面板共用。
struct BentoServiceRow<Trailing: View>: View {
    let service: ServiceSummary
    let tone: BentoTone
    /// 紧凑：图标和内边距小一号（概览右栏要在一屏里放下所有内容）。
    var isCompact = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        BentoCard(tone: tone, radius: BentoRadius.lg, padding: isCompact ? BentoSpace.s8 : BentoSpace.s12) {
            HStack(spacing: BentoSpace.s12) {
                BentoIconCircle(BentoCatalog.icon(of: service), on: tone,
                                size: isCompact ? BentoSpace.s32 : BentoMetric.iconCircle)
                VStack(alignment: .leading, spacing: 0) {
                    Text(service.name).bentoText(.bodyStrong)
                    Text(service.path).bentoText(.mono, tone.ink)
                }
                .lineLimit(1)
                Spacer(minLength: BentoSpace.s4)
                BentoPillChip(String(localized: "\(service.members.count) 个 · \(service.toolCount) 工具"))
                trailing
            }
        }
    }
}

extension BentoServiceRow where Trailing == EmptyView {
    init(service: ServiceSummary, tone: BentoTone, isCompact: Bool = false) {
        self.init(service: service, tone: tone, isCompact: isCompact) { EmptyView() }
    }
}
