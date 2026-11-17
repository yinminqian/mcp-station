using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.Text;

namespace MCPStation.Theme;

// Pastel Bento 的设计变量。数值和 Mac 端 ThemeBento/BentoTokens.swift 一一对应（Figma variables）；
// 主题里的颜色、间距、圆角、字号都只从这里取，别的文件不写字面量。

public static class BentoColor
{
    public static class Bg
    {
        public static readonly Color Window = Hex(0xFBF9F6);
        public static readonly Color Surface = Hex(0xFFFFFF);
        public static readonly Color Panel = Hex(0xF2EFEA);
        public static readonly Color Sunken = Hex(0xEAE6E0);
        public static readonly Color Inverse = Hex(0x1E1D1B);
    }

    public static class Ink
    {
        public static readonly Color Black = Hex(0x111111);
        public static readonly Color Primary = Hex(0x1D1C1A);
        // Mac 是 0x6E6963。DirectWrite 灰度抗锯齿的笔画比 Core Text 细、边缘更淡，同一个色值在 Windows 上显得更浅，
        // 所以压暗一档（白底对比度 5.4 → 6.8），色相不变。
        public static readonly Color Secondary = Hex(0x5F5A54);
        // Mac 是 0xA5A099（白底 2.6:1）。11px 的表头、占位符在 Windows 上几乎看不清，压到 3.5:1 左右。
        public static readonly Color Tertiary = Hex(0x8E8982);
        public static readonly Color Inverse = Hex(0xFFFFFF);
        // Mac 是 0x9C978F。深底上的细字同样偏淡，这里反过来提亮一档。
        public static readonly Color InverseMuted = Hex(0xAAA59D);
    }

    public static class Status
    {
        public static readonly Color Green = Hex(0x37B877);
        public static readonly Color Peach = Hex(0xEE9B3F);
        public static readonly Color Rose = Hex(0xE2596D);
        public static readonly Color Idle = Hex(0xC6C1BA);
    }

    public static Color Hex(uint hex, double opacity = 1) =>
        Color.FromArgb((byte)Math.Round(opacity * 255), (byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));

    public static Color WithOpacity(this Color c, double opacity) => Color.FromArgb((byte)Math.Round(opacity * 255), c.R, c.G, c.B);

    public static SolidColorBrush Brush(this Color c) => new(c);
}

/// 一组「底色 + 上面的字色」。五个粉彩色调来自 Figma 的 tint/*，其余是中性色调。
public sealed record BentoTone(Color Fill, Color Ink, Color MutedInk, bool IsDark = false)
{
    private static BentoTone Tint(uint tint, uint ink) => new(BentoColor.Hex(tint), BentoColor.Hex(ink), BentoColor.Hex(ink));

    public static readonly BentoTone Lavender = Tint(0xD9D2F9, 0x40348F);
    public static readonly BentoTone Mint = Tint(0xC2ECD8, 0x1A5C42);
    public static readonly BentoTone Sky = Tint(0xCDE4F6, 0x1F4E74);
    public static readonly BentoTone Peach = Tint(0xF9DDBD, 0x7C4A12);
    public static readonly BentoTone Rose = Tint(0xF7CDD1, 0x84283A);
    /// 不属于任何服务的调用来源（「试调用」、已删掉的服务）。
    public static readonly BentoTone Stone = Tint(0xD3CBBF, 0x564E44);

    public static readonly BentoTone Surface = new(BentoColor.Bg.Surface, BentoColor.Ink.Primary, BentoColor.Ink.Secondary);
    public static readonly BentoTone Panel = new(BentoColor.Bg.Panel, BentoColor.Ink.Primary, BentoColor.Ink.Secondary);
    public static readonly BentoTone Sunken = new(BentoColor.Bg.Sunken, BentoColor.Ink.Secondary, BentoColor.Ink.Tertiary);
    /// 黑底白字：主按钮、选中的药丸。
    public static readonly BentoTone InkTone = new(BentoColor.Ink.Black, BentoColor.Ink.Inverse, BentoColor.Ink.InverseMuted, true);
    /// 深色面板：日志块。
    public static readonly BentoTone Inverse = new(BentoColor.Bg.Inverse, BentoColor.Ink.Inverse, BentoColor.Ink.InverseMuted, true);

    /// 命名服务轮流使用的色调（默认服务固定 lavender；peach / rose 留给状态）。
    public static readonly BentoTone[] ServiceCycle = [Sky, Mint, Lavender];

