using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.Views;

/// 左侧导航栏：品牌、四个主页面，底部是设置和后台服务状态。每项是「图标 + 文字」，选中整行铺淡色底。
/// 窗口窄时收成只有图标的窄条，图标位置不动。对应 Mac 端 ThemeBento/BentoRail.swift。
public sealed class BentoRail : UserControl
{
    /// 选中行的色调（默认服务的 lavender；mint / peach / rose 是状态色）。
    private static readonly BentoTone RowTone = BentoTone.Lavender;
    private static readonly Navigator.Route[] MainRoutes = [Navigator.Route.Overview, Navigator.Route.Mcps, Navigator.Route.Services, Navigator.Route.Calls];

    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly Border _shell;
    private readonly StackPanel _brandText;
    private readonly Dictionary<Navigator.Route, (Pressable Button, FontIcon Icon, TextBlock Text, Border Badge)> _rows = [];
    private readonly Pressable _coreRow;
    private readonly Grid _coreDotHost = new() { Width = BentoSpace.S20 };
    private readonly TextBlock _coreText;
    private bool _compact;

    public BentoRail(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;

        var stack = new Grid { RowSpacing = BentoSpace.S4 };
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        foreach (var _ in MainRoutes) stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        // 品牌：圆标和下面各行的图标同一条中轴，名字和各行文字左对齐
        _brandText = Bento.VStack(0,
            BentoText.Make("MCP Station", BentoTextStyle.Title, BentoColor.Ink.Black),
            BentoText.Make("本机 MCP 网关", BentoTextStyle.Label, BentoColor.Ink.Secondary));
        _brandText.VerticalAlignment = VerticalAlignment.Center;
        var brand = Bento.HStack(BentoSpace.S8,
            Bento.IconCircle(BentoIcon.Brand, BentoSpace.S32, BentoColor.Ink.Black, BentoColor.Ink.Inverse),
            _brandText);
        brand.Height = BentoSpace.S40;
        brand.Margin = new Thickness(BentoSpace.S8, 0, 0, BentoSpace.S16);
        stack.Children.Add(brand);

        var row = 1;
        foreach (var route in MainRoutes)
        {
            var r = MakeRow(route);
            Grid.SetRow(r.Button, row++);
            stack.Children.Add(r.Button);
        }
        var settings = MakeRow(Navigator.Route.Settings);
        Grid.SetRow(settings.Button, row + 1);
        stack.Children.Add(settings.Button);

        // 底部：「● 后台服务运行中」
        _coreText = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Secondary);
        _coreRow = new Pressable(PressableKind.Row, radius: BentoRadius.Sm)
        {
            Height = BentoSpace.S36,
            Padding = new Thickness(BentoSpace.S14, 0, BentoSpace.S14, 0),
            InnerContent = Bento.HStack(BentoSpace.S14, _coreDotHost, _coreText),
        };
        _coreRow.Click += (_, _) => _nav.Current = Navigator.Route.Settings;
        Grid.SetRow(_coreRow, row + 2);
        stack.Children.Add(_coreRow);

        _shell = new Border
        {
            Background = BentoColor.Bg.Panel.Brush(),
            CornerRadius = new CornerRadius(BentoRadius.Xl),
            Padding = new Thickness(BentoSpace.S8, BentoSpace.S12, BentoSpace.S8, BentoSpace.S12),
            Width = BentoMetric.SidebarWidth,
            Child = stack,
        };
        Content = _shell;

