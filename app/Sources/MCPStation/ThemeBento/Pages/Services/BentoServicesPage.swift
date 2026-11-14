import SwiftUI

/// 服务页：左边每个服务一张卡片，右边选中服务的详情。
struct BentoServicesPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @State private var tab: BentoServiceTab = .members

    var body: some View {
        let services = store.services
        let tones = BentoServiceTones(services)
        HStack(alignment: .top, spacing: BentoSpace.s16) {
            BentoServiceList(services: services, tones: tones)
                .frame(width: BentoMetric.listColumnWidth)
            BentoPanel {
                if let service = services.first(where: { $0.name == nav.selectedService }) {
                    BentoServiceDetail(service: service, tab: $tab)
                } else {
                    BentoEmptyState(icon: .services, text: "在左边选一个服务")
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .bentoPageInsets()
    }
}

private struct BentoServiceList: View {
    let services: [ServiceSummary]
    let tones: BentoServiceTones

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.bentoCoreRunning) private var coreRunning

    /// 由按钮或菜单栏"新建服务…"（Navigator.request）打开。
    private var creating: Binding<Bool> {
        Binding { nav.request == .createService } set: { if !$0 { nav.request = nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            HStack {
                Text("服务").bentoText(.headline, BentoColor.Ink.black)
                Spacer()
                Button {
                    nav.request = .createService
                } label: {
                    Label("新建服务", bento: .add)
                }
                .buttonStyle(.bento(.ink, size: .small))
                .disabled(!coreRunning)
                .popover(isPresented: creating, arrowEdge: .bottom) {
                    BentoNamePopover(title: "新建服务", actionTitle: "创建") { name in
                        let ok = await store.createService(name)
                        if ok { nav.selectedService = name }
                        return ok
                    }
                }
            }
            .frame(height: BentoMetric.controlHeight)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BentoSpace.s10) {
                    ForEach(services) { service in
                        BentoServiceCard(service: service, tone: tones[service.name],
                                         isSelected: service.name == nav.selectedService) {
                            nav.selectedService = service.name
                        }
                    }
                    Text("每个 MCP 也有自己的单独地址 /servers/<名字>/mcp（工具名不加前缀）")
                        .bentoText(.label, BentoColor.Ink.tertiary)
                        .padding(.top, BentoSpace.s2)
                }
                .padding(.bottom, BentoSpace.s12)
                .animation(BentoMotion.smooth, value: services.map(\.name))
            }
            .scrollIndicators(.never)
        }
    }
}

/// 服务卡片：地址、会话数、名字、规模、健康状况。
private struct BentoServiceCard: View {
    let service: ServiceSummary
    let tone: BentoTone
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let health = BentoCopy.health(service)
        Button(action: action) {
            BentoCard(tone: tone, radius: BentoRadius.xl, padding: BentoSpace.s16, isSelected: isSelected) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: BentoSpace.s8) {
                        BentoIconCircle(BentoCatalog.icon(of: service), on: tone)
                        Text(service.path).bentoText(.mono, tone.ink).lineLimit(1)
                        Spacer(minLength: BentoSpace.s4)
                        BentoPillChip("\(service.sessions) 个会话")
                    }
                    Text(service.name)
                        .bentoText(.title)
                        .lineLimit(1)
                        .padding(.top, BentoSpace.s20)
                    Text("\(service.members.count) 个 MCP · \(service.toolCount) 工具")
                        .bentoText(.label, tone.ink)
                        .contentTransition(.numericText())
                    HStack(spacing: BentoSpace.s6) {
                        BentoStatusDot(status: health.status)
                        Text(service.isDefault ? "= 所有开关打开的 MCP · \(health.text)" : health.text)
                            .bentoText(.label, tone.ink)
                            .lineLimit(1)
                    }
                    .padding(.top, BentoSpace.s20)
                }
                .animation(BentoMotion.snappy, value: service.toolCount)
            }
        }
        .buttonStyle(.bentoCard(radius: BentoRadius.xl))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
