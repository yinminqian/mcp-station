import Sparkle

/// 自动更新（Sparkle 2，和 paster 同一套）：读仓库里的 appcast.xml（Info.plist 的 SUFeedURL），
/// 从 GitHub Release 下载 DMG，用 SUPublicEDKey 验签后安装。每次启动悄悄查一次、之后每两天查一次，
/// 有新版才提示，装不装由用户点。发版见 scripts/release.sh。
@MainActor
enum Updates {
    static let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    /// 用 swift build 直接跑（没有打成 .app、Info.plist 里没有更新源）时不启动。
    static var available: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    static func start() {
        guard available else { return }
        controller.startUpdater()
        controller.updater.checkForUpdatesInBackground()
    }

    static func checkNow() {
        controller.checkForUpdates(nil)
    }
}
