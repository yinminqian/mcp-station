using MCPStation.State;
using MCPStation.Theme;
using MCPStation.Views;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;

namespace MCPStation;

/// 主窗口：左边侧边栏（窄窗口时收成图标条），右边按当前页面挂内容。对应 Mac 端 ThemeBento/BentoRoot.swift。
///
/// 内容延伸到标题栏下面（Mac 上是透明标题栏 + 红绿灯，这里是系统的最小化 / 最大化 / 关闭按钮），
/// 顶部 44 的一条留给拖动和窗口标题。
public sealed class MainWindow : Window
{
    private readonly AppStore _store;
    private readonly Navigator _nav = Navigator.Shared;
    private readonly BentoRail _rail;
    private readonly Grid _pages = new();
    private readonly Dictionary<Navigator.Route, FrameworkElement> _pageCache = [];
    private readonly TextBlock _title;
    private readonly Border _toast = new();
    private readonly TrayIcon? _tray;
    private bool _quitting;

    public MainWindow(AppStore store)
    {
        _store = store;
        Title = "MCP Station";

        // 标题栏：内容铺到顶，系统按钮透明底、深色图标
        ExtendsContentIntoTitleBar = true;
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
        AppWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        AppWindow.TitleBar.ButtonForegroundColor = BentoColor.Ink.Primary;
        AppWindow.TitleBar.ButtonInactiveForegroundColor = BentoColor.Ink.Tertiary;
        AppWindow.TitleBar.ButtonHoverBackgroundColor = BentoColor.Ink.Black.WithOpacity(0.06);
        AppWindow.TitleBar.ButtonHoverForegroundColor = BentoColor.Ink.Black;
        AppWindow.TitleBar.ButtonPressedBackgroundColor = BentoColor.Ink.Black.WithOpacity(0.1);
        AppWindow.TitleBar.ButtonPressedForegroundColor = BentoColor.Ink.Black;
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);

