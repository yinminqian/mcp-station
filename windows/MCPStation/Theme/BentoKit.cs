using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Composition;
using System.Numerics;
using MCPStation.Core;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.UI;

namespace MCPStation.Theme;

// 第二批 Bento 组件：表单、键值行、日志块、提示卡、分段选择、弹窗。对应 Mac 端 ThemeBento/Components/ 下的同名组件。

/// 分段选择：一条胶囊底上，选中项是黑色块，切换时黑块滑过去。标签页、筛选、客户端类型都用它。对应 Mac 端 BentoSegmentedPills。
///
/// - 黑块只有一个，用 Composition 画（圆角矩形 ShapeVisual），位置和宽度用系统的 Composition 关键帧动画过渡：
///   在合成线程上跑，不占 UI 线程，曲线用 Fluent 的标准减速曲线。
/// - 每项文字下面垫一份隐形的粗体，宽度按粗体算：选中变粗时这一项不变宽，整条不抖（2026-11-17 用户反馈）。
public sealed class SegmentedPills<T> : UserControl where T : notnull
{
    private static readonly TimeSpan Duration = TimeSpan.FromMilliseconds(300);

    private readonly List<(T Item, Pressable Button, TextBlock Text, TextBlock Ghost)> _items = [];
    private readonly StackPanel _row = Bento.HStack(BentoSpace.S2);
    private readonly Grid _thumbHost = new() { IsHitTestVisible = false };
    private readonly Compositor _compositor;
    private readonly ShapeVisual _thumbVisual;
    private readonly CompositionRoundedRectangleGeometry _thumb;
    private readonly CubicBezierEasingFunction _ease;
    private T _selected;
    private bool _placed;
    private Vector2 _lastOffset, _lastSize;

    public event Action<T>? SelectionChanged;

    public SegmentedPills(IEnumerable<T> items, T selected, Func<T, string> title, Color? track = null)
    {
        _selected = selected;
        foreach (var item in items)
        {
            var text = BentoText.Make(title(item), BentoTextStyle.Body, BentoColor.Ink.Secondary);
            var ghost = BentoText.Make(title(item), BentoTextStyle.BodyStrong, BentoColor.Ink.Secondary);
            ghost.Opacity = 0;
            foreach (var t in new[] { text, ghost })
            {
                Bento.CenterGlyphs(t);
                t.HorizontalAlignment = HorizontalAlignment.Center;
            }
            var cell = new Grid();
            cell.Children.Add(ghost);
            cell.Children.Add(text);
            var b = new Pressable(PressableKind.Plain)
            {
                Height = BentoSpace.S36,
                Padding = new Thickness(BentoSpace.S16, 0, BentoSpace.S16, 0),
                InnerContent = cell,
            };
            var it = item;
            b.Click += (_, _) => Select(it, notify: true);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, title(item));
            _items.Add((item, b, text, ghost));
            _row.Children.Add(b);
        }

        _compositor = ElementCompositionPreview.GetElementVisual(_thumbHost).Compositor;
        _thumb = _compositor.CreateRoundedRectangleGeometry();
        _thumb.CornerRadius = new Vector2(18, 18);
        var shape = _compositor.CreateSpriteShape(_thumb);
        shape.FillBrush = _compositor.CreateColorBrush(BentoColor.Ink.Black);
        _thumbVisual = _compositor.CreateShapeVisual();
        _thumbVisual.Shapes.Add(shape);
        _thumbVisual.RelativeSizeAdjustment = Vector2.One;
        ElementCompositionPreview.SetElementChildVisual(_thumbHost, _thumbVisual);
        _ease = _compositor.CreateCubicBezierEasingFunction(new Vector2(0.1f, 0.9f), new Vector2(0.2f, 1f));

