import SwiftUI

/// 图标变量：界面里的每个概念对应一个 SF Symbol。要换图标只改这里。
struct BentoIcon: Hashable, Sendable {
    let symbol: String

    // 导航
    static let brand = BentoIcon(symbol: "antenna.radiowaves.left.and.right")
    static let overview = BentoIcon(symbol: "house")
    static let mcps = BentoIcon(symbol: "powerplug")
    static let services = BentoIcon(symbol: "square.3.layers.3d")
    static let calls = BentoIcon(symbol: "waveform.path.ecg")
    static let settings = BentoIcon(symbol: "slider.horizontal.3")
    static let core = BentoIcon(symbol: "server.rack")

    // 分组
    static let groupAll = BentoIcon(symbol: "square.grid.2x2")
    static let groupDev = BentoIcon(symbol: "chevron.left.forwardslash.chevron.right")
    static let groupData = BentoIcon(symbol: "cylinder.split.1x2")
    static let groupDesign = BentoIcon(symbol: "pencil")
    static let groupSystem = BentoIcon(symbol: "cpu")

    // MCP 的类型和用途
    static let http = BentoIcon(symbol: "globe")
    static let package = BentoIcon(symbol: "shippingbox")
    static let terminal = BentoIcon(symbol: "apple.terminal")
    static let browser = BentoIcon(symbol: "display")
    static let phone = BentoIcon(symbol: "iphone")
    static let database = BentoIcon(symbol: "cylinder.split.1x2")
    static let image = BentoIcon(symbol: "photo")
    static let document = BentoIcon(symbol: "doc.text")
    static let cloud = BentoIcon(symbol: "icloud")
    static let eye = BentoIcon(symbol: "eye")
    static let note = BentoIcon(symbol: "book.closed")

    // 操作
    static let restart = BentoIcon(symbol: "arrow.clockwise")
    static let add = BentoIcon(symbol: "plus")
    static let importFile = BentoIcon(symbol: "square.and.arrow.down")
    static let edit = BentoIcon(symbol: "pencil")
    static let delete = BentoIcon(symbol: "trash")
    static let copy = BentoIcon(symbol: "doc.on.doc")
    static let copied = BentoIcon(symbol: "checkmark")
    static let search = BentoIcon(symbol: "magnifyingglass")
    static let clear = BentoIcon(symbol: "xmark.circle.fill")
    static let folder = BentoIcon(symbol: "folder")
    static let reveal = BentoIcon(symbol: "eye")
    static let conceal = BentoIcon(symbol: "eye.slash")
    static let openWindow = BentoIcon(symbol: "macwindow")
    static let quit = BentoIcon(symbol: "power")

    // 状态和指示
    static let warning = BentoIcon(symbol: "exclamationmark.triangle")
    static let clock = BentoIcon(symbol: "clock")
    static let check = BentoIcon(symbol: "checkmark")
    static let chevronRight = BentoIcon(symbol: "chevron.right")
    static let chevronDown = BentoIcon(symbol: "chevron.down")
    static let info = BentoIcon(symbol: "info.circle")
    static let tools = BentoIcon(symbol: "wrench.and.screwdriver")

    var image: Image { Image(systemName: symbol) }
}

extension Navigator.Route {
    var bentoIcon: BentoIcon {
        switch self {
        case .overview: .overview
        case .mcps: .mcps
        case .services: .services
        case .calls: .calls
        case .settings: .settings
        }
    }
}
