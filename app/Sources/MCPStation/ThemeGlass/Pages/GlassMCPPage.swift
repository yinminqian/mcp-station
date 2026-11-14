import SwiftUI

/// MCP 页：左边原生表格，右边选中项的详情（系统设置式分组表单）。
/// 工具栏、搜索框、标题在 GlassRoot 统一声明（见 GlassToolbar），页面里不声明。
struct GlassMCPPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    @State private var sortOrder = [KeyPathComparator(\MCPRow.name, comparator: .localizedStandard)]

    var body: some View {
        @Bindable var nav = nav
        let rows = visibleRows

        HStack(spacing: 0) {
            Table(rows, selection: $nav.selectedMCP, sortOrder: $sortOrder) {
                TableColumn("名称", value: \.name) { r in
                    Text(r.name).foregroundStyle(r.server.state == .stopped ? .tertiary : .primary)
                }
                .width(min: 100, ideal: 120)
                TableColumn("状态", value: \.stateRank) { r in
                    HStack(spacing: 6) {
                        GlassStatusDot(state: r.server.state, size: 7)
                        GlassStateText(state: r.server.state)
                            .foregroundStyle(r.server.state == .stopped ? .tertiary : .primary)
                    }
                }
                .width(min: 96, ideal: 105)
                TableColumn("工具", value: \.toolCount) { r in
                    Text(r.server.state == .stopped ? "—" : "\(r.toolCount)").monospacedDigit()
                }
                .width(min: 34, ideal: 40)
                TableColumn("内存", value: \.memorySort) { r in
                    Text(Format.bytes(r.server.memory))
                        .monospacedDigit()
                        .foregroundStyle(r.server.memory == nil ? .tertiary : .primary)
                }
                .width(min: 52, ideal: 58)
                TableColumn("服务") { r in
                    Text(r.usedBy.isEmpty ? "无" : r.usedBy.joined(separator: "、"))
                        .foregroundStyle(r.usedBy.isEmpty ? .tertiary : .secondary)
                }
                .width(min: 56, ideal: 70)
                TableColumn("默认") { r in
                    Toggle("加入默认服务", isOn: Binding(
                        get: { r.server.inDefault },
                        set: { store.setDefault(r.name, on: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .width(40)
            }
            .alternatingRowBackgrounds()
            .frame(minWidth: 380)

            Divider()

            Group {
                if let m = store.mcp(nav.selectedMCP) {
                    GlassMCPDetail(server: m)
                } else if store.mcps.isEmpty {
                    // 第一次打开：引导添加或导入
                    ContentUnavailableView {
                        Label("还没有 MCP", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("添加一个，或导入现有的配置（Claude Code、Cursor 等的 mcpServers）。")
                    } actions: {
                        Button("添加 MCP…") { nav.request = .addMCP }
                        Button("导入配置…") { ConfigTransfer.importFromFile(store: store) }
                    }
                } else {
                    ContentUnavailableView("选择一个 MCP", systemImage: "puzzlepiece.extension",
                                           description: Text("在左边的表格里选一个，查看状态、定义和日志。"))
                }
            }
            .frame(width: 380)
            .frame(maxHeight: .infinity)
        }
        // 进来没选中（或选中的被删了）就选第一个
        .task(id: rows.map(\.name)) {
            if store.mcp(nav.selectedMCP) == nil, let first = rows.first { nav.selectedMCP = first.name }
        }
    }

    private var visibleRows: [MCPRow] {
        let q = nav.mcpSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return store.mcps
            .filter { m in
                switch nav.mcpFilter {
                case .all: true
                case .attention: m.state.needsAttention
                case .stopped: m.state == .stopped
                }
            }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .map { MCPRow(server: $0, usedBy: store.usedBy($0)) }
            .sorted(using: sortOrder)
    }
}

/// 表格行。把排序要用的键摊平成属性，KeyPathComparator 才能直接用。
struct MCPRow: Identifiable {
    var server: MCPServer
    var usedBy: [String]
    var id: String { server.name }
    var name: String { server.name }
    var toolCount: Int { server.toolCount }
    var memorySort: Int64 { server.memory ?? -1 }
    var stateRank: Int {
        switch server.state {
        case .configError: 0
        case .backoff: 1
        case .starting: 2
        case .ready: 3
        case .stopped: 4
        }
    }
}

// MARK: - 详情

struct GlassMCPDetail: View {
    var server: MCPServer
    @Environment(Navigator.self) private var nav

    var body: some View {
        switch nav.mcpTab {
        case .overview: GlassMCPOverview(server: server)
        case .tools: GlassToolList(server: server)
        case .resources: GlassResourcesInfo(server: server)
        case .logs: GlassFullLog(server: server)
        case .calls: GlassMCPCalls(server: server)
        }
    }
}

private struct GlassMCPOverview: View {
    var server: MCPServer
    @Environment(AppStore.self) private var store
    @State private var revealed: Set<String> = []

    var body: some View {
        let port = store.core?.port ?? ConfigFile.defaultPort
        Form {
            if case .backoff(let reason, _, let attempts) = server.state {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(server.name) 连不上上游")
                            HStack(spacing: 0) {
                                GlassStateText(state: server.state)
                                Text(" · 已重试 \(attempts) 次")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("\(reason)。其他 \(store.mcps.count - 1) 个 MCP 不受影响；上游恢复后会自动连上，不需要重启任何东西。")
                }
            } else if case .configError(let why) = server.state {
                Section {
                    Label(why, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            } else if server.state == .stopped {
                Section {
                    Label("没有服务用到它，所以没在运行", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("打开\"默认\"开关，或在某个命名服务里勾选它，它就会启动。")
                }
            }

            Section("定义") {
                LabeledContent("类型", value: server.kind.label)
                ForEach(server.definition) { f in
                    LabeledContent(f.key) {
                        HStack(spacing: 6) {
                            Text(f.secret && !revealed.contains(f.key) ? "••••••••" : f.value)
                                .font(f.monospaced ? .system(size: 11, design: .monospaced) : nil)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            if f.secret {
                                Button(revealed.contains(f.key) ? "隐藏" : "显示") {
                                    withAnimation(.snappy) {
                                        if revealed.contains(f.key) { revealed.remove(f.key) } else { revealed.insert(f.key) }
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                LabeledContent("用到它的服务") {
                    let used = store.usedBy(server)
                    Text(used.isEmpty ? "无" : used.joined(separator: "、"))
                }
                LabeledContent("单独地址") {
                    HStack(spacing: 6) {
                        Text(verbatim: Format.mcpURL(server.name, port: port))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        GlassCopyButton(text: Format.mcpURL(server.name, port: port),
                                        key: "addr:\(server.name)", label: "复制单独地址")
                    }
                }
            }

            Section("运行") {
                LabeledContent("进程") { Text(server.pid.map { "pid \(String($0))" } ?? "—").monospacedDigit() }
                if let since = server.startedAt {
                    LabeledContent("已运行") {
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            Text(Format.uptime(since: since, now: ctx.date))
                        }
                    }
                }
                LabeledContent("内存") {
                    HStack(spacing: 10) {
                        if server.memoryHistory.count > 1 {
                            Sparkline(values: server.memoryHistory.map(Double.init), color: .purple, baselineAtZero: false)
                                .frame(width: 90, height: 18)
                        }
                        Text(server.memory == nil ? (server.kind == .http ? "无本地进程" : "—") : Format.bytes(server.memory))
                            .monospacedDigit()
                    }
                }
                .help("进程组（含子进程）的 RSS 合计，每 5 秒采样")
                LabeledContent("能力", value: "\(server.toolCount) 工具 · \(server.resourceCount) resources · \(server.promptCount) prompts")
                if server.instructionsLength > 0 {
                    LabeledContent("使用说明", value: "\(server.instructionsLength) 字")
                }
            }

            Section("最近日志（stderr 最后 6 行）") {
                GlassLogView(lines: Array(server.stderr.suffix(6)))
                    .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .contentMargins(.top, 4, for: .scrollContent)
    }
}

private struct GlassToolList: View {
    var server: MCPServer
    @State private var query = ""

    var body: some View {
        let q = query.lowercased()
        let tools = server.tools.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
        List(tools) { t in
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.system(.body, design: .monospaced))
                if !t.summary.isEmpty {
                    Text(t.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TextField("筛选工具", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
        }
        .overlay {
            if tools.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }
}

private struct GlassResourcesInfo: View {
    var server: MCPServer

    var body: some View {
        Form {
            Section {
                LabeledContent("Resources", value: "\(server.resourceCount)")
                LabeledContent("Prompts", value: "\(server.promptCount)")
                LabeledContent("使用说明", value: server.instructionsLength > 0 ? "\(server.instructionsLength) 字" : "无")
            } footer: {
                Text("聚合到服务时，resources 按原 URI 路由回 \(server.name)，prompts 以 \(server.name)__ 为前缀。")
            }
        }
        .formStyle(.grouped)
    }
}

private struct GlassFullLog: View {
    var server: MCPServer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GlassLogView(lines: server.stderr)
                    .padding(12)
                Color.clear.frame(height: 1).id("end")
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: server.stderr.last?.id) { withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .background(.background)
    }
}

private struct GlassMCPCalls: View {
    var server: MCPServer
    @Environment(AppStore.self) private var store

    var body: some View {
        let calls = store.calls.lazy.filter { $0.mcp == server.name }.suffix(200).reversed()
        Table(Array(calls)) {
            TableColumn("时间") { c in Text(Format.time(c.time)).monospacedDigit() }.width(64)
            TableColumn("工具") { c in Text(c.tool).font(.system(size: 11, design: .monospaced)) }
            TableColumn("耗时") { c in Text(Format.duration(c.duration)).monospacedDigit() }.width(54)
            TableColumn("") { c in
                Image(systemName: c.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(c.isError ? .red : .green)
            }
            .width(20)
        }
        .alternatingRowBackgrounds()
        .overlay {
            if calls.isEmpty {
                ContentUnavailableView("最近一小时没有调用", systemImage: "clock")
            }
        }
    }
}
