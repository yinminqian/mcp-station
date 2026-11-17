using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace MCPStation.Theme;

// Bento 的基础组件。对应 Mac 端 ThemeBento/Components/ 下的同名组件。
// 动效原则同 Mac 端：只给用户操作触发的变化加动画（悬停、按下、选中、开关），实时数据直接替换。

public static class Bento
{
    /// 卡片：一块圆角色块。粉彩卡片、白卡片、深色日志块都是它，只是色调不同。
    public static Border Card(UIElement content, BentoTone? tone = null, double radius = BentoRadius.Lg, double padding = BentoSpace.S20)
    {
        var t = tone ?? BentoTone.Surface;
        var card = new Border
        {
            Background = t.Fill.Brush(),
            CornerRadius = new CornerRadius(radius),
            Padding = new Thickness(padding),
            Child = content,
        };
        // 白卡片描一圈很淡的发丝边（黑 7%）：Windows 上白卡片贴在 #FBF9F6 底上边界几乎看不出来，
        // Mac 那边靠更强的文字对比撑住了，这里补一条边（2026-11-17 Fable 配色评审）
        if (t == BentoTone.Surface)
        {
            card.BorderBrush = BentoColor.Ink.Black.WithOpacity(0.07).Brush();
            card.BorderThickness = new Thickness(1);
        }
        return card;
    }

    /// 详情区的大面板（右侧那块暖灰底）。
    public static Border Panel(UIElement content) => new()
    {
        Background = BentoColor.Bg.Panel.Brush(),
        CornerRadius = new CornerRadius(BentoRadius.Xl),
        Child = content,
    };

    /// 小药丸：计数、状态、标签（「24 工具」「1 个等待重试」）。
    public static Border Pill(string text, BentoTone? tone = null, BentoStatus? dot = null, string? icon = null)
    {
        var t = tone ?? BentoTone.Surface;
        var row = HStack(BentoSpace.S4);
        if (dot is { } d) row.Children.Add(StatusDot(d));
        if (icon != null) row.Children.Add(BentoIcon.Make(icon, BentoMetric.IconSizeSmall, t.Ink));
        var label = BentoText.Make(text, BentoTextStyle.Label, t.Ink);
        CenterGlyphs(label);
        row.Children.Add(label);
        return new Border
        {
            Background = t.Fill.Brush(),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(BentoSpace.S10, 0, BentoSpace.S10, 0),
            Height = BentoSpace.S24,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
            Child = row,
        };
    }

    /// 在固定高度的胶囊、圆里放字时用：去掉固定行高，按字形的实际上下边界居中，
    /// 否则 Segoe UI / 微软雅黑的行框上下留白不对称，字看起来偏下（2026-11-17 用户反馈"没对齐"）。
    public static TextBlock CenterGlyphs(TextBlock t)
    {
        t.LineHeight = 0;
        t.LineStackingStrategy = LineStackingStrategy.MaxHeight;
        t.TextLineBounds = TextLineBounds.Tight;
        t.VerticalAlignment = VerticalAlignment.Center;
        return t;
    }

