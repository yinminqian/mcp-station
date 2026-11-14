import SwiftUI

// 随时间变化的文字。计时只发生在这两个小视图里（TimelineView），不依赖 store 推送，
// 所以倒计时每秒跳动时，外层卡片和列表不会重绘。

/// 倒计时：距 `target` 还剩多少秒，每秒更新，数字滚动过渡。
struct BentoCountdown: View {
    let target: Date
    /// 把剩余秒数排成文案，例如 `{ "等待重试 \($0)s" }`。
    var format: (Int) -> String = { "\($0)s" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(target.timeIntervalSince(context.date).rounded(.up)))
            // 倒计时每秒变化，直接替换文字。
            Text(format(remaining))
                .monospacedDigit()
        }
    }
}

/// 已运行时长：「3 小时 12 分」，半分钟刷新一次。
struct BentoUptime: View {
    let since: Date
    var prefix = "已运行 "

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(prefix + Format.uptime(since: since, now: context.date))
        }
    }
}
