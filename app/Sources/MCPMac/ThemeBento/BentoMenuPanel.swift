import AppKit
import SwiftUI

/// 菜单栏面板（MenuBarExtra 的 .window 样式）：一眼看状态、拨开关、复制服务地址。
struct BentoMenuPanel: View {
    @Environment(AppStore.self) private var store
    @State private var scope: BentoMenuScope = .all
    @State private var expanded = false

    var body: some View {
        // 内容比屏幕高（MCP 很多、列表展开）时改成可滚动；平时按内容高度。
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.never)
        }
        .frame(width: BentoMetric.menuPanelWidth)
        .frame(maxHeight: Self.maxHeight)
        .background(BentoColor.Bg.window)
        .toggleStyle(.bento)
        .environment(\.bentoCoreRunning, store.core?.canManage ?? false)
        // 主窗口由 WindowChrome 固定成浅色；面板是另一个窗口，这里自己固定。
        .environment(\.colorScheme, .light)
    }

    private static var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - BentoSpace.s24
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            BentoMenuHeader()
            if let core = store.core, case .stopped(let reason) = core.state {
                BentoMenuCoreDown(reason: reason)
            } else {
                BentoMenuMCPs(scope: $scope, expanded: $expanded)
                BentoMenuServices()
            }
            BentoMenuFooter()
        }
        .padding(BentoSpace.s16)
    }
}

enum BentoMenuScope: Hashable, CaseIterable {
    case all, attention
}

/// 打开主窗口并切到指定页面。
@MainActor
struct BentoOpenMain {
    let nav: Navigator
    let openWindow: OpenWindowAction

    func callAsFunction(_ change: (Navigator) -> Void = { _ in }) {
        change(nav)
        openWindow(id: "main")
        NSApp.activate()
    }
}