        var stage = new Grid();
        stage.Children.Add(_thumbHost);
        stage.Children.Add(_row);
        Content = new Border
        {
            Background = (track ?? BentoColor.Bg.Surface).Brush(),
            CornerRadius = new CornerRadius(22),
            Padding = new Thickness(BentoSpace.S4),
            HorizontalAlignment = HorizontalAlignment.Left,
            Child = stage,
        };
        HorizontalAlignment = HorizontalAlignment.Left;
        _row.LayoutUpdated += (_, _) => PlaceThumb(animate: _placed);
        Paint();
    }

    public T Selected => _selected;

    public void Select(T item, bool notify = false)
    {
        if (EqualityComparer<T>.Default.Equals(item, _selected)) return;
        _selected = item;
        Paint();
        PlaceThumb(animate: true);
        if (notify) SelectionChanged?.Invoke(item);
    }

    /// 改某一项的文字（「工具 · 23」里的数字变了）。
    public void SetTitle(T item, string title)
    {
        foreach (var (i, _, t, g) in _items)
            if (EqualityComparer<T>.Default.Equals(i, item) && t.Text != title) { t.Text = title; g.Text = title; }
    }

    private void Paint()
    {
        foreach (var (item, _, text, _) in _items)
        {
            var on = EqualityComparer<T>.Default.Equals(item, _selected);
            text.FontWeight = BentoText.Weight(on ? BentoTextStyle.BodyStrong : BentoTextStyle.Body);
            text.Foreground = (on ? BentoColor.Ink.Inverse : BentoColor.Ink.Secondary).Brush();
        }
    }

    private void PlaceThumb(bool animate)
    {
        var sel = _items.FirstOrDefault(i => EqualityComparer<T>.Default.Equals(i.Item, _selected));
        if (sel.Button == null || sel.Button.ActualWidth == 0) return;
        var x = (float)sel.Button.TransformToVisual(_row).TransformPoint(default).X;
        var offset = new Vector2(x, 0);
        var size = new Vector2((float)sel.Button.ActualWidth, (float)sel.Button.ActualHeight);
        if (_placed && offset == _lastOffset && size == _lastSize) return;
        _lastOffset = offset;
        _lastSize = size;
        if (!animate || !_placed)
        {
            // 第一次就位直接放好，不从最左边滑过来
            _placed = true;
            _thumb.StopAnimation("Offset");
            _thumb.StopAnimation("Size");
            _thumb.Offset = offset;
            _thumb.Size = size;
            return;
        }
        foreach (var (prop, target) in new[] { ("Offset", offset), ("Size", size) })
        {
            var anim = _compositor.CreateVector2KeyFrameAnimation();
            anim.InsertKeyFrame(1f, target, _ease);
            anim.Duration = Duration;
            _thumb.StartAnimation(prop, anim);
        }
    }
}

public static class BentoKit
{
    // MARK: 文字

    /// 小节标题（「定义」「我的服务」）。
    public static TextBlock Section(string title, Color? color = null) =>
        BentoText.Make(title, BentoTextStyle.Label, color ?? BentoColor.Ink.Secondary);

    /// 可选中、会换行的文字。
    public static TextBlock Wrap(string text, BentoTextStyle style, Color? color = null, bool selectable = false)
    {
        var t = BentoText.Make(text, style, color);
        t.TextWrapping = TextWrapping.Wrap;
        t.TextTrimming = TextTrimming.None;
        t.IsTextSelectionEnabled = selectable;
        return t;
    }

    // MARK: 输入

    /// 输入框：单行是胶囊，多行是圆角矩形，等宽字。去掉系统输入框的边框和焦点下划线，外观由外面的 Border 负责。
    public static (Border Box, TextBox Input) Field(string placeholder, bool multiline = false, Color? fill = null, bool mono = true)
    {
        var tb = new TextBox
        {
            PlaceholderText = placeholder,
            FontFamily = mono ? BentoText.MonoFont : BentoText.UiFont,
            FontSize = BentoText.Size(mono ? BentoTextStyle.Mono : BentoTextStyle.Body),
            BorderThickness = new Thickness(0),
            Background = null,
            Padding = new Thickness(0, multiline ? 0 : 0, 0, 0),
            MinHeight = 0,
            VerticalAlignment = multiline ? VerticalAlignment.Stretch : VerticalAlignment.Center,
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            IsSpellCheckEnabled = false,
        };
        Plain(tb);
        var box = new Border
        {
            Background = (fill ?? BentoColor.Bg.Surface).Brush(),
            CornerRadius = new CornerRadius(multiline ? BentoRadius.Md : 20),
            Padding = new Thickness(BentoSpace.S14, multiline ? BentoSpace.S10 : 0, BentoSpace.S14, multiline ? BentoSpace.S10 : 0),
            MinHeight = 40,
            Child = tb,
        };
        return (box, tb);
    }

