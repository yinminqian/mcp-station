import SwiftUI

enum BentoServiceTab: String, CaseIterable, Identifiable {
    case members, tools, instructions, calls
    var id: String { rawValue }

    func label(for service: ServiceSummary) -> BentoCountLabel {
        switch self {
        case .members: BentoCountLabel(String(localized: "组成"))
        case .tools: BentoCountLabel(String(localized: "聚合后的工具"), count: service.toolCount)
        case .instructions: BentoCountLabel(String(localized: "合并后的说明"))
        case .calls: BentoCountLabel(String(localized: "调用"))
        }
    }
}

/// 服务详情：名字和操作、页签、页签内容。
struct BentoServiceDetail: View {
    let service: ServiceSummary
    @Binding var tab: BentoServiceTab

    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: BentoSpace.s16) {
            BentoServiceDetailHeader(service: service)
            BentoSegmentedPills(items: BentoServiceTab.allCases, selection: $tab) { tab in
                tab.label(for: service)
            }
            BentoTabStack(tabs: BentoServiceTab.allCases, selection: tab) { t in
                content(t)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(BentoSpace.s20)
    }

    @ViewBuilder private func content(_ tab: BentoServiceTab) -> some View {
        switch tab {
        case .members:
            ScrollView {
                VStack(spacing: BentoSpace.s12) {
                    BentoServiceMembersCard(service: service, allMCPs: store.mcps)
                    if let port = store.core?.port {
                        BentoClientConfigCard(service: service, port: port)
                    }
                    BentoServiceChecksCard(service: service)
                    BentoNote(tag: String(localized: "说明"), text: note, tone: .surface)
                }
            }
            .scrollIndicators(.never)
        case .tools:
            BentoServiceToolsTab(service: service)
        case .instructions:
            BentoServiceInstructionsTab(service: service)
        case .calls:
            BentoCallTable(matches: { $0.service == service.name }, showsService: false)
        }
    }

    /// 开关和勾选的关系，用这个服务自己的成员举例。
    private var note: String {
        if service.isDefault {
            return String(localized: "默认服务 = 所有开关打开的 MCP。在这里勾选，和在 MCP 页拨开关是同一件事。")
        }
        let offByDefault = service.members.filter { !$0.inDefault }.map(\.name)
        let base = String(localized: "开关只管默认服务；命名服务按勾选。")
        guard !offByDefault.isEmpty else { return base }
        return base + String(localized: "\(offByDefault.joined(separator: "、")) 的默认开关是关的，但在 \(service.name) 里照样有。")
    }
}

/// 名字、健康状况、重命名和删除（默认服务不能改名、不能删）。
private struct BentoServiceDetailHeader: View {
    let service: ServiceSummary

    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.bentoCoreRunning) private var coreRunning
    @State private var renaming = false
    @State private var confirmingDelete = false

    var body: some View {
        let health = BentoCopy.health(service)
        HStack(spacing: BentoSpace.s12) {
            Text(service.name)
                .bentoText(.headline, BentoColor.Ink.black)
                .lineLimit(1)
            BentoPillChip(health.text, tone: health.status.tone, dot: health.status)
            Spacer(minLength: BentoSpace.s8)
            if !service.isDefault {
                Button {
                    renaming = true
                } label: {
                    Label(String(localized: "重命名"), bento: .edit)
                }
                .buttonStyle(.bentoSecondary)
                .popover(isPresented: $renaming, arrowEdge: .bottom) {
                    BentoNamePopover(title: String(localized: "重命名「\(service.name)」"), actionTitle: String(localized: "保存"), initial: service.name) { newName in
                        let ok = await store.renameService(service.name, to: newName)
                        if ok { nav.selectedService = newName }
                        return ok
                    }
                }
                Button {
                    confirmingDelete = true
                } label: {
                    Label(String(localized: "删除"), bento: .delete)
                }
                .buttonStyle(.bento(.rose))
                .confirmationDialog("删除服务「\(service.name)」？", isPresented: $confirmingDelete) {
                    Button("删除", role: .destructive) {
                        store.deleteService(service.name)
                        nav.selectedService = store.services.first?.name
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("地址 \(service.path) 会失效；里面的 MCP 本身不会被删。")
                }
            }
        }
        .frame(height: BentoMetric.controlHeight)
        .disabled(!coreRunning)
    }
}
