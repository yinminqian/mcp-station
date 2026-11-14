import AppKit

/// 界面语言：中文或 English。第一次打开时跟系统：系统是中文就中文，其他语言一律英文
/// （App 包的默认区域是英文，系统按语言匹配，匹配不上就落到英文）。
/// 在设置里切换后写进这个 App 自己的语言偏好（AppleLanguages），重新打开 App 生效。
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh-Hans", en = "en"
    var id: String { rawValue }

    /// 语言自己的名字，不翻译。
    var name: String { self == .zh ? "中文" : "English" }

    /// 现在界面用的语言。
    static var current: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? .zh : .en
    }

    /// 选过但还没重新打开时，界面仍是旧语言。
    static var chosen: AppLanguage {
        (UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first).map { $0.hasPrefix("zh") ? .zh : .en } ?? current
    }

    static func choose(_ l: AppLanguage) {
        UserDefaults.standard.set([l.rawValue], forKey: "AppleLanguages")
    }

    /// 重新打开 App（换语言用）：等这个进程退出后再打开自己。
    @MainActor
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
