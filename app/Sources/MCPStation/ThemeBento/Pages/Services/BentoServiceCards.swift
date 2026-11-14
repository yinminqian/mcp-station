import SwiftUI

/// 「包含的 MCP」：全部 MCP 的勾选清单。默认服务勾的是开关，命名服务勾的是成员。
struct BentoServiceMembersCard: View {
    let service: ServiceSummary
    let allMCPs: [MCPServer]

    @Environment(AppStore.self) private var store
    @Environment(\.bentoCoreRunning) private var coreRunning

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: BentoSpace.s16, alignment: .leading), count: 2)

    var body: some View {
        let members = Set(service.members.map(\.name))
        BentoCard {
            VStack(alignment: .leading, spacing: BentoSpace.s8) {
                BentoSectionLabel(service.isDefault
                    ? "包含的 MCP（= 所有开关打开的 MCP）"
                    : "包含的 MCP（勾选即生效，不受“默认服务”开关影响）")
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: BentoSpace.s2) {
                    ForEach(allMCPs) { mcp in
                        let isMember = members.contains(mcp.name)
                        Toggle(isOn: Binding(get: { isMember }, set: { set(mcp, $0) })) {
                            HStack(spacing: BentoSpace.s8) {
                                BentoStatusDot(status: mcp.state.bentoStatus)
                                Text(mcp.name).bentoText(.body)
                                Text("\(mcp.toolCount)").bentoText(.body, BentoColor.Ink.tertiary)
                                if isMember && !mcp.inDefault {
                                    BentoPillChip("默认已关", tone: .panel)
                                }
                            }
                            .lineLimit(1)
                        }
                        .toggleStyle(.bentoCheckbox)
                        .frame(height: BentoSpace.s32)
                        .disabled(!coreRunning)
                    }
                }
            }
        }
    }

    private func set(_ mcp: MCPServer, _ on: Bool) {
        if service.isDefault {
            store.setDefault(mcp.name, on: on)
        } else {
            store.toggleMember(mcp.name, in: service.name)
        }
    }
}

/// 「客户端配置」：选客户端类型，给出要粘贴的命令或 JSON。
struct BentoClientConfigCard: View {
    let service: ServiceSummary
    let port: Int

    @State private var target: ClientTarget = .local

    var body: some View {
        let command = Format.clientCommand(service: service, client: target, port: port)
        BentoCard {
            VStack(alignment: .leading, spacing: BentoSpace.s12) {
                BentoSectionLabel("客户端配置")
                BentoSegmentedPills(ClientTarget.allCases, selection: $target,
                                    track: BentoColor.Bg.panel, title: \.rawValue)
                HStack(alignment: .top, spacing: BentoSpace.s12) {
                    Text(command)
                        .bentoText(.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: BentoMetric.controlHeightSmall, alignment: .leading)
                        .contentTransition(.opacity)
                    BentoCopyButton(text: command, key: "client-config", style: .labeled, tone: .ink)
                }
                .padding(.leading, BentoSpace.s16)
                .padding([.vertical, .trailing], BentoSpace.s8)
                .background(BentoColor.Bg.panel, in: RoundedRectangle(cornerRadius: BentoRadius.md, style: .continuous))
                Text(hint)
                    .bentoText(.label, BentoColor.Ink.tertiary)
            }
            .animation(BentoMotion.snappy, value: target)
        }
    }

    private var hint: String {
        switch target {
        case .local: "在本机终端里运行一次即可；地址只监听 127.0.0.1"
        case .container: "容器里用 host.docker.internal 代替 127.0.0.1，换网络不受影响"
        case .json: "写进客户端的 MCP 配置文件；容器里把 127.0.0.1 换成 host.docker.internal"
        }
    }
}

/// 「检查」：聚合后会不会出问题。
struct BentoServiceChecksCard: View {
    let service: ServiceSummary

    var body: some View {
        let longest = service.longestToolName
        let health = BentoCopy.health(service)
        BentoCard {
            VStack(alignment: .leading, spacing: 0) {
                BentoSectionLabel("检查").padding(.bottom, BentoSpace.s4)
                check("工具名", longest <= ServiceSummary.toolNameLimit ? .ok : .error,
                      "最长 \(longest) 字符（上限 \(ServiceSummary.toolNameLimit)）")
                check("名字冲突", .ok, "无（工具名都带 MCP 名前缀）")
                check("合并后的说明", .ok, service.withInstructions > 0
                    ? "\(service.withInstructions) 个 MCP 有说明，共 \(Format.count(service.instructionsLength)) 字"
                    : "没有 MCP 带说明")
                check("MCP 状态", health.status, health.text)
            }
        }
    }

    private func check(_ key: String, _ status: BentoStatus, _ text: String) -> some View {
        BentoKeyValueRow(key: key) {
            HStack(spacing: BentoSpace.s8) {
                BentoStatusDot(status: status)
                Text(text).bentoText(.body).contentTransition(.numericText())
            }
        }
    }
}