    /// 悬停时盖在上面的一层：浅色压暗，深色提亮。
    public Color HoverVeil => IsDark ? Colors.White.WithOpacity(0.14) : BentoColor.Ink.Black.WithOpacity(0.05);
}

public static class BentoSpace
{
    public const double S2 = 2, S4 = 4, S6 = 6, S8 = 8, S10 = 10, S12 = 12, S14 = 14, S16 = 16, S18 = 18, S20 = 20,
        S24 = 24, S32 = 32, S36 = 36, S40 = 40, S48 = 48;
}

public static class BentoRadius
{
    public const double Xs = 6, Sm = 10, Md = 16, Lg = 20, Xl = 28;
}

/// 组件和版式的固定尺寸（设计稿量出来的）。
public static class BentoMetric
{
    /// 顶部标题栏的高度；内容延伸到标题栏下面。Mac 上是给红绿灯留的 44，这里给系统标题栏按钮留同样高度。
    public const double TitleBarInset = 44;
    public const double WindowInset = 12;
    public const double RailWidth = 64;
    public const double SidebarWidth = 184;
    public const double SidebarCollapseBelow = 1100;
    public const double RailButton = 44;
    public const double SidePanelWidth = 324;
    public const double IconCircle = 36;
    public const double IconCircleLarge = 48;
    public const double StatusDot = 7;
    public const double ChartHeight = 96;
    public const double CallTableCompactWidth = 640;
    public const double IconSize = 15;
    public const double IconSizeSmall = 11;
    public const double SelectionStroke = 1.5;
}

/// Figma 的文字样式。字体：Segoe UI Variable（中文回落到 Noto Sans SC，没有再到微软雅黑），等宽用 Cascadia Mono。
/// 字号、行高、字距和 Mac 一致；字重比 Mac 的 token 各重半档到一档，原因见 Weight()。
public enum BentoTextStyle { Display, Headline, Title, Body, BodyStrong, Label, Mono }

public static class BentoText
{
    // 中文先用 Noto Sans SC（Win11 新版自带的可变字体）：微软雅黑只有 Light/Regular/Bold，
    // Medium 会落回 Regular，中文的 Title/BodyStrong/Label 和正文就分不出轻重；Noto 有真正的 500/600，
    // 字形也更接近苹方。系统里没有 Noto 时照旧回落到微软雅黑。
    // 全部用 Text 光学尺寸：Display 那一档在 28/54px 下笔画更细，会更显淡。
    public static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI, Noto Sans SC, Microsoft YaHei UI");
    // 11px 的 Label 用 Small 光学尺寸：笔画更粗、字怀更开，小字更清楚（SF 在小字号也会自动这样调整）。
    public static readonly FontFamily LabelFont = new("Segoe UI Variable Small, Segoe UI Variable Text, Segoe UI, Noto Sans SC, Microsoft YaHei UI");
    public static readonly FontFamily MonoFont = new("Cascadia Mono, Consolas, Noto Sans SC, Microsoft YaHei UI");
    public static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static double Size(BentoTextStyle s) => s switch
    {
        BentoTextStyle.Display => 54,
        BentoTextStyle.Headline => 28,
        BentoTextStyle.Title => 16,
        BentoTextStyle.Body or BentoTextStyle.BodyStrong => 13,
        BentoTextStyle.Label => 11,
        _ => 12,
    };

    public static double LineHeight(BentoTextStyle s) => s switch
    {
        BentoTextStyle.Display => 66,
        BentoTextStyle.Headline => 36,
        BentoTextStyle.Title => 24,
        BentoTextStyle.Body or BentoTextStyle.BodyStrong => 20,
        BentoTextStyle.Label => 16,
        _ => 19,
    };

    /// 字重比 Mac 的 token 重：同一个名义字重，Segoe UI Variable 的笔画比 SF Pro 细，
    /// DirectWrite 的灰度抗锯齿又不像 Core Text 那样把笔画加粗，照抄数值会整体发灰。
    /// 这里按「看起来和 Mac 一样重」取值（可变字体，中间值有效）。
    public static FontWeight Weight(BentoTextStyle s) => s switch
    {
        BentoTextStyle.Display => W(350),      // Mac: Light 300
        BentoTextStyle.Headline => W(500),     // Mac: Regular 400
        BentoTextStyle.Title => W(600),        // Mac: Medium 500
        BentoTextStyle.BodyStrong => W(600),   // Mac: Medium 500
        BentoTextStyle.Label => W(500),        // Mac: Medium 500（不变，改用 Small 光学尺寸补足）
        BentoTextStyle.Mono => W(400),         // Mac: Regular 400（Cascadia Mono 本身够重，不变）
        _ => W(450),                           // Body。Mac: Regular 400
    };

