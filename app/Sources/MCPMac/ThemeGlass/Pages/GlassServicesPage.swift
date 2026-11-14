import SwiftUI

/// 服务页：左边服务表格，右边选中服务的组成、客户端配置和检查。
struct GlassServicesPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        let services = store.services

        HStack(spacing: 0) {
            Table(services, selection: $nav.selectedService) {
                TableColumn("名称") { s in Text(s.name) }.width(min: 70, ideal: 90)
                TableColumn("地址") { s in Text(s.path).font(.system(size: 11, design: .monospaced)) }
                    .width(min: 90, ideal: 120)
                TableColumn("组成") { s in Text("\(s.members.count) 个 · \(s.toolCount) 工具").monospacedDigit() }
                    .width(min: 90, ideal: 110)
                TableColumn("会话") { s in Text("\(s.sessions) 个会话").monospacedDigit().foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 70)
            }
            .alternatingRowBackgrounds()
            .frame(minWidth: 380)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\"默认\" = 所有开关打开的 MCP")
                    Text("每个 MCP 也有自己的单独地址 /servers/<名字>/mcp（工具名不加前缀）")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            Divider()

            Group {
                if let s = store.service(nav.selectedService) {
                    detail(s)
                } else {
                    ContentUnavailableView("选择一个服务", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .frame(width: 380)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detail(_ s: ServiceSummary) -> some View {
        switch nav.serviceTab {
        case .members: GlassServiceMembers(service: s)
        case .tools: GlassAggregatedTools(service: s)
        case .instructions: GlassMergedInstructions(service: s)
        case .calls: GlassServiceCalls(service: s)
        }
    }
}

private struct GlassServiceMembers: View {
    var service: ServiceSummary
    @Environment(AppStore.self) private var store
    @State private var client: ClientTarget = .local

    var body: some View {
        let port = store.core?.port ?? ConfigFile.defaultPort
        Form {
            Section {
                ForEach(store.mcps) { m in
                    let included = service.isDefault ? m.inDefault : service.members.contains { $0.name == m.name }
                    Toggle(isOn: Binding(
                        get: { included },
                        set: { _ in
                            if service.isDefault { store.setDefault(m.name, on: !m.inDefault) }
                            else { store.toggleMember(m.name, in: service.name) }
                        })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.name)
                                Text(subtitle(m)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            GlassStatusDot(state: m.state)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                Text("\(service.name) 包含的 MCP · \(service.members.count) 个\(service.healthy == service.members.count ? "都正常" : "，\(service.members.count - service.healthy) 个异常")")
            } footer: {
                Text(service.isDefault ? "这里的勾选就是各 MCP 的\"默认\"开关。" : "勾选即生效，不受\"默认服务\"开关影响。")
            }

            Section {
                Picker("客户端", selection: $client) {
                    ForEach(ClientTarget.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack(alignment: .top) {
                    Text(Format.clientCommand(service: service, client: client, port: port))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GlassCopyButton(text: Format.clientCommand(service: service, client: client, port: port),
                                    key: "cmd:\(service.name):\(client.rawValue)", label: "复制配置")
                }
            } header: {
                Text("客户端配置")
            } footer: {
                Text("容器里用 host.docker.internal 代替 127.0.0.1，换网络不受影响。")
            }

            Section("检查") {
                LabeledContent("工具名") {
                    check(service.longestToolName <= ServiceSummary.toolNameLimit, "最长 \(service.longestToolName) 字符（上限 \(ServiceSummary.toolNameLimit)）")
                }
                LabeledContent("名字冲突") { check(true, "无") }
                LabeledContent("合并后的说明") {
                    check(true, service.withInstructions == 0 ? "没有 MCP 带说明"
                          : "\(service.withInstructions) 个 MCP 有说明，共 \(Format.count(service.instructionsLength)) 字")
                }
            }
        }
        .formStyle(.grouped)
        .animation(.snappy, value: service.members.map(\.name))
    }

    private func subtitle(_ m: MCPServer) -> String {
        var parts = ["\(m.toolCount) 工具"]
        if !service.isDefault && !m.inDefault { parts.append("默认已关") }
        if m.state != .ready { parts.append(Format.stateLabel(m.state)) }
        return parts.joined(separator: " · ")
    }

    private func check(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : .orange).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct GlassAggregatedTools: View {
    var service: ServiceSummary

    var body: some View {
        List {
            ForEach(service.members) { m in
                Section("\(m.name) · \(m.toolCount)") {
                    ForEach(m.tools) { t in
                        Text(service.members.count > 1 || service.isDefault ? "\(m.name)__\(t.name)" : t.name)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
        .overlay { if service.members.isEmpty { ContentUnavailableView("还没有勾选 MCP", systemImage: "square.dashed") } }
    }
}

private struct GlassMergedInstructions: View {
    var service: ServiceSummary

    var body: some View {
        Form {
            Section {
                ForEach(service.members.filter { $0.instructionsLength > 0 }) { m in
                    LabeledContent("## \(m.name)", value: "\(m.instructionsLength) 字")
                }
            } footer: {
                Text("客户端 initialize 时拿到的说明，按 MCP 加小标题后拼接。")
            }
        }
        .formStyle(.grouped)
        .overlay {
            if service.withInstructions == 0 { ContentUnavailableView("没有 MCP 带使用说明", systemImage: "text.alignleft") }
        }
    }
}

private struct GlassServiceCalls: View {
    var service: ServiceSummary
    @Environment(AppStore.self) private var store

    var body: some View {
        let calls = Array(store.calls.lazy.filter { $0.service == service.name }.suffix(200).reversed())
        Table(calls) {
            TableColumn("时间") { c in Text(Format.time(c.time)).monospacedDigit() }.width(64)
            TableColumn("MCP") { c in Text(c.mcp) }
            TableColumn("工具") { c in Text(c.tool).font(.system(size: 11, design: .monospaced)) }
            TableColumn("耗时") { c in Text(Format.duration(c.duration)).monospacedDigit() }.width(54)
        }
        .alternatingRowBackgrounds()
    }
}
