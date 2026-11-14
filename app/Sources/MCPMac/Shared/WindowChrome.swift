import AppKit
import SwiftUI

/// 按主题调整承载窗口的外观。
///
/// SwiftUI 的 windowStyle 是 Scene 级、启动时定死的；而两套主题要在同一个窗口里运行时切换，
/// 所以这里直接改 NSWindow：Pastel Bento 需要内容延伸到标题栏下、标题栏透明；
/// Liquid Glass 用系统默认的统一工具栏。
struct WindowChrome: NSViewRepresentable {
    var theme: AppTheme

    func makeNSView(context: Context) -> NSView { ChromeView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ChromeView)?.theme = theme
    }

    final class ChromeView: NSView {
        var theme: AppTheme = .glass { didSet { apply() } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let w = window else { return }
            switch theme {
            case .bento:
                w.styleMask.insert(.fullSizeContentView)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovableByWindowBackground = true
                // 设计稿只有浅色
                w.appearance = NSAppearance(named: .aqua)
            case .glass:
                w.titlebarAppearsTransparent = false
                w.titleVisibility = .hidden
                w.isMovableByWindowBackground = false
                w.appearance = nil
            }
        }
    }
}
