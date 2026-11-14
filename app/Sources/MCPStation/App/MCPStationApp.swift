import SwiftUI

@main
struct MCPStationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @State private var nav = Navigator()
    @State private var copy = CopyFeedback()
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .glass

    init() {
        ConfigStore.migrateFromOldName()
        // 配置读写 config.json、MCP 在 App 里真实检测；网关做好后换成 HTTP 版 CoreClient，其余不动。
        _store = State(initialValue: AppStore(client: LocalCore()))
    }

    var body: some Scene {
        Window("MCP Station", id: "main") {
            RootView()
                .environment(store)
                .environment(nav)
                .environment(copy)
                .task {
                    store.start()
                    Snapshotter.applyStartRoute(nav: nav)
                    Snapshotter.runSwitchBenchIfRequested(nav: nav)
                    Snapshotter.runIfRequested(store: store, nav: nav, copy: copy)
                    Snapshotter.runTryCallIfRequested(store: store)
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(store: store, nav: nav) }

        MenuBarExtra {
            MenuBarPanel()
                .environment(store)
                .environment(nav)
                .environment(copy)
                .task { store.start() }
        } label: {
            MenuBarLabel(store: store, appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏状态图标：正常 / 有 MCP 需要关注 / 后台服务没在运行。
struct MenuBarLabel: View {
    let store: AppStore
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let symbol: String = {
            guard let core = store.core, core.canManage else { return "exclamationmark.octagon" }
            return store.attention.isEmpty ? "puzzlepiece.extension" : "exclamationmark.triangle"
        }()
        Image(systemName: symbol)
            .accessibilityLabel("MCP Station")
            // 菜单栏图标常驻，借它把 openWindow 交给 AppDelegate（Dock 图标重新打开主窗口用）
            .task {
                appDelegate.openMainWindow = { [openWindow] in
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Snapshotter.runCloseTestIfRequested()
            }
    }
}

struct AppCommands: Commands {
    let store: AppStore
    let nav: Navigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("添加 MCP…") {
                nav.route = .mcps
                nav.request = .addMCP
                openWindow(id: "main")
            }
            .keyboardShortcut("n")
            Button("新建服务…") {
                nav.route = .services
                nav.request = .createService
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("导入配置…") { ConfigTransfer.importFromFile(store: store) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("导出配置…") { ConfigTransfer.exportToFile(store: store) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("在访达中显示配置文件") { ConfigTransfer.revealConfigFile() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                nav.route = .settings
                openWindow(id: "main")
            }
            .keyboardShortcut(",")
        }
        CommandMenu("前往") {
            ForEach(Array(Navigator.Route.allCases.enumerated()), id: \.element) { i, r in
                Button(r.title) { nav.route = r; openWindow(id: "main") }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
    }
}
