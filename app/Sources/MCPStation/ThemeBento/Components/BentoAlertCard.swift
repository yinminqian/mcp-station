import SwiftUI

/// 提示卡片：图标 + 标题 + 说明 + 一排操作。peach 表示等待重试，rose 表示出错。
struct BentoAlertCard<Title: View, Message: View, Actions: View>: View {
    var tone: BentoTone = .peach
    var icon: BentoIcon = .warning
    /// 这个值变化时图标弹一下（比如又重试失败了一次）。
    var bounce = 0
    @ViewBuilder var title: Title
    @ViewBuilder var message: Message
    @ViewBuilder var actions: Actions

    var body: some View {
        BentoCard(tone: tone, radius: BentoRadius.xl) {
            VStack(alignment: .leading, spacing: BentoSpace.s12) {
                HStack(spacing: BentoSpace.s12) {
                    BentoIconCircle(icon, on: tone)
                        .symbolEffect(.bounce, value: bounce)
                    title.bentoText(.title, tone.ink)
                }
                VStack(alignment: .leading, spacing: BentoSpace.s4) { message }
                    .bentoText(.body, tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
    }
}

extension BentoAlertCard where Actions == EmptyView {
    init(tone: BentoTone = .peach, icon: BentoIcon = .warning, bounce: Int = 0,
         @ViewBuilder title: () -> Title, @ViewBuilder message: () -> Message) {
        self.init(tone: tone, icon: icon, bounce: bounce, title: title, message: message) { EmptyView() }
    }
}