    private static FontWeight W(ushort weight) => new() { Weight = weight };

    /// 字距（XAML 里单位是 1/1000 em）：Display -1.5pt、Headline -0.5pt、Label 1%。
    public static int Spacing(BentoTextStyle s) => s switch
    {
        BentoTextStyle.Display => -28,
        BentoTextStyle.Headline => -18,
        BentoTextStyle.Label => 10,
        _ => 0,
    };

    public static TextBlock Make(string text, BentoTextStyle style, Color? color = null)
    {
        var tb = new TextBlock { Text = text };
        return tb.Style(style, color ?? BentoColor.Ink.Primary);
    }

    public static TextBlock Style(this TextBlock tb, BentoTextStyle style, Color color)
    {
        tb.FontFamily = style switch
        {
            BentoTextStyle.Mono => MonoFont,
            BentoTextStyle.Label => LabelFont,
            _ => UiFont,
        };
        tb.FontSize = Size(style);
        tb.FontWeight = Weight(style);
        tb.CharacterSpacing = Spacing(style);
        tb.LineHeight = LineHeight(style);
        tb.LineStackingStrategy = LineStackingStrategy.BlockLineHeight;
        tb.Foreground = color.Brush();
        tb.TextTrimming = TextTrimming.CharacterEllipsis;
        tb.TextWrapping = TextWrapping.NoWrap;
        tb.VerticalAlignment = VerticalAlignment.Center;
        return tb;
    }
}

/// 图标变量：界面里的每个概念对应 Segoe Fluent Icons 的一个字形（Mac 端是 SF Symbol）。要换图标只改这里。
public static class BentoIcon
{
    public const string Brand = "";
    public const string Overview = "";
    public const string Mcps = "";
    public const string Services = "";
    public const string Calls = "";
    public const string Settings = "";
    public const string Core = "";
    public const string Http = "";
    public const string Package = "";
    public const string Terminal = "";
    public const string Browser = "";
    public const string Phone = "";
    public const string Database = "";
    public const string Document = "";
    public const string Eye = "";
    public const string Restart = "";
    public const string Add = "";
    public const string Edit = "";
    public const string Delete = "";
    public const string Copy = "";
    public const string Check = "";
    public const string Search = "";
    public const string Folder = "";
    public const string Warning = "";
    public const string Clock = "";
    public const string ChevronRight = "";
    public const string ChevronDown = "";
    public const string Info = "";
    public const string Tools = "";

    public static FontIcon Make(string glyph, double size, Color color) => new()
    {
        Glyph = glyph,
        FontFamily = BentoText.IconFont,
        FontSize = size,
        Foreground = color.Brush(),
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        IsTextScaleFactorEnabled = false,
    };
}

/// 界面上的状态语义。颜色只有这几种，MCP 状态和后台服务状态都先映射到它。
public enum BentoStatus { Ok, Warn, Error, Idle, Busy }

public static class BentoStatusExt
{
    public static Color Color(this BentoStatus s) => s switch
    {
        BentoStatus.Ok => BentoColor.Status.Green,
        BentoStatus.Warn or BentoStatus.Busy => BentoColor.Status.Peach,
        BentoStatus.Error => BentoColor.Status.Rose,
        _ => BentoColor.Status.Idle,
    };

    public static BentoTone Tone(this BentoStatus s) => s switch
    {
        BentoStatus.Ok => BentoTone.Mint,
        BentoStatus.Warn or BentoStatus.Busy => BentoTone.Peach,
        BentoStatus.Error => BentoTone.Rose,
        _ => BentoTone.Sunken,
    };

    public static BentoStatus Of(Core.McpStateKind s) => s switch
    {
        Core.McpStateKind.Ready => BentoStatus.Ok,
        Core.McpStateKind.Starting => BentoStatus.Busy,
        Core.McpStateKind.Backoff => BentoStatus.Warn,
        Core.McpStateKind.ConfigError => BentoStatus.Error,
        _ => BentoStatus.Idle,
    };

    public static BentoStatus Of(Core.CoreStatus? c) => c?.State switch
    {
        Core.CoreStateKind.Running => BentoStatus.Ok,
        Core.CoreStateKind.Restarting => BentoStatus.Busy,
        Core.CoreStateKind.Stopped => BentoStatus.Error,
        _ => BentoStatus.Idle,
    };
}