        var root = new Grid { Background = BentoColor.Bg.Window.Brush() };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // 拖动区：整条顶栏
        var dragBar = new Grid { Height = BentoMetric.TitleBarInset, VerticalAlignment = VerticalAlignment.Top, Background = new SolidColorBrush(Colors.Transparent) };
        Grid.SetColumnSpan(dragBar, 2);
        _title = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Tertiary);
        _title.HorizontalAlignment = HorizontalAlignment.Center;
        _title.IsHitTestVisible = false;
        dragBar.Children.Add(_title);
        root.Children.Add(dragBar);
        SetTitleBar(dragBar);

        _rail = new BentoRail(store, _nav)
        {
            Margin = new Thickness(BentoMetric.WindowInset, BentoMetric.TitleBarInset, 0, BentoMetric.WindowInset),
        };
        root.Children.Add(_rail);

        Grid.SetColumn(_pages, 1);
        root.Children.Add(_pages);

        // 一句话提示（操作失败等），在底部正中，3 秒后消失
        _toast.HorizontalAlignment = HorizontalAlignment.Center;
        _toast.VerticalAlignment = VerticalAlignment.Bottom;
        _toast.Margin = new Thickness(0, 0, 0, BentoSpace.S24);
        _toast.Padding = new Thickness(BentoSpace.S16, BentoSpace.S10, BentoSpace.S16, BentoSpace.S10);
        _toast.CornerRadius = new CornerRadius(20);
        _toast.Opacity = 0;
        _toast.IsHitTestVisible = false;
        _toast.OpacityTransition = new ScalarTransition { Duration = TimeSpan.FromMilliseconds(280) };
        Grid.SetColumnSpan(_toast, 2);
        root.Children.Add(_toast);

        // 焦点落点：窗口打开时先把焦点放在这里，免得系统把焦点（和它的焦点框）放到侧边栏第一个按钮上
        var focusSink = new ContentControl { IsTabStop = true, Width = 0, Height = 0, UseSystemFocusVisuals = false };
        root.Children.Add(focusSink);
        root.Loaded += (_, _) => focusSink.Focus(FocusState.Programmatic);
        // 打开 10 秒后悄悄查一次更新（同 Mac 端 Sparkle 的自动检查）
        root.Loaded += async (_, _) => { await Task.Delay(10_000); await Updater.CheckInBackground(root.XamlRoot); };
        Content = root;

        root.SizeChanged += (_, e) => _rail.IsCompact = e.NewSize.Width < BentoMetric.SidebarCollapseBelow;
        _nav.RouteChanged += ShowRoute;
        _store.Toast += ShowToast;
        ShowRoute();

        SizeWindow();

        // 托盘：关窗口只是收进托盘，网关照常运行；从托盘「退出」才真的退出 App（内核仍然保留，和 Mac 版一样）
        if (File.Exists(icon))
        {
            _tray = new TrayIcon(WinRT.Interop.WindowNative.GetWindowHandle(this), icon);
            _tray.Invoked += cmd =>
            {
                switch (cmd)
                {
                    case TrayIcon.Command.Open: ShowAndFocus(); break;
                    case TrayIcon.Command.RestartCore: _store.RestartCore(); break;
                    case TrayIcon.Command.Quit: Quit(); break;
                }
            };
            _store.CoreChanged += () => _tray.SetStatus(Format.CoreHeadline(_store.Core));
            _tray.SetStatus(Format.CoreHeadline(_store.Core));
        }
        AppWindow.Closing += (_, e) =>
        {
            if (_quitting || _tray == null) return;
            e.Cancel = true;
            AppWindow.Hide();
        };
        Closed += (_, _) => { _tray?.Dispose(); _store.Stop(); };
    }

    public void ShowAndFocus()
    {
        AppWindow.Show();
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } p) p.Restore();
        Activate();
        SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(this));
    }

    private void Quit()
    {
        _quitting = true;
        _tray?.Dispose();
        _store.Stop();
        Close();
        Application.Current.Exit();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    /// 页面常驻：第一次进入时建，之后切换只改可见性（Mac 端 KeepAlivePages 同理），滚动位置和选中项都保留。
    private void ShowRoute()
    {
        var route = _nav.Current;
        if (!_pageCache.TryGetValue(route, out var page))
        {
            page = route switch
            {
                Navigator.Route.Overview => new OverviewPage(_store, _nav),
                Navigator.Route.Mcps => new McpsPage(_store, _nav),
                Navigator.Route.Services => new ServicesPage(_store, _nav),
                Navigator.Route.Calls => new CallsPage(_store, _nav),
                _ => new SettingsPage(_store),
            };
            _pageCache[route] = page;
            _pages.Children.Add(page);
        }
        foreach (var (r, p) in _pageCache) p.Visibility = r == route ? Visibility.Visible : Visibility.Collapsed;
        _title.Text = $"MCP Station — {Navigator.Title(route)}";
    }

    private DispatcherTimer? _toastTimer;

    private void ShowToast(string text, bool isError)
    {
        var tone = isError ? BentoTone.Rose : BentoTone.InkTone;
        _toast.Background = tone.Fill.Brush();
        _toast.Child = BentoText.Make(text, BentoTextStyle.BodyStrong, tone.Ink);
        _toast.Opacity = 1;
        _toastTimer?.Stop();
        _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        _toastTimer.Tick += (_, _) => { _toast.Opacity = 0; _toastTimer.Stop(); };
        _toastTimer.Start();
    }

    /// 初始大小 1280×820（逻辑像素），最小 980×640，放在屏幕正中。
    private void SizeWindow()
    {
        var scale = (Content.XamlRoot?.RasterizationScale) ?? GetDpiScale();
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int w = (int)Math.Min(1280 * scale, area.Width * 0.92), h = (int)Math.Min(820 * scale, area.Height * 0.92);
        AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h));
        if (AppWindow.Presenter is OverlappedPresenter p)
        {
            p.PreferredMinimumWidth = (int)(980 * scale);
            p.PreferredMinimumHeight = (int)(640 * scale);
        }
    }

    private double GetDpiScale()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        return GetDpiForWindow(hwnd) / 96.0;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);
}
