import SwiftUI

/// 外观主题。两套主题是两套完整的界面（布局不同），不是换色。
enum AppTheme: String, CaseIterable, Identifiable {
    case glass, bento
    var id: String { rawValue }

    static let storageKey = "appearance.theme"

    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .bento: "Pastel Bento"
        }
    }

    var subtitle: String {
        switch self {
        case .glass: "原生风格，跟随系统外观"
        case .bento: "柔和卡片风格，浅色"
        }
    }
}