        _nav.RouteChanged += Refresh;
        _store.CoreChanged += Refresh;
        _store.McpsChanged += Refresh;
        Refresh();
    }

    public bool IsCompact
    {
        get => _compact;
        set
        {
            if (_compact == value) return;
            _compact = value;
            _shell.Width = value ? BentoMetric.RailWidth : BentoMetric.SidebarWidth;
            Refresh();
        }
    }

    private (Pressable Button, FontIcon Icon, TextBlock Text, Border Badge) MakeRow(Navigator.Route route)
    {
        var icon = BentoIcon.Make(Navigator.Icon(route), BentoMetric.IconSize, BentoColor.Ink.Secondary);
        var iconBox = new Grid { Width = BentoSpace.S20 };
        iconBox.Children.Add(icon);
        var text = BentoText.Make(Navigator.Title(route), BentoTextStyle.Body);
        var badge = new Border { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
        var content = new Grid();
        content.Children.Add(Bento.HStack(BentoSpace.S14, iconBox, text));
        content.Children.Add(badge);
        var b = new Pressable(PressableKind.Row, radius: BentoRadius.Sm)
        {
            Height = BentoSpace.S36,
            Padding = new Thickness(BentoSpace.S14, 0, BentoSpace.S8, 0),
            InnerContent = content,
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, Navigator.Title(route));
        b.Click += (_, _) => _nav.Current = route;
        var tuple = (b, icon, text, badge);
        _rows[route] = tuple;
        return tuple;
    }

    private void Refresh()
    {
        var coreDown = _store.Core?.CanManage == false;
        var attention = coreDown ? 0 : _store.Attention.Count;
        _brandText.Visibility = _compact ? Visibility.Collapsed : Visibility.Visible;
        foreach (var (route, r) in _rows)
        {
            var selected = _nav.Current == route;
            r.Button.SelectedFill = selected ? RowTone.Fill : null;
            r.Icon.Foreground = (selected ? RowTone.Ink : BentoColor.Ink.Secondary).Brush();
            r.Text.Style(selected ? BentoTextStyle.BodyStrong : BentoTextStyle.Body, selected ? RowTone.Ink : BentoColor.Ink.Primary);
            r.Text.Visibility = _compact ? Visibility.Collapsed : Visibility.Visible;
            r.Button.Opacity = coreDown && route != Navigator.Route.Overview && route != Navigator.Route.Settings && !selected ? 0.4 : 1;
            ToolTipService.SetToolTip(r.Button, _compact ? Navigator.Title(route) : null);
            var count = route == Navigator.Route.Mcps ? attention : 0;
            r.Badge.Child = count == 0 ? null : _compact ? Bento.StatusDot(BentoStatus.Warn, BentoSpace.S8) : Bento.Pill(count.ToString(), BentoTone.Peach);
            r.Badge.Margin = _compact ? new Thickness(0, -16, -4, 0) : new Thickness(0);
        }
        _coreDotHost.Children.Clear();
        _coreDotHost.Children.Add(Bento.StatusDot(BentoStatusExt.Of(_store.Core), BentoSpace.S8));
        _coreText.Text = Format.CoreHeadline(_store.Core);
        _coreText.Visibility = _compact ? Visibility.Collapsed : Visibility.Visible;
        ToolTipService.SetToolTip(_coreRow, Format.CoreHeadline(_store.Core));
    }
}

/// 还没做完的页面。
public sealed class PlaceholderPage : Grid
{
    public PlaceholderPage(Navigator.Route route)
    {
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);
        var panel = Bento.Panel(Bento.VStack(BentoSpace.S10,
            Bento.IconCircle(Navigator.Icon(route), BentoMetric.IconCircleLarge, BentoColor.Bg.Sunken, BentoColor.Ink.Secondary),
            BentoText.Make($"「{Navigator.Title(route)}」页面还在做", BentoTextStyle.Title),
            BentoText.Make("先看概览页。", BentoTextStyle.Body, BentoColor.Ink.Secondary)));
        if (panel.Child is StackPanel s)
        {
            s.HorizontalAlignment = HorizontalAlignment.Center;
            s.VerticalAlignment = VerticalAlignment.Center;
            foreach (var c in s.Children) ((FrameworkElement)c).HorizontalAlignment = HorizontalAlignment.Center;
        }
        Children.Add(panel);
    }
}
