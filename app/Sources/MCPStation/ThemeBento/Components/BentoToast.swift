import SwiftUI

/// 窗口底部的一句话提示（操作失败等）。读 `store.toast`，自己负责进出场。
struct BentoToastHost: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = store.toast {
                BentoToastPill(toast: toast)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, BentoSpace.s24)
        .animation(BentoMotion.snappy, value: store.toast)
    }
}

private struct BentoToastPill: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: BentoSpace.s8) {
            if toast.style == .error { BentoStatusDot(status: .error) }
            Text(toast.text).bentoText(.bodyStrong, BentoColor.Ink.inverse)
        }
        .padding(.horizontal, BentoSpace.s16)
        .frame(minHeight: BentoMetric.controlHeight)
        .background(BentoColor.Bg.inverse, in: Capsule())
        .shadow(color: BentoColor.Ink.black.opacity(BentoOpacity.shadow), radius: BentoSpace.s12, y: BentoSpace.s6)
        .accessibilityAddTraits(.isStaticText)
    }
}
