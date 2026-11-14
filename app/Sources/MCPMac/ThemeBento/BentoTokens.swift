import SwiftUI

/// 动效原则：只给用户操作触发的变化加动画（选中、开关、悬停、页面切换）。
/// 每秒/每 5 秒刷新的实时数据（调用数、倒计时、内存）直接替换，不加 numericText 等过渡——
/// 这类过渡在 CPU 上插值并做模糊，持续触发会让空闲 CPU 到 40%+（2026-11-14 实测）。

// Pastel Bento 的设计变量，对应 Figma variables。
// 主题里的颜色、间距、圆角、字号、动效都只从这里取；别的文件不写字面量颜色。

// MARK: 颜色

enum BentoColor {
    enum Bg {
        static let window = Color(bentoHex: 0xFBF9F6)
        static let surface = Color(bentoHex: 0xFFFFFF)
        static let panel = Color(bentoHex: 0xF2EFEA)
        static let sunken = Color(bentoHex: 0xEAE6E0)
        static let inverse = Color(bentoHex: 0x1E1D1B)
    }

    enum Ink {
        static let black = Color(bentoHex: 0x111111)
        static let primary = Color(bentoHex: 0x1D1C1A)
        static let secondary = Color(bentoHex: 0x6E6963)
        static let tertiary = Color(bentoHex: 0xA5A099)
        static let inverse = Color(bentoHex: 0xFFFFFF)
        static let inverseMuted = Color(bentoHex: 0x9C978F)
    }

    enum Status {
        static let green = Color(bentoHex: 0x37B877)
        static let peach = Color(bentoHex: 0xEE9B3F)
        static let rose = Color(bentoHex: 0xE2596D)
        static let idle = Color(bentoHex: 0xC6C1BA)
    }

    enum Log {
        static let error = Color(bentoHex: 0xFF9A93)
        static let warn = Color(bentoHex: 0xF5C875)
    }
}

/// 一组「底色 + 上面的字色」。五个粉彩色调来自 Figma 的 tint/*；
/// 其余几个是用 bg/* 和 ink/* 配出来的中性色调，让卡片、药丸、按钮可以用同一个参数换肤。
struct BentoTone: Hashable, Sendable {
    let fill: Color
    let ink: Color
    /// 次要文字（说明、路径）。粉彩色调上直接用 ink，中性色调上用 ink/secondary。
    let mutedInk: Color
    /// 深色底：悬停时提亮而不是压暗。
    var isDark = false

    static let lavender = BentoTone(tint: 0xD9D2F9, ink: 0x40348F)
    static let mint = BentoTone(tint: 0xC2ECD8, ink: 0x1A5C42)
    static let sky = BentoTone(tint: 0xCDE4F6, ink: 0x1F4E74)
    static let peach = BentoTone(tint: 0xF9DDBD, ink: 0x7C4A12)
    static let rose = BentoTone(tint: 0xF7CDD1, ink: 0x84283A)
    /// 不属于任何服务的调用来源（「试调用」、已删掉的服务）：比空白深一档的暖灰。
    static let stone = BentoTone(tint: 0xD3CBBF, ink: 0x564E44)

    static let surface = BentoTone(fill: BentoColor.Bg.surface, ink: BentoColor.Ink.primary, mutedInk: BentoColor.Ink.secondary)
    static let panel = BentoTone(fill: BentoColor.Bg.panel, ink: BentoColor.Ink.primary, mutedInk: BentoColor.Ink.secondary)
    static let sunken = BentoTone(fill: BentoColor.Bg.sunken, ink: BentoColor.Ink.secondary, mutedInk: BentoColor.Ink.tertiary)
    /// 黑底白字：主按钮、选中的药丸。
    static let ink = BentoTone(fill: BentoColor.Ink.black, ink: BentoColor.Ink.inverse, mutedInk: BentoColor.Ink.inverseMuted, isDark: true)
    /// 深色面板：日志块。
    static let inverse = BentoTone(fill: BentoColor.Bg.inverse, ink: BentoColor.Ink.inverse, mutedInk: BentoColor.Ink.inverseMuted, isDark: true)

    /// 命名服务轮流使用的色调（默认服务固定用 lavender；peach / rose 留给状态）。
    static let serviceCycle: [BentoTone] = [.sky, .mint, .lavender]

    private init(tint: UInt32, ink: UInt32) {
        fill = Color(bentoHex: tint)
        self.ink = Color(bentoHex: ink)
        mutedInk = Color(bentoHex: ink)
    }

    private init(fill: Color, ink: Color, mutedInk: Color, isDark: Bool = false) {
        self.fill = fill
        self.ink = ink
        self.mutedInk = mutedInk
        self.isDark = isDark
    }
}

