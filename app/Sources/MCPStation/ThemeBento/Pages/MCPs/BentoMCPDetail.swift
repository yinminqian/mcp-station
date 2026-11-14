import SwiftUI

/// MCP 详情：名字和操作、页签、页签内容。
struct BentoMCPDetail: View {
    let mcp: MCPServer

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        VStack(alignment: .leading, spacing: BentoSpace.s16) {
            BentoMCPDetailHeader(mcp: mcp)
            BentoSegmentedPills(items: Navigator.MCPTab.allCases, selection: $nav.mcpTab) { tab in
                tab.bentoLabel(for: mcp)
            }
            BentoTabStack(tabs: Navigator.MCPTab.allCases, selection: nav.mcpTab) { tab in
                tabContent(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(BentoSpace.s20)
    }

    @ViewBuilder
    private func tabContent(_ tab: Navigator.MCPTab) -> some View {
        switch tab {
        case .overview:
            BentoMCPOverviewTab(mcp: mcp, usedBy: store.usedBy(mcp),
                                othersHealthy: store.healthyCount - (mcp.state.isHealthy ? 1 : 0),
                                port: store.core?.port)
        case .tools:
            BentoMCPToolsTab(mcp: mcp.name, tools: mcp.tools)
        case .resources:
            BentoMCPCapabilitiesTab(mcp: mcp)
        case .logs:
            BentoLogBlock(title: String(localized: "stderr（最近 \(mcp.stderr.count) 行）"),
                          lines: mcp.stderr.map(BentoLogLine.init), fillsHeight: true)
        case .calls:
            BentoCallTable(matches: { $0.mcp == mcp.name }, showsMCP: false)
        }
    }
}

extension Navigator.MCPTab {
    func bentoLabel(for mcp: MCPServer) -> BentoCountLabel {
        switch self {
        case .overview: BentoCountLabel(String(localized: "概况"))
        case .tools: BentoCountLabel(String(localized: "工具"), count: mcp.toolCount)
        case .resources: BentoCountLabel("Resources", count: mcp.resourceCount)
        case .logs: BentoCountLabel(String(localized: "日志"))
        case .calls: BentoCountLabel(String(localized: "调用"))
        }
    }
}

/// 名字、状态药丸、当前状态下能做的那个操作。
private struct BentoMCPDetailHeader: View {
    let mcp: MCPServer

    @Environment(AppStore.self) private var store
    @Environment(\.bentoCoreRunning) private var coreRunning

    var body: some View {
        let status = mcp.state.bentoStatus
        HStack(spacing: BentoSpace.s12) {
            Text(mcp.name)
                .bentoText(.headline, BentoColor.Ink.black)
                .lineLimit(1)
            BentoPillChip(Format.stateLabel(mcp.state), tone: status.tone, dot: status)
            Spacer(minLength: BentoSpace.s8)
            action
        }
        .frame(height: BentoMetric.controlHeight)
    }

    @ViewBuilder private var action: some View {
        switch mcp.state {
        case .backoff:
            actionButton(String(localized: "立即重试"), busyKey: "retry:\(mcp.name)") { store.retryNow(mcp.name) }
        case .ready, .starting, .configError:
            actionButton(String(localized: "重启"), busyKey: "restart:\(mcp.name)") { store.restart(mcp.name) }
        case .stopped:
            EmptyView()
        }
    }

    private func actionButton(_ title: String, busyKey: String, action: @escaping () -> Void) -> some View {
        let busy = store.isBusy(busyKey) || mcp.state == .starting
        return Button(action: action) {
            Label {
                Text(title)
            } icon: {
                BentoIcon.restart.image
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: busy)
            }
        }
        .buttonStyle(.bentoPrimary)
        .disabled(busy || !coreRunning)
    }
}
