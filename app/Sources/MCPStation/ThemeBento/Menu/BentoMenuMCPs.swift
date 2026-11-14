import SwiftUI

/// 面板的 MCP 段：范围切换、需要处理的卡片、其余 MCP 的开关列表。
struct BentoMenuMCPs: View {
    @Binding var scope: BentoMenuScope
    @Binding var expanded: Bool

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 收起时正常的 MCP 显示几行。
    private static let collapsedRows = 6

    var body: some View {
        let attention = store.attention
        let others = store.mcps.filter { !$0.state.needsAttention }
        let visible = expanded ? others : Array(others.prefix(Self.collapsedRows))

        BentoSegmentedPills(BentoMenuScope.allCases, selection: $scope, track: BentoColor.Bg.panel) { scope in
            switch scope {
            case .all: String(localized: "全部 \(store.mcps.count)")
            case .attention: String(localized: "需要处理 \(attention.count)")
            }
        }
        BentoSectionLabel(String(localized: "MCP（开关 = 是否在默认服务里）"))

        ForEach(attention) { mcp in
            BentoAttentionCard(mcp: mcp)
        }
        if scope == .attention && attention.isEmpty {
            BentoCard { BentoEmptyState(icon: .check, text: String(localized: "没有需要处理的 MCP")) }
        }
        if scope == .all && !others.isEmpty {
            BentoCard(padding: BentoSpace.s8) {
                VStack(spacing: 0) {
                    ForEach(visible) { mcp in
                        BentoMenuMCPRow(mcp: mcp)
                    }
                    if others.count > Self.collapsedRows {
                        Button {
                            withAnimation(reduceMotion ? nil : BentoMotion.smooth) { expanded.toggle() }
                        } label: {
                            Text(expanded ? "收起" : "还有 \(others.count - visible.count) 个 …")
                                .bentoText(.label, BentoColor.Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, BentoSpace.s12 + BentoMetric.statusDot + BentoSpace.s10)
                                .frame(height: BentoSpace.s32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// 需要处理的 MCP：原因、倒计时、立即重试、查看详情。菜单栏面板和概览页共用。
struct BentoAttentionCard: View {
    let mcp: MCPServer

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let tone = mcp.bentoCardTone
        BentoCard(tone: tone, radius: BentoRadius.xl) {
            VStack(alignment: .leading, spacing: BentoSpace.s10) {
                HStack(spacing: BentoSpace.s12) {
                    BentoIconCircle(.warning, on: tone)
                    Text(mcp.name).bentoText(.title, tone.ink).lineLimit(1)
                    Spacer(minLength: BentoSpace.s4)
                    BentoDefaultToggle(mcp: mcp)
                }
                detail(tone)
                HStack(spacing: BentoSpace.s8) {
                    // 重试期间按钮留着、图标转圈，直到出结果（成功卡片才消失，失败就更新原因）
                    let busy = mcp.state == .starting || store.isBusy("retry:\(mcp.name)")
                    if busy || isBackoff {
                        Button {
                            store.retryNow(mcp.name)
                        } label: {
                            Label {
                                Text("立即重试")
                            } icon: {
                                BentoIcon.restart.image
                                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: busy)
                            }
                        }
                        .buttonStyle(.bento(.ink, size: .small))
                        .disabled(busy)
                    }
                    Button("查看详情") {
                        BentoOpenMain(nav: nav, openWindow: openWindow)() { $0.show(mcp: mcp.name) }
                    }
                    .buttonStyle(.bento(.surface, size: .small))
                }
            }
        }
    }

    private var isBackoff: Bool { if case .backoff = mcp.state { true } else { false } }

    @ViewBuilder
    private func detail(_ tone: BentoTone) -> some View {
        switch mcp.state {
        case .starting:
            Text("正在重试…").bentoText(.body, tone.ink)
        case let .backoff(reason, retryAt, attempts):
            Text(reason)
                .bentoText(.body, tone.ink)
                .fixedSize(horizontal: false, vertical: true)
            BentoCountdown(target: retryAt) { seconds in
                seconds > 0 ? String(localized: "\(seconds) 秒后自动重试 · 已重试 \(attempts) 次") : String(localized: "正在重试… · 已重试 \(attempts) 次")
            }
            .bentoText(.label, tone.ink)
        case .configError(let message):
            Text(message)
                .bentoText(.body, tone.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .ready, .stopped:
            EmptyView()
        }
    }
}

/// 列表里的一行：状态点、名字、工具数、开关。
private struct BentoMenuMCPRow: View {
    let mcp: MCPServer

    var body: some View {
        let isStopped = mcp.state == .stopped
        HStack(spacing: BentoSpace.s10) {
            BentoStatusDot(status: mcp.state.bentoStatus)
            Text(mcp.name)
                .bentoText(.body, isStopped ? BentoColor.Ink.tertiary : BentoColor.Ink.primary)
                .lineLimit(1)
            Spacer(minLength: BentoSpace.s4)
            Text(mcp.state.isHealthy ? "\(mcp.toolCount)" : Format.stateLabel(mcp.state))
                .bentoText(.body, BentoColor.Ink.tertiary)
                .monospacedDigit()
            BentoDefaultToggle(mcp: mcp)
        }
        .padding(.horizontal, BentoSpace.s12)
        .frame(height: BentoSpace.s36)
        .bentoRowHover()
    }
}

/// 「加入默认服务」开关。
private struct BentoDefaultToggle: View {
    let mcp: MCPServer

    @Environment(AppStore.self) private var store
    @Environment(\.bentoCoreRunning) private var coreRunning

    var body: some View {
        Toggle(isOn: Binding(get: { mcp.inDefault }, set: { store.setDefault(mcp.name, on: $0) })) {
            Text("\(mcp.name) 加入默认服务")
        }
        .disabled(!coreRunning)
    }
}
