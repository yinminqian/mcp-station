import AppKit

/// 菜单栏常驻应用的生命周期：关掉主窗口不退出（MCP 由后台服务托管，App 只是遥控器），
/// 点 Dock 图标重新打开主窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 由 SwiftUI 侧注入（需要 openWindow 环境值），用于 Dock 图标重新打开主窗口。
    var openMainWindow: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow?() }
        return true
    }
}
