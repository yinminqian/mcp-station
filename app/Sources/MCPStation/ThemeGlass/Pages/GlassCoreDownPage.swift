import SwiftUI

/// 管不了的时候的页面：配置文件读不了（将来网关接入后，也用来显示网关没运行的原因）。
/// 只用 CoreStatus 里带来的原因，不依赖网关的接口。
struct GlassCoreDownPage: View {
    var core: CoreStatus
    var reason: CoreDownReason
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reason.title).font(.headline)
                        Text(reason.detail).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if let occ = reason.occupiedBy {
                    LabeledContent("占用端口的进程") { Text(occ).foregroundStyle(.secondary) }
                }
                HStack {
                    Button("在访达中显示配置文件") { ConfigTransfer.revealConfigFile() }
                    Spacer()
                    Button("重新检测") { store.restartCore() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isBusy("core-restart"))
                }
            }

            if !reason.logTail.isEmpty {
                Section("日志最后 \(reason.logTail.count) 行") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(reason.logTail.enumerated()), id: \.offset) { _, line in
                            Text(line).foregroundStyle(line.contains("error") ? .red : .primary)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}
