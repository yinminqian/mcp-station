import AppKit
import SwiftUI

/// 管不了的时候的概览页：配置文件读不了（将来网关接入后，也用来显示网关没运行的原因）。
/// 只用 CoreStatus 里带来的原因，不依赖网关的接口。
struct BentoCoreDownView: View {
    let core: CoreStatus
    let reason: CoreDownReason

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BentoSpace.s12) {
                HStack(spacing: BentoSpace.s8) {
                    BentoStatusDot(status: .error)
                    Text(reason.title).bentoText(.headline, BentoColor.Ink.black)
                }
                BentoAlertCard(tone: .rose) {
                    Text(reason.title)
                } message: {
                    Text(reason.detail).textSelection(.enabled)
                } actions: {
                    BentoFlowLayout {
                        BentoRestartCoreButton(tone: .ink, size: .small)
                        Button {
                            ConfigTransfer.revealConfigFile()
                        } label: {
                            Label(String(localized: "在访达中显示配置文件"), bento: .folder)
                        }
                        .buttonStyle(.bento(.surface, size: .small))
                    }
                }
                .frame(maxWidth: BentoMetric.alertColumnMaxWidth)
                if !reason.logTail.isEmpty {
                    BentoLogBlock(title: String(localized: "日志最后 \(reason.logTail.count) 行"),
                                  lines: reason.logTail.enumerated().map { BentoLogLine(raw: $1, index: $0) })
                }
            }
            .padding(.leading, BentoSpace.s16)
            .padding(.trailing, BentoSpace.s24)
            .padding(.bottom, BentoSpace.s20)
        }
        .scrollIndicators(.never)
    }
}