/// 透明度。叠在色块上的半透明白、悬停时的蒙层等。
enum BentoOpacity {
    /// 粉彩卡片上的白色图标底。
    static let chipOnTint = 0.6
    /// 后台服务没运行时，暂时用不了的入口。
    static let dimmed = 0.4
    static let hoverVeil = 0.05
    static let hoverVeilOnDark = 0.14
    static let hairline = 0.08
    static let shadow = 0.10
    /// 趋势线下面那层面积。
    static let sparkFill = 0.12
}

// MARK: 间距 / 圆角 / 尺寸

enum BentoSpace {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s18: CGFloat = 18
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s36: CGFloat = 36
    static let s40: CGFloat = 40
    static let s48: CGFloat = 48
}

enum BentoRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    // full：直接用 Capsule / Circle
}

/// 组件和版式的固定尺寸（设计稿量出来的）。
enum BentoMetric {
    /// 顶部给红绿灯留的高度；内容延伸到透明标题栏下面。
    static let titleBarInset: CGFloat = 44
    static let windowInset: CGFloat = 12
    /// 侧边栏收窄后的宽度。
    static let railWidth: CGFloat = 64
    /// 侧边栏展开时的宽度。
    static let sidebarWidth: CGFloat = 184
    /// 窗口窄于这个宽度，侧边栏收成窄条。= 最小窗口 980 + (sidebarWidth - railWidth)，
    /// 所以展开时页面内容不会比最小窗口下更窄。
    static let sidebarCollapseBelow: CGFloat = 1100
    static let railButton: CGFloat = 44
    static let listColumnWidth: CGFloat = 296
    static let sidePanelWidth: CGFloat = 324
    static let menuPanelWidth: CGFloat = 380

    static let controlHeight: CGFloat = 40
    static let controlHeightSmall: CGFloat = 30
    static let iconCircle: CGFloat = 36
    static let iconCircleLarge: CGFloat = 48
    static let statusDot: CGFloat = 7
    static let avatar: CGFloat = 26
    static let toggleSize = CGSize(width: 36, height: 22)
    static let checkbox: CGFloat = 18
    static let selectionStroke: CGFloat = 1.5

    static let mcpCardMinWidth: CGFloat = 216
    static let mcpCardHeight: CGFloat = 180
    static let chartHeight: CGFloat = 96
    static let keyColumnWidth: CGFloat = 120
    /// 调用表窄于这个宽度时省掉「客户端」一列。
    static let callTableCompactWidth: CGFloat = 640
    /// 出错页左列（提示卡片）最宽多少，右列的路径才放得下。
    static let alertColumnMaxWidth: CGFloat = 440

    static let iconSize: CGFloat = 15
    static let iconSizeSmall: CGFloat = 11
}

// MARK: 字体

/// Figma 的文字样式。字体用系统字体（SF Pro / 苹方），等宽用系统等宽。
enum BentoTextStyle {
    case display, headline, title, body, bodyStrong, label, mono

    var size: CGFloat {
        switch self {
        case .display: 54
        case .headline: 28
        case .title: 16
        case .body, .bodyStrong: 13
        case .label: 11
        case .mono: 12
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display: 66
        case .headline: 36
        case .title: 24
        case .body, .bodyStrong: 20
        case .label: 16
        case .mono: 19
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display: .light
        case .headline, .body, .mono: .regular
        case .title, .bodyStrong, .label: .medium
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -1.5
        case .headline: -0.5
        // 变量表里 Label 的字距写的是 +1。按 1pt 排明显比设计稿截图松，按 1%（11pt 下约 0.11pt）排才对得上，
        // 所以这里按百分比理解；真实单位待和设计确认。
        case .label: 0.11
        default: 0
        }
    }

    var font: Font {
        .system(size: size, weight: weight, design: self == .mono ? .monospaced : .default)
    }
}

extension View {
    /// 套用一个文字样式（字号、字重、字距、行高）和颜色。
    func bentoText(_ style: BentoTextStyle, _ color: Color = BentoColor.Ink.primary) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineHeight(.exact(points: style.lineHeight))
            .foregroundStyle(color)
    }
}

// MARK: 动效

enum BentoMotion {
    /// 选中态、开关、药丸滑块。
    static let snappy = Animation.snappy(duration: 0.26)
    /// 页面切换、卡片出现。
    static let smooth = Animation.smooth(duration: 0.28)
    /// 悬停、按下。
    static let hover = Animation.snappy(duration: 0.16)
    static let pressedScale: CGFloat = 0.975
    static let hoverLift: CGFloat = -2
}

// MARK: 内部

private extension Color {
    init(bentoHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
