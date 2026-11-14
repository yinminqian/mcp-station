import SwiftUI

/// 概览右栏，讲「态」：后台服务 → MCP 正不正常 → 需要处理的（有才出现）→ 我的服务。
/// 调用、内存、最近调用在主区域（BentoOverviewMain）。
struct BentoOverviewSidePanel: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        let services = store.services
        let tones = BentoServiceTones(services)
        let attention = store.attention
        BentoPanel {
            ScrollView {
                VStack(alignment: .leading, spacing: BentoSpace.s10) {
                    BentoCoreHeader()
                    BentoMCPHealthRow()
                    ForEach(attention) { BentoAttentionCard(mcp: $0) }
                    Text("我的服务")
                        .bentoText(.body, BentoColor.Ink.secondary)
                    ForEach(services) { service in
                        Button {
                            nav.show(service: service.name)
                        } label: {
                            BentoServiceRow(service: service, tone: tones[service.name], isCompact: true)
                        }
                        .buttonStyle(.bentoCard())
                    }
                }
                .padding(BentoSpace.s16)
                .animation(BentoMotion.smooth, value: attention.map(\.name))
            }
            .scrollIndicators(.never)
        }
    }
}

/// 右栏顶部：后台服务的大图标、状态、地址和运行时长、重启。
private struct BentoCoreHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        let core = store.core
        VStack(spacing: BentoSpace.s6) {
            HStack(alignment: .top) {
                BentoIconButton(icon: .terminal, label: "后台服务设置") { nav.route = .settings }
                Spacer()
                BentoIconCircle(icon: .core, size: BentoMetric.iconCircleLarge,
                                fill: BentoColor.Ink.black, ink: BentoColor.Ink.inverse)
                Spacer()
                BentoRestartCoreButton(style: .icon)
            }
            HStack(spacing: BentoSpace.s8) {
                BentoStatusDot(status: BentoStatus(core: core))
                Text(core.bentoHeadline).bentoText(.title)
            }
            // 「127.0.0.1:8090 · 已运行 3 小时 12 分」，和菜单栏面板头部同一写法
            HStack(spacing: BentoSpace.s4) {
                if let core {
                    Text(BentoCopy.address(port: core.port))
                    Text("·")
                }
                BentoCoreDetailLine(core: core, showsPID: false)
            }
            .bentoText(.label, BentoColor.Ink.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 「MCP　● 12 / 13 正常 ›」，点进 MCP 页（有需要处理的就直接选中它）。整页只有这里说 MCP 正不正常。
private struct BentoMCPHealthRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        let attention = store.attention
        Button {
            if let first = attention.first { nav.show(mcp: first.name) } else { nav.route = .mcps }
        } label: {
            HStack(spacing: BentoSpace.s10) {
                BentoIconCircle(icon: .mcps, size: BentoSpace.s32, fill: BentoColor.Bg.panel)
                Text("MCP").bentoText(.bodyStrong)
                Spacer(minLength: BentoSpace.s4)
                BentoPillChip("\(store.healthyCount) / \(store.activeMCPs.count) 正常",
                              tone: attention.isEmpty ? .mint : .peach, dot: attention.isEmpty ? .ok : .warn)
                BentoIcon.chevronRight.image
                    .font(.system(size: BentoMetric.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(BentoColor.Ink.primary)
            }
            .padding(.leading, BentoSpace.s6)
            .padding(.trailing, BentoSpace.s14)
            .frame(height: BentoMetric.railButton)
            .background(BentoColor.Bg.surface, in: Capsule())
        }
        .buttonStyle(.bentoCard(radius: BentoMetric.railButton / 2))
    }
}