    /// 状态圆点。进行中（busy）时缓慢闪动。
    public static Ellipse StatusDot(BentoStatus status, double size = BentoMetric.StatusDot)
    {
        var e = new Ellipse { Width = size, Height = size, Fill = status.Color().Brush(), VerticalAlignment = VerticalAlignment.Center };
        if (status == BentoStatus.Busy)
        {
            var anim = new DoubleAnimation { From = 1, To = 0.3, Duration = TimeSpan.FromMilliseconds(700), AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
            var sb = new Storyboard();
            Storyboard.SetTarget(anim, e);
            Storyboard.SetTargetProperty(anim, "Opacity");
            sb.Children.Add(anim);
            e.Loaded += (_, _) => sb.Begin();
            e.Unloaded += (_, _) => sb.Stop();
        }
        return e;
    }

    /// 圆形底上的一个图标。
    public static Border IconCircle(string glyph, double size = BentoMetric.IconCircle, Color? fill = null, Color? ink = null) => new()
    {
        Width = size,
        Height = size,
        CornerRadius = new CornerRadius(size / 2),
        Background = (fill ?? BentoColor.Bg.Surface).Brush(),
        Child = BentoIcon.Make(glyph, Math.Round(size * 0.42), ink ?? BentoColor.Ink.Black),
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// 粉彩卡片上的图标：半透明白底，图标用卡片的字色。
    public static Border IconCircleOn(string glyph, BentoTone tone, double size = BentoMetric.IconCircle) =>
        IconCircle(glyph, size, BentoColor.Bg.Surface.WithOpacity(0.6), tone.Ink);

    public static StackPanel HStack(double spacing = 0, params UIElement[] children)
    {
        var s = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var c in children) s.Children.Add(c);
        return s;
    }

    public static StackPanel VStack(double spacing = 0, params UIElement[] children)
    {
        var s = new StackPanel { Orientation = Orientation.Vertical, Spacing = spacing };
        foreach (var c in children) s.Children.Add(c);
        return s;
    }

    /// 一行三段：左边、弹性中间、右边（SwiftUI 里 HStack + Spacer 的写法）。
    public static Grid Row(double spacing, UIElement? leading, UIElement? middle, UIElement? trailing)
    {
        var g = new Grid { ColumnSpacing = spacing };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        void Put(UIElement? e, int col) { if (e == null) return; Grid.SetColumn((FrameworkElement)e, col); g.Children.Add(e); }
        Put(leading, 0); Put(middle, 1); Put(trailing, 2);
        return g;
    }

    /// 带图标的胶囊按钮（Mac 端 `.bento(tone, size:)`）。
    public static Pressable Button(string title, string? icon, BentoTone tone, Action onClick, bool small = false)
    {
        var row = HStack(BentoSpace.S6);
        if (icon != null) row.Children.Add(BentoIcon.Make(icon, BentoMetric.IconSizeSmall + 1, tone.Ink));
        row.Children.Add(CenterGlyphs(BentoText.Make(title, small ? BentoTextStyle.Label : BentoTextStyle.BodyStrong, tone.Ink)));
        var b = new Pressable(PressableKind.Fill, tone, small ? 15 : 20)
        {
            Height = small ? 30 : 40,
            Padding = new Thickness(small ? BentoSpace.S12 : BentoSpace.S16, 0, small ? BentoSpace.S12 : BentoSpace.S16, 0),
            InnerContent = row,
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, title);
        b.Click += (_, _) => onClick();
        return b;
    }

    /// 只有图标的圆按钮（Mac 端 BentoIconButton）。
    public static Pressable IconButton(string glyph, string label, Action onClick, BentoTone? tone = null, double size = BentoMetric.RailButton)
    {
        var t = tone ?? BentoTone.Surface;
        var b = new Pressable(PressableKind.Fill, t, size / 2)
        {
            Width = size,
            Height = size,
            InnerContent = BentoIcon.Make(glyph, Math.Round(size * 0.36), t.Ink),
        };
        ToolTipService.SetToolTip(b, label);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, label);
        b.Click += (_, _) => onClick();
        return b;
    }
}

public enum PressableKind
{
    /// 自带底色的按钮：悬停盖一层蒙层，按下微缩。
    Fill,
    /// 整张卡片可点：悬停时整张卡片稍微压暗一点。不上浮、不加投影、不缩放，位置和大小都不变（2026-11-17 用户要求）。
    Card,
    /// 列表行：悬停铺一层浅底。
    Row,
    /// 没有任何反馈（只要能点）。
    Plain,
}

/// 可点的区域。外观全由 Bento 自己画：系统 Button 的模板换成只有内容（App.xaml 里的 BentoBareButton）。
/// 对应 Mac 端 BentoPressable / BentoCardButtonStyle / bentoRowHover。
public class Pressable : Button
{
    /// 卡片悬停时盖在上面那层的颜色：黑 4%，粉彩和白卡片上都只是"稍微深一点"。
    private static readonly Color CardHoverVeil = BentoColor.Ink.Black.WithOpacity(0.04);

    private readonly PressableKind _kind;
    private readonly Border _fill = new();
    private readonly Border _veil = new() { Opacity = 0, IsHitTestVisible = false };
    private readonly ContentPresenter _presenter = new();
    private readonly Grid _root = new();
    private bool _hovering;

