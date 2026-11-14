import SwiftUI

/// MCP 页：左边列表，右边选中那个的详情。
struct BentoMCPsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        HStack(alignment: .top, spacing: BentoSpace.s16) {
            BentoMCPList()
                .frame(width: BentoMetric.listColumnWidth)
            BentoPanel {
                if let mcp = store.mcp(nav.selectedMCP) {
                    BentoMCPDetail(mcp: mcp)
                        .id(mcp.name)
                        .transition(.opacity)
                } else {
                    BentoEmptyState(icon: .mcps, text: "在左边选一个 MCP")
                        .frame(maxHeight: .infinity)
                }
            }
            .animation(BentoMotion.smooth, value: nav.selectedMCP)
        }
        .bentoPageInsets()
        // 进来没选中（或选中的被删了）就选第一个，右边不留空
        .task(id: store.mcps.map(\.name)) {
            if store.mcp(nav.selectedMCP) == nil, let first = store.mcps.first { nav.selectedMCP = first.name }
        }
    }
}

private struct BentoMCPList: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.bentoCoreRunning) private var coreRunning

    /// 由按钮或菜单栏"添加 MCP…"（Navigator.request）打开。
    private var adding: Binding<Bool> {
        Binding { nav.request == .addMCP } set: { if !$0 { nav.request = nil } }
    }

    var body: some View {
        @Bindable var nav = nav
        let query = nav.mcpSearch.trimmingCharacters(in: .whitespaces)
        let rows = store.mcps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }

        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            HStack(spacing: BentoSpace.s8) {
                Text("MCP").bentoText(.headline, BentoColor.Ink.black)
                BentoPillChip("\(store.mcps.count) 个", tone: .panel)
                Spacer()
                Button {
                    nav.request = .addMCP
                } label: {
                    Label("添加 MCP", bento: .add)
                }
                .buttonStyle(.bento(.ink, size: .small))
                .disabled(!coreRunning)
                // 新建表单用正式的弹窗（sheet），不用气泡（2026-11-14 用户要求"正经一点"）
                .sheet(isPresented: adding) { BentoAddMCPForm() }
            }
            .frame(height: BentoMetric.controlHeight)

            BentoSearchField(prompt: "搜索 MCP", text: $nav.mcpSearch)

            ScrollView {
                LazyVStack(spacing: BentoSpace.s8) {
                    ForEach(rows) { mcp in
                        BentoMCPListRow(mcp: mcp, usedBy: store.usedBy(mcp),
                                        isSelected: mcp.name == nav.selectedMCP) {
                            nav.selectedMCP = mcp.name
                        } setDefault: { on in
                            store.setDefault(mcp.name, on: on)
                        }
                    }
                    if store.mcps.isEmpty {
                        // 第一次打开：引导添加或导入
                        VStack(spacing: BentoSpace.s10) {
                            BentoEmptyState(icon: .mcps, text: "还没有 MCP。点右上角「添加 MCP」，或导入现有的配置（Claude Code、Cursor 等的 mcpServers）")
                            Button("导入配置…") { ConfigTransfer.importFromFile(store: store) }
                                .buttonStyle(.bento(.ink, size: .small))
                                .disabled(!coreRunning)
                        }
                    } else if rows.isEmpty {
                        BentoEmptyState(icon: .search, text: "没有符合条件的 MCP")
                    }
                }
                .padding(.bottom, BentoSpace.s12)
                .animation(BentoMotion.smooth, value: rows.map(\.name))
            }
            .scrollIndicators(.never)
        }
    }
}

/// 列表里的一行：状态点、名字、一句话摘要、默认服务开关。
private struct BentoMCPListRow: View {
    let mcp: MCPServer
    let usedBy: [String]
    let isSelected: Bool
    let select: () -> Void
    let setDefault: (Bool) -> Void

    @Environment(\.bentoCoreRunning) private var coreRunning
    @State private var hovering = false

    var body: some View {
        let isStopped = mcp.state == .stopped
        let shape = RoundedRectangle(cornerRadius: BentoRadius.md, style: .continuous)
        HStack(spacing: BentoSpace.s8) {
            Button(action: select) {
                HStack(spacing: BentoSpace.s12) {
                    BentoStatusDot(status: mcp.state.bentoStatus)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mcp.name)
                            .bentoText(.bodyStrong, isStopped ? BentoColor.Ink.tertiary : BentoColor.Ink.primary)
                        summary.bentoText(.label, BentoColor.Ink.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if mcp.memory != nil {
                BentoMemoryText(bytes: mcp.memory)
                    .bentoText(.label, BentoColor.Ink.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Toggle(isOn: Binding(get: { mcp.inDefault }, set: { setDefault($0) })) {
                Text("\(mcp.name) 加入默认服务")
            }
            .disabled(!coreRunning)
        }
        .padding(.leading, BentoSpace.s16)
        .padding(.trailing, BentoSpace.s14)
        .frame(height: BentoSpace.s48 + BentoSpace.s10)
        .background(BentoColor.Bg.surface, in: shape)
        .overlay(shape.fill(BentoTone.surface.hoverVeil).opacity(hovering && !isSelected ? 1 : 0).allowsHitTesting(false))
        .overlay(shape.strokeBorder(BentoColor.Ink.black, lineWidth: BentoMetric.selectionStroke)
            .opacity(isSelected ? 1 : 0))
        .onHover { hovering = $0 }
        .animation(BentoMotion.hover, value: hovering)
        .animation(BentoMotion.hover, value: isSelected)
    }

    /// 「npx · 24 工具 · 默认、ios」；等待重试时中间换成倒计时。
    private var summary: some View {
        let services = usedBy.isEmpty ? "没有服务用到" : usedBy.joined(separator: "、")
        return HStack(spacing: BentoSpace.s4) {
            Text(mcp.kind.label)
            Text("·")
            switch mcp.state {
            case .backoff(_, let retryAt, _):
                BentoCountdown(target: retryAt) { "等待重试 \($0)s" }
            case .ready:
                Text("\(mcp.toolCount) 工具")
            case .starting, .configError, .stopped:
                Text(Format.stateLabel(mcp.state))
            }
            Text("·")
            Text(services)
        }
    }
}
