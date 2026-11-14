import SwiftUI

/// 概览页。后台服务在运行时是「主体 + 右栏」；没运行时整页换成出错说明。
struct BentoOverviewPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let core = store.core
        let isDown = BentoStatus(core: core) == .error
        ZStack {
            if let core, case .stopped(let reason) = core.state {
                BentoCoreDownView(core: core, reason: reason)
                    .transition(.opacity)
            } else {
                HStack(alignment: .top, spacing: BentoSpace.s20) {
                    BentoOverviewMain()
                    BentoOverviewSidePanel()
                        .frame(width: BentoMetric.sidePanelWidth)
                }
                .transition(.opacity)
            }
        }
        .animation(BentoMotion.smooth, value: isDown)
        .bentoPageInsets()
    }
}

/// 左边的主体，讲「量」：调用和内存两张卡并排等高，下面是最近的调用，占满剩下的高度。
/// 「态」（后台服务、MCP 正不正常、需要处理的、服务入口）都在右栏，这里不重复。
/// 2026-11-14 整页重排（方案出自 Fable 评审）：去掉状态行和三张数字卡（和右栏、调用卡重复），需要处理的卡片移到右栏。
private struct BentoOverviewMain: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let services = store.services
        VStack(spacing: BentoSpace.s12) {
            // 等高：这一排取两张卡里高的那个，矮的由卡片内部拉满
            HStack(alignment: .top, spacing: BentoSpace.s12) {
                BentoCallChartCard(serviceOrder: services.map(\.name), tones: BentoServiceTones(services))
                BentoMemoryCard()
            }
            .fixedSize(horizontal: false, vertical: true)

            BentoCallTable(matches: { _ in true }, showsService: false, limit: 50)
        }
    }
}
