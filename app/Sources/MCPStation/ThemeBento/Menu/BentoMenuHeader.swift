import SwiftUI

/// 面板头部：名字、地址和运行时长、整体健康状况、内存合计。
struct BentoMenuHeader: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let core = store.core
        let attention = store.attention
        HStack(alignment: .center, spacing: BentoSpace.s8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("MCP Station").bentoText(.title, BentoColor.Ink.black)
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
            Spacer(minLength: BentoSpace.s4)
            VStack(alignment: .trailing, spacing: BentoSpace.s2) {
                switch BentoStatus(core: core) {
                case .ok:
                    BentoPillChip(String(localized: "\(store.healthyCount) / \(store.activeMCPs.count) 正常"),
                                  tone: attention.isEmpty ? .mint : .peach, dot: attention.isEmpty ? .ok : .warn)
                    BentoMemoryText(bytes: store.totalMemory, prefix: String(localized: "内存合计 "))
                        .bentoText(.label, BentoColor.Ink.secondary)
                case let status:
                    BentoPillChip(core.bentoHeadline, tone: status.tone, dot: status)
                }
            }
        }
    }
}
