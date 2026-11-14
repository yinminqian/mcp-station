import SwiftUI

extension CoreStatus? {
    /// 后台服务状态的一句话。
    var bentoHeadline: String {
        switch self?.state {
        case .running: "后台服务运行中"
        case .notInstalled: "网关还没接入"
        case .restarting: "后台服务重启中…"
        case .stopped: "后台服务没有运行"
        case nil: "正在连接后台服务…"
        }
    }
}

/// 后台服务状态下面的小字：「pid 4242 · 已运行 3 小时 12 分」。时长自己计时刷新。
struct BentoCoreDetailLine: View {
    let core: CoreStatus?
    /// 地方窄（菜单栏面板）时不带 pid。
    var showsPID = true

    var body: some View {
        switch core?.state {
        case let .running(pid, since):
            BentoUptime(since: since, prefix: showsPID ? "pid \(pid) · 已运行 " : "已运行 ")
        case .notInstalled:
            Text("配置和检测可用，客户端还连不上")
        case .restarting:
            Text("正在重新启动，马上回来")
        case .stopped(let reason):
            Text(reason.title)
        case nil:
            Text("等待状态…")
        }
    }
}

/// 「重启后台服务」按钮。进行中时图标旋转并禁用，防止重复点。
struct BentoRestartCoreButton: View {
    enum Style { case icon, labeled }
    var style: Style = .labeled
    var tone: BentoTone = .surface
    /// 不传就按状态：网关没接入时叫「重新检测」。
    var title: String?
    var size: BentoButtonStyle.Size = .regular

    @Environment(AppStore.self) private var store

    var body: some View {
        let busy = store.isBusy("core-restart") || store.core?.state == .restarting
        let label = title ?? store.core?.restartTitle ?? "重新检测"
        let button = Button {
            store.restartCore()
        } label: {
            Label {
                Text(busy ? "正在处理…" : label)
            } icon: {
                BentoIcon.restart.image
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: busy)
            }
        }
        .disabled(busy)
        Group {
            switch style {
            case .icon: button.buttonStyle(BentoIconButtonStyle(tone: tone))
            case .labeled: button.buttonStyle(.bento(tone, size: size))
            }
        }
        .accessibilityLabel(label)
        .help(label)
    }
}