    public Pressable(PressableKind kind, BentoTone? tone = null, double radius = BentoRadius.Sm)
    {
        _kind = kind;
        Style = (Style)Application.Current.Resources["BentoBareButton"];
        var t = tone ?? BentoTone.Panel;
        var corner = new CornerRadius(radius);
        _fill.CornerRadius = corner;
        // 键盘焦点框跟着按钮的圆角走
        CornerRadius = corner;
        _fill.Background = kind == PressableKind.Fill ? t.Fill.Brush() : null;
        _fill.BackgroundTransition = new BrushTransition { Duration = TimeSpan.FromMilliseconds(160) };
        _veil.CornerRadius = corner;
        _veil.Background = (kind switch
        {
            PressableKind.Row => BentoColor.Bg.Panel,
            PressableKind.Card => CardHoverVeil,
            _ => t.HoverVeil,
        }).Brush();
        _veil.OpacityTransition = new ScalarTransition { Duration = TimeSpan.FromMilliseconds(160) };
        _root.Children.Add(_fill);
        // 卡片的底色画在内容里，蒙层要盖在内容上面；其他的蒙层在底色和内容之间
        if (kind == PressableKind.Card)
        {
            _root.Children.Add(_presenter);
            _root.Children.Add(_veil);
        }
        else
        {
            _root.Children.Add(_veil);
            _root.Children.Add(_presenter);
        }
        Content = _root;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        // 系统 Button 默认左对齐、按内容收缩；行和卡片要铺满一行，带底色的按钮才按内容宽
        HorizontalAlignment = kind is PressableKind.Row or PressableKind.Card ? HorizontalAlignment.Stretch : HorizontalAlignment.Left;
        ScaleTransition = new Vector3Transition { Duration = TimeSpan.FromMilliseconds(160) };
        SizeChanged += (_, e) => CenterPoint = new Vector3((float)e.NewSize.Width / 2, (float)e.NewSize.Height / 2, 0);
        IsEnabledChanged += (_, _) => Opacity = IsEnabled ? 1 : 0.4;
        UseSystemFocusVisuals = true;
    }

    /// 按钮里的内容（放在底色和蒙层上面）。内边距用 Padding。
    public UIElement? InnerContent
    {
        get => _presenter.Content as UIElement;
        set => _presenter.Content = value;
    }

    public new Thickness Padding
    {
        get => _presenter.Padding;
        set => _presenter.Padding = value;
    }

    /// 选中时铺的底（侧边栏行）。null 表示没选中。
    public Color? SelectedFill
    {
        set
        {
            _fill.Background = value is { } c ? c.Brush() : _kind == PressableKind.Fill ? _fill.Background : null;
            UpdateVisual(false);
        }
    }

    private bool IsSelectedRow => _kind == PressableKind.Row && _fill.Background != null;

    protected override void OnPointerEntered(PointerRoutedEventArgs e)
    {
        base.OnPointerEntered(e);
        _hovering = true;
        UpdateVisual(false);
    }

    protected override void OnPointerExited(PointerRoutedEventArgs e)
    {
        base.OnPointerExited(e);
        _hovering = false;
        UpdateVisual(false);
    }

    protected override void OnPointerCanceled(PointerRoutedEventArgs e)
    {
        base.OnPointerCanceled(e);
        _hovering = false;
        UpdateVisual(false);
    }

    protected override void OnPointerCaptureLost(PointerRoutedEventArgs e)
    {
        base.OnPointerCaptureLost(e);
        UpdateVisual(false);
    }

    protected override void OnPointerPressed(PointerRoutedEventArgs e)
    {
        base.OnPointerPressed(e);
        UpdateVisual(true);
    }

    protected override void OnPointerReleased(PointerRoutedEventArgs e)
    {
        base.OnPointerReleased(e);
        UpdateVisual(false);
    }

    private void UpdateVisual(bool pressed)
    {
        if (_kind == PressableKind.Plain) return;
        var hover = _hovering && IsEnabled;
        _veil.Opacity = hover && !IsSelectedRow ? 1 : 0;
        // 只有带底色的小按钮按下时微缩；卡片和宽行不动
        var s = pressed && _kind == PressableKind.Fill ? 0.975f : 1f;
        Scale = new Vector3(s, s, 1);
    }
}

