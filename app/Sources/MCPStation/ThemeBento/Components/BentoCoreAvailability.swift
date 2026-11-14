import SwiftUI

extension EnvironmentValues {
    /// 后台服务是否在运行。没运行时，会改状态的控件（开关、勾选、重启）先禁用，
    /// 免得点了以后先变再弹回来。由 `BentoRoot` 写入。
    @Entry var bentoCoreRunning = true
}

/// 标题栏里的提示：后台服务没运行时，除概览外的页面都显示它（概览自己就是出错页）。
struct BentoCoreDownBadge: View {
    var body: some View {
        HStack(spacing: BentoSpace.s8) {
            BentoPillChip("后台服务没有运行，下面是最后一次的状态", tone: .rose, dot: .error)
            BentoRestartCoreButton(tone: .ink, title: "重启", size: .small)
        }
    }
}