    /// 把系统 TextBox 的各状态底色、边框都换成透明（轻量样式）。
    public static void Plain(TextBox tb)
    {
        var clear = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        foreach (var k in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused", "TextControlBackgroundDisabled",
                     "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused", "TextControlBorderBrushDisabled" })
            tb.Resources[k] = clear;
        tb.Resources["TextControlForeground"] = BentoColor.Ink.Primary.Brush();
        tb.Resources["TextControlForegroundFocused"] = BentoColor.Ink.Primary.Brush();
        tb.Resources["TextControlForegroundPointerOver"] = BentoColor.Ink.Primary.Brush();
        tb.Resources["TextControlPlaceholderForeground"] = BentoColor.Ink.Tertiary.Brush();
        tb.Resources["TextControlPlaceholderForegroundFocused"] = BentoColor.Ink.Tertiary.Brush();
        tb.Resources["TextControlPlaceholderForegroundPointerOver"] = BentoColor.Ink.Tertiary.Brush();
        tb.Resources["TextControlBorderThemeThicknessFocused"] = new Thickness(0);
        tb.Resources["TextControlButtonForeground"] = BentoColor.Ink.Tertiary.Brush();
    }

    /// 搜索框：胶囊形，带放大镜（清除按钮用系统输入框自带的）。
    public static (Border Box, TextBox Input) SearchField(string prompt, Color? fill = null)
    {
        var (box, tb) = Field(prompt, fill: fill, mono: false);
        var grid = new Grid { ColumnSpacing = BentoSpace.S8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        box.Child = null;
        grid.Children.Add(BentoIcon.Make(BentoIcon.Search, BentoMetric.IconSize, BentoColor.Ink.Tertiary));
        Grid.SetColumn(tb, 1);
        grid.Children.Add(tb);
        box.Child = grid;
        return (box, tb);
    }

    /// 表单里的一栏：小标题 + 输入。
    public static StackPanel Labeled(string title, UIElement content) =>
        Bento.VStack(BentoSpace.S6, Section(title), content);

    // MARK: 行

    /// 「名称 — 值」一行，右边可以带一个附加内容（复制按钮、提示）。
    public static Grid KeyValue(string key, UIElement value, UIElement? trailing = null)
    {
        var g = new Grid { ColumnSpacing = BentoSpace.S12, MinHeight = BentoSpace.S32 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var k = BentoText.Make(key, BentoTextStyle.Body, BentoColor.Ink.Secondary);
        g.Children.Add(k);
        ((FrameworkElement)value).VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn((FrameworkElement)value, 1);
        g.Children.Add(value);
        if (trailing != null)
        {
            Grid.SetColumn((FrameworkElement)trailing, 2);
            g.Children.Add(trailing);
        }
        return g;
    }

    public static Grid KeyValue(string key, string value, bool mono = false) =>
        KeyValue(key, Wrap(value, mono ? BentoTextStyle.Mono : BentoTextStyle.Body, selectable: true));

    /// 敏感值一行：默认打码，点一下显示，再点隐藏。
    public static Pressable SecretRow(string key, string value)
    {
        const string mask = "••••••••••••";
        var text = BentoText.Make(mask, BentoTextStyle.Mono);
        var hintIcon = BentoIcon.Make(BentoIcon.Eye, BentoMetric.IconSizeSmall + 1, BentoColor.Ink.Tertiary);
        var hint = BentoText.Make("点击显示", BentoTextStyle.Label, BentoColor.Ink.Tertiary);
        var revealed = false;
        var b = new Pressable(PressableKind.Plain) { InnerContent = KeyValue(key, text, Bento.HStack(BentoSpace.S6, hintIcon, hint)) };
        b.Click += (_, _) =>
        {
            revealed = !revealed;
            text.Text = revealed ? value : mask;
            hint.Text = revealed ? "点击隐藏" : "点击显示";
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, $"{key}，点击显示或隐藏");
        return b;
    }

    // MARK: 块

    /// 说明条：黑色小标签 + 一段说明文字。
    public static Border Note(string tag, string text, BentoTone? tone = null)
    {
        var t = tone ?? BentoTone.Panel;
        var g = new Grid { ColumnSpacing = BentoSpace.S10 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        var pill = Bento.Pill(tag, BentoTone.InkTone);
        pill.VerticalAlignment = VerticalAlignment.Top;
        g.Children.Add(pill);
        var body = Wrap(text, BentoTextStyle.Body, t.MutedInk);
        body.Margin = new Thickness(0, 2, 0, 0);
        Grid.SetColumn(body, 1);
        g.Children.Add(body);
        return Bento.Card(g, t, BentoRadius.Lg, BentoSpace.S12);
    }

    /// 列表为空时的占位。
    public static StackPanel Empty(string icon, string text)
    {
        var s = Bento.VStack(BentoSpace.S10,
            Bento.IconCircle(icon, fill: BentoColor.Bg.Sunken, ink: BentoColor.Ink.Secondary),
            Wrap(text, BentoTextStyle.Body, BentoColor.Ink.Secondary));
        s.HorizontalAlignment = HorizontalAlignment.Center;
        s.Padding = new Thickness(0, BentoSpace.S32, 0, BentoSpace.S32);
        foreach (var c in s.Children) ((FrameworkElement)c).HorizontalAlignment = HorizontalAlignment.Center;
        ((TextBlock)s.Children[1]).TextAlignment = TextAlignment.Center;
        return s;
    }

    /// 数字块：小标题 + 大数字。
    public static Border StatTile(string title, string value, BentoTone tone, string? caption = null)
    {
        var s = Bento.VStack(BentoSpace.S4,
            Section(title, tone.MutedInk),
            BentoText.Make(value, BentoTextStyle.Headline, tone.Ink));
        if (caption != null)
        {
            var c = BentoText.Make(caption, BentoTextStyle.Label, tone.MutedInk);
            ToolTipService.SetToolTip(c, caption);
            s.Children.Add(c);
        }
        return Bento.Card(s, tone, BentoRadius.Lg, BentoSpace.S16);
    }

    /// 提示卡片：图标 + 标题 + 说明 + 一排操作。peach 表示等待重试，rose 表示出错。
    public static Border Alert(BentoTone tone, string icon, UIElement title, IEnumerable<UIElement> message, UIElement? actions = null)
    {
        if (title is TextBlock tt) tt.Style(BentoTextStyle.Title, tone.Ink);
        var msg = Bento.VStack(BentoSpace.S4);
        foreach (var m in message) msg.Children.Add(m);
        var s = Bento.VStack(BentoSpace.S12, Bento.HStack(BentoSpace.S12, Bento.IconCircleOn(icon, tone), title), msg);
        if (actions != null) s.Children.Add(actions);
        return Bento.Card(s, tone, BentoRadius.Xl);
    }

    /// 深色日志块：标题 + 等宽日志行，错误和警告的级别词上色。
    /// `fillsHeight`：占满可用高度并在块内滚动，打开时停在最新一行；否则按内容高度。
    public static Border LogBlock(string title, IReadOnlyList<LogLine> lines, bool fillsHeight = false)
    {
        var head = Bento.HStack(BentoSpace.S6,
            BentoIcon.Make(BentoIcon.Terminal, BentoMetric.IconSizeSmall + 1, BentoColor.Ink.InverseMuted),
            BentoText.Make(title, BentoTextStyle.Label, BentoColor.Ink.InverseMuted));
        var grid = new Grid { RowSpacing = BentoSpace.S10 };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = fillsHeight ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
        grid.Children.Add(head);
        UIElement body;
        if (lines.Count == 0)
            body = BentoText.Make("还没有日志", BentoTextStyle.Mono, BentoColor.Ink.InverseMuted);
        else
        {
            var tb = new RichTextBlock
            {
                FontFamily = BentoText.MonoFont,
                FontSize = BentoText.Size(BentoTextStyle.Mono),
                LineHeight = BentoText.LineHeight(BentoTextStyle.Mono),
                Foreground = BentoColor.Ink.Inverse.Brush(),
                IsTextSelectionEnabled = true,
                TextWrapping = TextWrapping.Wrap,
            };
            foreach (var l in lines)
            {
                var p = new Paragraph();
                p.Inlines.Add(new Run { Text = Format.Time(l.Time) + " ", Foreground = BentoColor.Ink.InverseMuted.Brush() });
                if (l.Level != LogLevel.Info)
                    p.Inlines.Add(new Run
                    {
                        Text = l.Level == LogLevel.Error ? "error " : "warn ",
                        Foreground = (l.Level == LogLevel.Error ? BentoColor.Hex(0xFF9A93) : BentoColor.Hex(0xF5C875)).Brush(),
                    });
                p.Inlines.Add(new Run { Text = l.Text });
                tb.Blocks.Add(p);
            }
            if (fillsHeight)
            {
                var sv = new ScrollViewer { Content = tb, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                sv.Loaded += (_, _) => sv.ChangeView(null, sv.ScrollableHeight, null, true);
                body = sv;
            }
            else body = tb;
        }
        Grid.SetRow((FrameworkElement)body, 1);
        grid.Children.Add(body);
        var card = Bento.Card(grid, BentoTone.Inverse, BentoRadius.Lg);
        if (fillsHeight) card.VerticalAlignment = VerticalAlignment.Stretch;
        return card;
    }

    // MARK: 控件

    /// Bento 的勾选框：18 的圆角方块，勾上是黑底白勾。
    public static Pressable Checkbox(bool isOn, UIElement label, Action<bool> onChange)
    {
        var check = BentoIcon.Make(BentoIcon.Check, BentoMetric.IconSizeSmall, BentoColor.Ink.Inverse);
        var box = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(BentoRadius.Xs), Child = check, VerticalAlignment = VerticalAlignment.Center };
        void Paint(bool on)
        {
            box.Background = (on ? BentoColor.Ink.Black : BentoColor.Bg.Surface).Brush();
            box.BorderBrush = BentoColor.Ink.Tertiary.Brush();
            box.BorderThickness = new Thickness(on ? 0 : BentoMetric.SelectionStroke);
            check.Opacity = on ? 1 : 0;
        }
        Paint(isOn);
        // 初始状态画好之后才挂动画，新建时不闪
        box.BackgroundTransition = new BrushTransition { Duration = TimeSpan.FromMilliseconds(160) };
        var state = isOn;
        var b = new Pressable(PressableKind.Plain) { InnerContent = Bento.HStack(BentoSpace.S10, box, label) };
        b.Click += (_, _) => { state = !state; Paint(state); onChange(state); };
        return b;
    }

    /// 复制按钮：点了图标变成对勾，1.5 秒后变回来。
    public static Pressable CopyButton(Func<string> text, string label, BentoTone? tone = null, bool labeled = false)
    {
        var t = tone ?? BentoTone.Panel;
        var icon = BentoIcon.Make(BentoIcon.Copy, labeled ? BentoMetric.IconSizeSmall + 1 : 14, t.Ink);
        var title = BentoText.Make("复制", BentoTextStyle.Label, t.Ink);
        var b = labeled
            ? new Pressable(PressableKind.Fill, t, 15) { Height = 30, Padding = new Thickness(BentoSpace.S12, 0, BentoSpace.S12, 0), InnerContent = Bento.HStack(BentoSpace.S6, icon, title) }
            : new Pressable(PressableKind.Fill, t, 15) { Width = 30, Height = 30, InnerContent = icon };
        b.VerticalAlignment = VerticalAlignment.Center;
        ToolTipService.SetToolTip(b, label);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, label);
        DispatcherTimer? timer = null;
        b.Click += (_, _) =>
        {
            var pkg = new DataPackage();
            pkg.SetText(text());
            Clipboard.SetContent(pkg);
            icon.Glyph = BentoIcon.Check;
            title.Text = "已复制";
            timer?.Stop();
            timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            timer.Tick += (_, _) => { icon.Glyph = BentoIcon.Copy; title.Text = "复制"; timer.Stop(); };
            timer.Start();
        };
        return b;
    }

    /// 一个小趋势线（内存最近若干次采样）：一条线加淡淡的面积，没有坐标轴。
    public static Grid Sparkline(IReadOnlyList<long> values, Color color, double width = 64, double height = 18)
    {
        var g = new Grid { Width = width, Height = height, VerticalAlignment = VerticalAlignment.Center };
        if (values.Count < 2) return g;
        double low = values.Min(), high = values.Max();
        var span = Math.Max(Math.Max(high - low, high * 0.1), 1);
        var inset = (span - (high - low)) / 2;
        var step = width / (values.Count - 1);
        var line = new Polyline { Stroke = color.Brush(), StrokeThickness = 1.5, StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        var area = new Polygon { Fill = color.WithOpacity(0.12).Brush() };
        for (var i = 0; i < values.Count; i++)
        {
            var p = new Windows.Foundation.Point(i * step, height - (values[i] - low + inset) / span * height);
            line.Points.Add(p);
            area.Points.Add(p);
        }
        area.Points.Add(new Windows.Foundation.Point(width, height));
        area.Points.Add(new Windows.Foundation.Point(0, height));
        g.Children.Add(area);
        g.Children.Add(line);
        return g;
    }

    // MARK: 弹窗

    /// Bento 外观的弹窗（Mac 端的 sheet）：系统 ContentDialog 当容器，按钮和内容都自己画。
    /// `build` 拿到一个关闭弹窗的回调，返回弹窗内容。
    public static async Task ShowDialog(XamlRoot root, double width, Func<Action, UIElement> build)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Background = BentoColor.Bg.Window.Brush(),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(BentoRadius.Xl),
            Padding = new Thickness(0),
        };
        // 模板里的底色资源会盖掉 Background，一起换成窗口的暖白，白色输入框才看得出来
        dialog.Resources["ContentDialogBackground"] = BentoColor.Bg.Window.Brush();
        dialog.Resources["ContentDialogTopOverlay"] = BentoColor.Bg.Window.Brush();
        dialog.Resources["ContentDialogBorderBrush"] = BentoColor.Bg.Window.Brush();
        dialog.Resources["ContentDialogMaxWidth"] = width + 48;
        dialog.Resources["ContentDialogMinWidth"] = width + 48;
        dialog.Resources["ContentDialogPadding"] = new Thickness(BentoSpace.S24);
        dialog.Content = new Grid { Width = width, Children = { build(() => dialog.Hide()) } };
        await dialog.ShowAsync();
    }

    /// 只输入一个名字的小弹窗（新建服务、重命名）。`submit` 返回 true 才关闭。
    public static Task AskName(XamlRoot root, string title, string actionTitle, string initial, Func<string, Task<bool>> submit) =>
        ShowDialog(root, 360, close =>
        {
            var (box, input) = Field("字母、数字、- 和 _");
            input.Text = initial;
            input.SelectAll();
            async void Go()
            {
                var name = input.Text.Trim();
                if (name.Length == 0) return;
                if (await submit(name)) close();
            }
            input.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) Go(); };
            input.Loaded += (_, _) => input.Focus(FocusState.Programmatic);
            var buttons = Bento.HStack(BentoSpace.S8, Bento.Button("取消", null, BentoTone.Panel, close), Bento.Button(actionTitle, null, BentoTone.InkTone, Go));
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            return Bento.VStack(BentoSpace.S14, BentoText.Make(title, BentoTextStyle.Title), box, buttons);
        });

    /// 确认框（删除服务）。返回是否确认。
    public static async Task<bool> Confirm(XamlRoot root, string title, string message, string actionTitle)
    {
        var ok = false;
        await ShowDialog(root, 380, close =>
        {
            var buttons = Bento.HStack(BentoSpace.S8,
                Bento.Button("取消", null, BentoTone.Panel, close),
                Bento.Button(actionTitle, BentoIcon.Delete, BentoTone.Rose, () => { ok = true; close(); }));
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            return Bento.VStack(BentoSpace.S14, BentoText.Make(title, BentoTextStyle.Title), Wrap(message, BentoTextStyle.Body, BentoColor.Ink.Secondary), buttons);
        });
        return ok;
    }
}