/// Bento 的开关：36×22 的胶囊，开是黑底，关是灰底。对应 Mac 端 BentoToggleStyle。
public sealed class BentoSwitch : Pressable
{
    private readonly Border _track;
    private readonly Ellipse _knob;
    private bool _isOn;

    public event Action<bool>? Toggled;

    public BentoSwitch(bool isOn) : base(PressableKind.Plain)
    {
        _knob = new Ellipse { Width = 18, Height = 18, Fill = BentoColor.Bg.Surface.Brush(), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(2) };
        _track = new Border { Width = 36, Height = 22, CornerRadius = new CornerRadius(11), Child = _knob };
        InnerContent = _track;
        Width = 36;
        Height = 22;
        VerticalAlignment = VerticalAlignment.Center;
        // 先按初始值画好再挂动画：控件新建（列表刷新）时滑块不能从「关」滑到「开」，否则一刷新所有开关一起闪
        IsOn = isOn;
        _knob.TranslationTransition = new Vector3Transition { Duration = TimeSpan.FromMilliseconds(260) };
        _track.BackgroundTransition = new BrushTransition { Duration = TimeSpan.FromMilliseconds(260) };
        Click += (_, _) => { IsOn = !IsOn; Toggled?.Invoke(IsOn); };
    }

    public bool IsOn
    {
        get => _isOn;
        set
        {
            _isOn = value;
            _track.Background = (value ? BentoColor.Ink.Black : BentoColor.Status.Idle).Brush();
            _knob.Translation = new Vector3(value ? 14 : 0, 0, 0);
        }
    }
}

/// 两套主题共用的文案格式化。对应 Mac 端 Shared/Format.swift。
public static class Format
{
    public static string Uptime(DateTimeOffset since)
    {
        var s = Math.Max(0, (int)(DateTimeOffset.Now - since).TotalSeconds);
        int h = s / 3600, m = s % 3600 / 60;
        if (h > 0) return $"{h} 小时 {m} 分";
        return m > 0 ? $"{m} 分钟" : "刚刚";
    }

    public static string Duration(int ms) => ms >= 1000 ? $"{ms / 1000.0:0.0}s" : $"{ms}ms";

    public static string Time(DateTimeOffset t) => t.ToLocalTime().ToString("HH:mm:ss");

    /// 内存：小于 1 GB 用整数 MB，否则保留一位小数的 GB。
    public static string Bytes(long? b)
    {
        if (b is not { } v) return "—";
        var mb = v / 1_048_576.0;
        if (mb >= 1024) return $"{mb / 1024:0.0} GB";
        return mb < 1 ? "<1 MB" : $"{Math.Round(mb):0} MB";
    }

    public static string Count(int n) => n.ToString("N0");

    public static string StateLabel(Core.McpStateKind s) => s switch
    {
        Core.McpStateKind.Starting => "启动中",
        Core.McpStateKind.Ready => "正常",
        Core.McpStateKind.Backoff => "等待重试",
        Core.McpStateKind.ConfigError => "配置错误",
        _ => "已停止",
    };

    public static string CoreHeadline(Core.CoreStatus? c) => c?.State switch
    {
        Core.CoreStateKind.Running => "后台服务运行中",
        Core.CoreStateKind.NotInstalled => "网关还没接入",
        Core.CoreStateKind.Restarting => "后台服务重启中…",
        Core.CoreStateKind.Stopped => "后台服务没有运行",
        _ => "正在连接后台服务…",
    };

    public static string CoreDetail(Core.CoreStatus? c, bool showsPid = true) => c?.State switch
    {
        Core.CoreStateKind.Running => (showsPid ? $"pid {c.Pid} · " : "") + "已运行 " + Uptime(c.Since),
        Core.CoreStateKind.NotInstalled => "配置和检测可用，客户端还连不上",
        Core.CoreStateKind.Restarting => "正在重新启动，马上回来",
        Core.CoreStateKind.Stopped => c.Down?.Title ?? "后台服务没有运行",
        _ => "等待状态…",
    };
}
