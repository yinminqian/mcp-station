import AppKit
import SwiftUI

// 面板里其余几段：服务、后台服务没运行时的提示、底部菜单项。

/// 服务列表，每行可以复制地址。
struct BentoMenuServices: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let services = store.services
        let tones = BentoServiceTones(services)
        BentoSectionLabel("服务")
        ForEach(services) { service in
            BentoServiceRow(service: service, tone: tones[service.name]) {
                if let port = store.core?.port {
                    BentoCopyButton(text: Format.serviceURL(service, port: port), key: "menu-service:\(service.name)",
                                    label: "复制 \(service.name) 的地址")
                }
            }
        }
    }
}

/// 后台服务没运行时，代替 MCP 和服务两段。
struct BentoMenuCoreDown: View {
    let reason: CoreDownReason

    @Environment(Navigator.self) private var nav
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BentoAlertCard(tone: .rose) {
            Text(reason.title)
        } message: {
            Text(reason.detail)
        } actions: {
            HStack(spacing: BentoSpace.s8) {
                BentoRestartCoreButton(tone: .ink, title: "立即重启", size: .small)
                Button("查看原因…") {
                    BentoOpenMain(nav: nav, openWindow: openWindow)() { $0.route = .overview }
                }
                .buttonStyle(.bento(.surface, size: .small))
            }
        }
    }
}

/// 底部：打开主窗口、登录时打开、退出。
struct BentoMenuFooter: View {
    @Environment(Navigator.self) private var nav
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BentoCard(padding: BentoSpace.s8) {
            VStack(spacing: 0) {
                BentoMenuActionRow(title: "打开主窗口…", shortcut: "⌘O") {
                    BentoOpenMain(nav: nav, openWindow: openWindow)()
                }
                .keyboardShortcut("o")
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("登录时打开").bentoText(.bodyStrong, BentoColor.Ink.secondary)
                        Text(BentoCopy.loginItemLater).bentoText(.label, BentoColor.Ink.tertiary)
                    }
                    Spacer()
                    // 还没接登录项，先占位并禁用，和 Liquid Glass 主题一致。
                    Toggle(isOn: .constant(false)) { Text("登录时打开") }
                        .disabled(true)
                }
                .padding(.horizontal, BentoSpace.s12)
                .frame(height: BentoSpace.s40)
                BentoMenuActionRow(title: "退出 MCP Station", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        Text("退出 App 不影响 MCP —— 后台服务由 launchd 常驻。")
            .bentoText(.label, BentoColor.Ink.tertiary)
            .padding(.horizontal, BentoSpace.s4)
    }
}

/// 菜单项样式的一行：左边文字，右边快捷键，悬停高亮。
private struct BentoMenuActionRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).bentoText(.bodyStrong)
                Spacer()
                Text(shortcut).bentoText(.body, BentoColor.Ink.tertiary)
            }
            .padding(.horizontal, BentoSpace.s12)
            .frame(height: BentoSpace.s36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bentoRowHover()
    }
}
