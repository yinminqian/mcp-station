import SwiftUI

/// 菜单栏面板（MenuBarExtra .window 样式）。系统会给它玻璃菜单材质，这里只排内容。
struct GlassMenuPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.openWindow) private var openWindow

    /// 面板里最多展开显示的正常 MCP 行数，其余收进"还有 N 个正常"。
    private let visibleHealthy = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)
            if store.core?.canManage == true {
                mcpSection
                Divider().padding(.vertical, 6)
                serviceSection
            } else {
                Label(store.core.map { if case .stopped(let r) = $0.state { r.title } else { String(localized: "后台服务没有运行") } } ?? String(localized: "正在读取配置…"),
                      systemImage: "exclamationmark.octagon.fill")
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 6)
                MenuRow { open(.overview) } label: { Text("查看原因…") }
            }
            Divider().padding(.vertical, 6)
            MenuRow(shortcut: "⌘O") { open(nav.route) } label: { Text("打开主窗口…") }
            HStack {
                Text("登录时打开").foregroundStyle(.secondary)
                Spacer()
                Toggle("登录时打开", isOn: .constant(false)).toggleStyle(.switch).controlSize(.mini).labelsHidden().disabled(true)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            MenuRow(shortcut: "⌘Q") { NSApp.terminate(nil) } label: { Text("退出 MCP Station") }
        }
        .padding(10)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Station").font(.headline)
                if let core = store.core, case .notInstalled = core.state {
                    Text("网关还没接入").font(.caption).foregroundStyle(.secondary)
                }
                if let core = store.core, case .running(_, let since) = core.state {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("127.0.0.1:\(String(core.port)) · 已运行 \(Format.uptime(since: since, now: ctx.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(store.attention.isEmpty ? Color.green : .orange).frame(width: 7, height: 7)
                    Text("\(store.healthyCount) / \(store.activeMCPs.count) 正常")
                        .monospacedDigit()
                }
                .font(.callout)
                if store.totalMemory > 0 {
                    Text("内存 \(Format.bytes(store.totalMemory))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("MCP（开关 = 是否在默认服务里）")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.bottom, 3)
            ForEach(store.attention) { m in attentionRow(m) }
            let others = store.mcps.filter { !$0.state.needsAttention }
            ForEach(others.prefix(visibleHealthy)) { m in mcpRow(m) }
            if others.count > visibleHealthy {
                MenuRow { open(.mcps) } label: {
                    HStack {
                        Text("还有 \(others.count - visibleHealthy) 个")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func attentionRow(_ m: MCPServer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text(m.name)
                Spacer()
                defaultToggle(m)
            }
            if case .backoff(let reason, _, let attempts) = m.state {
                VStack(alignment: .leading, spacing: 1) {
                    Text(reason)
                    HStack(spacing: 0) {
                        GlassStateText(state: m.state)
                        Text(" · 已重试 \(attempts) 次")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 19)
            }
            HStack(spacing: 6) {
                Button("立即重试") { store.retryNow(m.name) }
                    .disabled(store.isBusy("retry:\(m.name)"))
                Button("查看详情") { nav.show(mcp: m.name); open(.mcps) }
            }
            .controlSize(.small)
            .padding(.leading, 19)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private func mcpRow(_ m: MCPServer) -> some View {
        HStack(spacing: 8) {
            GlassStatusDot(state: m.state, size: 7)
            Text(m.name).foregroundStyle(m.state == .stopped ? .tertiary : .primary)
            Spacer()
            Text(m.state == .stopped ? "未运行" : "\(m.toolCount)")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            defaultToggle(m)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
    }

    private func defaultToggle(_ m: MCPServer) -> some View {
        Toggle("\(m.name) 加入默认服务", isOn: Binding(get: { m.inDefault }, set: { store.setDefault(m.name, on: $0) }))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("服务").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.bottom, 3)
            ForEach(store.services) { s in
                HStack(spacing: 8) {
                    Text(s.name).frame(width: 40, alignment: .leading)
                    Text(s.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(s.members.count) 个 · \(s.toolCount) 工具").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    GlassCopyButton(text: Format.serviceURL(s, port: store.core?.port ?? ConfigFile.defaultPort), key: "menu:\(s.name)", label: String(localized: "复制 \(s.name) 的地址"))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
            }
        }
    }

    private func open(_ route: Navigator.Route) {
        nav.route = route
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// 菜单项样式的行：悬停高亮，右侧可带快捷键。
struct MenuRow<Label: View>: View {
    var shortcut: String?
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    init(shortcut: String? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.shortcut = shortcut
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            HStack {
                label
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(hovering ? .white.opacity(0.8) : .secondary) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .foregroundStyle(hovering ? .white : .primary)
            .background(hovering ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
