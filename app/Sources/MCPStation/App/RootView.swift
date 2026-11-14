import SwiftUI

/// 按主题挂载整套界面。两套主题只共享 store / navigator，视图互不引用。
struct RootView: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .glass

    var body: some View {
        ZStack {
            switch theme {
            case .glass: GlassRoot().transition(.opacity)
            case .bento:
                BentoRoot()
                    // 标题栏由主题用 SwiftUI 声明，不靠事后改 NSWindow：
                    // Glass 的分栏视图会给窗口挂上工具栏，切过来时要明确移除标题、隐藏工具栏背景，
                    // 否则会残留一条不透明标题栏（2026-11-14 运行中切换主题时复现）。
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: theme)
        .background(WindowChrome(theme: theme))
        .frame(minWidth: 980, minHeight: 640)
    }
}

/// 菜单栏面板同样按主题切换。
struct MenuBarPanel: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .glass

    var body: some View {
        switch theme {
        case .glass: GlassMenuPanel()
        case .bento: BentoMenuPanel()
        }
    }
}
