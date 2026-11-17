using System.Diagnostics;
using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.Storage.Pickers;

namespace MCPStation.Views;

/// 设置页：外观、网关、配置、关于，两列卡片。对应 Mac 端 BentoSettingsPage.swift。
public sealed class SettingsPage : Grid
{
    private readonly AppStore _store;
    private readonly Grid _grid = new() { ColumnSpacing = BentoSpace.S12, RowSpacing = BentoSpace.S12, Padding = new Thickness(BentoSpace.S20) };
    private readonly ContentControl _core = Host(), _config = Host(), _about = Host();
    private TextBox? _port;

    public SettingsPage(AppStore store)
    {
        _store = store;
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);
        RowSpacing = BentoSpace.S12;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition());
        var title = BentoText.Make("设置", BentoTextStyle.Headline, BentoColor.Ink.Black);
        title.Height = 40;
        title.Margin = new Thickness(BentoSpace.S4, 0, 0, 0);
        Children.Add(title);

        _grid.ColumnDefinitions.Add(new ColumnDefinition());
        _grid.ColumnDefinitions.Add(new ColumnDefinition());
        _grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Place(Host(AppearanceCard()), 0, 0);
        Place(_core, 0, 1);
        Place(_config, 1, 0);
        Place(_about, 1, 1);
        var panel = Bento.Panel(new ScrollViewer { Content = _grid, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden });
        SetRow(panel, 1);
        Children.Add(panel);

        store.CoreChanged += Render;
        store.MemoryChanged += Render;
        store.McpsChanged += Render;
        store.BusyChanged += Render;
        Render();
    }

    private static ContentControl Host(UIElement? content = null) => new()
    {
        Content = content,
        HorizontalContentAlignment = HorizontalAlignment.Stretch,
        VerticalContentAlignment = VerticalAlignment.Stretch,
    };

    private void Place(FrameworkElement e, int row, int col)
    {
        SetRow(e, row);
        SetColumn(e, col);
        _grid.Children.Add(e);
    }

    private void Render()
    {
        // 正在改端口时不重建网关卡片，免得把输入框里的字冲掉
        var editingPort = _port != null && _port.FocusState != FocusState.Unfocused && _port.Text.Trim() != _store.Core?.Port.ToString();
        if (!editingPort) _core.Content = CoreCard();
        _config.Content = ConfigCard();
        _about.Content = AboutCard();
    }

    private static Border SettingsCard(string title, params UIElement[] content)
    {
        var s = Bento.VStack(BentoSpace.S12, BentoKit.Section(title));
        foreach (var c in content) s.Children.Add(c);
        var card = Bento.Card(s);
        card.VerticalAlignment = VerticalAlignment.Stretch;
        return card;
    }

    // MARK: 外观

    private static UIElement AppearanceCard()
    {
        var options = new Grid { ColumnSpacing = BentoSpace.S12 };
        options.ColumnDefinitions.Add(new ColumnDefinition());
        options.ColumnDefinitions.Add(new ColumnDefinition());
        options.Children.Add(ThemeOption("Pastel Bento", "粉彩色块，自绘界面", true, true));
        var fluent = ThemeOption("Fluent", "Windows 原生控件 · 还在做", false, false);
        SetColumn(fluent, 1);
        options.Children.Add(fluent);
        return SettingsCard("外观", options, BentoKit.Note("说明", "Mac 版的第二套界面是 Liquid Glass；Windows 版对应的是 Fluent（Mica 背景、系统控件），做好后在这里切换。"));
    }

    private static FrameworkElement ThemeOption(string title, string subtitle, bool selected, bool enabled)
    {
        // 缩略图：左边侧栏、中间几块粉彩色块、右边面板
        var thumb = new Grid { Height = 92, ColumnSpacing = BentoSpace.S6, Padding = new Thickness(BentoSpace.S8), Background = BentoColor.Bg.Window.Brush() };
        thumb.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
        thumb.ColumnDefinitions.Add(new ColumnDefinition());
        thumb.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
        Border Block(Windows.UI.Color c, double r = BentoRadius.Xs) => new() { Background = c.Brush(), CornerRadius = new CornerRadius(r) };
        if (enabled)
        {
            thumb.Children.Add(Block(BentoColor.Bg.Panel, BentoRadius.Sm));
            var mid = new Grid { RowSpacing = BentoSpace.S4, ColumnSpacing = BentoSpace.S4 };
            mid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });
            mid.RowDefinitions.Add(new RowDefinition());
            mid.RowDefinitions.Add(new RowDefinition());
            for (var i = 0; i < 3; i++) mid.ColumnDefinitions.Add(new ColumnDefinition());
            var head = Block(BentoColor.Ink.Black);
            SetColumnSpan(head, 2);
            mid.Children.Add(head);
            var tones = new[] { BentoTone.Peach, BentoTone.Lavender, BentoTone.Sky, BentoTone.Mint, BentoTone.Lavender, BentoTone.Mint };
            for (var i = 0; i < 6; i++)
            {
                var b = Block(tones[i].Fill);
                SetRow(b, 1 + i / 3);
                SetColumn(b, i % 3);
                mid.Children.Add(b);
            }
            SetColumn(mid, 1);
            thumb.Children.Add(mid);
            var right = Block(BentoColor.Bg.Panel, BentoRadius.Sm);
            SetColumn(right, 2);
            thumb.Children.Add(right);
        }
        else
        {
            thumb.Background = BentoColor.Bg.Surface.Brush();
            thumb.Children.Add(Block(BentoColor.Bg.Sunken, BentoRadius.Sm));
            var lines = Bento.VStack(BentoSpace.S4);
            for (var i = 0; i < 5; i++) lines.Children.Add(new Border { Height = 10, Background = BentoColor.Bg.Sunken.Brush(), CornerRadius = new CornerRadius(3) });
            SetColumn(lines, 1);
            SetColumnSpan(lines, 2);
            thumb.Children.Add(lines);
        }
        var clipped = new Border { CornerRadius = new CornerRadius(BentoRadius.Sm), Child = thumb };
        var check = Bento.IconCircle(BentoIcon.Check, BentoSpace.S20, BentoColor.Ink.Black, BentoColor.Ink.Inverse);
        check.Opacity = selected ? 1 : 0;
        var caption = Bento.Row(BentoSpace.S8,
            Bento.VStack(0, BentoText.Make(title, BentoTextStyle.BodyStrong), BentoText.Make(subtitle, BentoTextStyle.Label, BentoColor.Ink.Secondary)), null, check);
        caption.Margin = new Thickness(BentoSpace.S4, 0, BentoSpace.S4, 0);
        var card = Bento.Card(Bento.VStack(BentoSpace.S10, clipped, caption), BentoTone.Panel, BentoRadius.Md, BentoSpace.S10);
        card.BorderThickness = new Thickness(BentoMetric.SelectionStroke);
        card.BorderBrush = (selected ? BentoColor.Ink.Black : Microsoft.UI.Colors.Transparent).Brush();
        card.Opacity = enabled ? 1 : 0.55;
        return card;
    }

    // MARK: 网关

    private UIElement CoreCard()
    {
        var core = _store.Core;
        var rows = Bento.VStack(0,
            BentoKit.KeyValue("状态", Bento.HStack(BentoSpace.S8, Bento.StatusDot(BentoStatusExt.Of(core)), BentoText.Make(Format.CoreHeadline(core), BentoTextStyle.BodyStrong))));
        if (core != null) rows.Children.Add(PortRow(core));
        if (core?.Memory != null)
            rows.Children.Add(BentoKit.KeyValue("内存", Bento.HStack(BentoSpace.S6,
                BentoText.Make(Format.Bytes(core.Memory), BentoTextStyle.Body),
                BentoText.Make($"· 连同所有 MCP 合计 {Format.Bytes(_store.TotalMemory)}", BentoTextStyle.Body, BentoColor.Ink.Secondary))));
        var autostart = new BentoSwitch(Autostart.IsEnabled);
        autostart.Toggled += on =>
        {
            try { Autostart.Set(on); _store.ShowToast(on ? "登录 Windows 时会自动在托盘里打开" : "已关闭开机自启"); }
            catch (Exception e) { _store.ShowToast(e.Message, true); autostart.IsOn = !on; }
        };
        rows.Children.Add(BentoKit.KeyValue("开机自启", Bento.HStack(BentoSpace.S10, autostart,
            BentoText.Make("登录时在托盘里打开，网关跟着起来", BentoTextStyle.Label, BentoColor.Ink.Secondary))));

        var busy = _store.IsBusy("core-restart") || core?.State == CoreStateKind.Restarting;
        var restart = Bento.Button(busy ? "正在处理…" : core?.RestartTitle ?? "重新检测", BentoIcon.Restart, BentoTone.InkTone, () => _store.RestartCore());
        restart.IsEnabled = !busy;
        var actions = Bento.HStack(BentoSpace.S10, restart,
            BentoText.Make(core?.State == CoreStateKind.NotInstalled ? "重新读配置，所有 MCP 重新握手" : "重启后客户端需要重新连接", BentoTextStyle.Label, BentoColor.Ink.Secondary));
        var card = SettingsCard("网关", rows, actions);
        if (core?.State == CoreStateKind.NotInstalled)
            ((StackPanel)card.Child).Children.Add(BentoKit.Note("说明", "网关端口没起来：MCP 照常常驻，能检测、试调用、看内存；客户端还连不上，换个端口后就好了。"));
        return card;
    }

    private UIElement PortRow(CoreStatus core)
    {
        var (box, input) = BentoKit.Field("端口", fill: BentoColor.Bg.Panel);
        box.Width = 84;
        box.Height = 30;
        box.MinHeight = 30;
        box.CornerRadius = new CornerRadius(15);
        box.Padding = new Thickness(BentoSpace.S10, 0, BentoSpace.S10, 0);
        input.Text = core.Port.ToString();
        _port = input;
        Pressable? save = null;
        save = Bento.Button("保存", null, BentoTone.InkTone, () => Save(), small: true);
        save.Visibility = Visibility.Collapsed;
        input.TextChanged += (_, _) => save!.Visibility = input.Text.Trim() == core.Port.ToString() ? Visibility.Collapsed : Visibility.Visible;
        input.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) Save(); };
        async void Save()
        {
            if (!int.TryParse(input.Text.Trim(), out var n)) { _store.ShowToast("端口要填数字", true); input.Text = core.Port.ToString(); return; }
            if (n == core.Port) return;
            save!.IsEnabled = false;
            if (!await _store.SetPort(n)) input.Text = core.Port.ToString();
            save.IsEnabled = true;
        }
        var value = Bento.VStack(BentoSpace.S4, Bento.HStack(BentoSpace.S6, BentoText.Make("127.0.0.1:", BentoTextStyle.Mono, BentoColor.Ink.Secondary), box, save));
        if (core.GatewayError is { } err) value.Children.Add(BentoKit.Wrap(err, BentoTextStyle.Label, BentoTone.Peach.Ink));
        return BentoKit.KeyValue("端口", value);
    }

    // MARK: 配置

    private UIElement ConfigCard()
    {
        var canManage = _store.Core?.CanManage == true;
        var path = DataDir.File("config.json");
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var shown = path.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + path[home.Length..] : path;
        var pathText = BentoText.Make(shown, BentoTextStyle.Mono);
        ToolTipService.SetToolTip(pathText, path);
        var import = Bento.Button("导入…", null, BentoTone.InkTone, () => _ = Import(), small: true);
        import.IsEnabled = canManage && !_store.IsBusy("import");
        var export = Bento.Button("导出…", null, BentoTone.Panel, () => _ = Export(), small: true);
        export.IsEnabled = canManage;
        var reveal = Bento.Button("在资源管理器中显示", BentoIcon.Folder, BentoTone.Panel, () => Reveal(path), small: true);
        return SettingsCard("配置",
            BentoKit.KeyValue("配置文件", pathText),
            Bento.HStack(BentoSpace.S8, import, export, reveal),
            BentoKit.Note("说明", "导入支持本软件导出的文件和 Claude Code、Cursor 等的 mcpServers 配置，同名会覆盖；导出的文件含密钥明文。"));
    }

    private async Task Import()
    {
        var picker = new FileOpenPicker(App.MainWindow!.AppWindow.Id) { CommitButtonText = "导入" };
        picker.FileTypeFilter.Add(".json");
        if (await picker.PickSingleFileAsync() is { } file) await _store.ImportConfig(file.Path);
    }

    private async Task Export()
    {
        var picker = new FileSavePicker(App.MainWindow!.AppWindow.Id) { SuggestedFileName = "mcp-station-config", CommitButtonText = "导出" };
        picker.FileTypeChoices.Add("JSON", [".json"]);
        if (await picker.PickSaveFileAsync() is { } file) await _store.ExportConfig(file.Path);
    }

    public static void Reveal(string path)
    {
        try
        {
            if (File.Exists(path)) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            else
            {
                var dir = Path.GetDirectoryName(path)!;
                Directory.CreateDirectory(dir);
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
            }
        }
        catch { }
    }

    // MARK: 关于

    private UIElement AboutCard()
    {
        var version = typeof(App).Assembly.GetName().Version?.ToString(3) ?? "开发版";
        var head = Bento.HStack(BentoSpace.S12,
            Bento.IconCircle(BentoIcon.Brand, BentoMetric.RailButton, BentoColor.Ink.Black, BentoColor.Ink.Inverse),
            Bento.VStack(0, BentoText.Make("MCP Station", BentoTextStyle.Title),
                BentoKit.Wrap("本机 MCP 网关：一个地址，背后有哪些 MCP 由开关和服务决定", BentoTextStyle.Label, BentoColor.Ink.Secondary)));
        var rows = Bento.VStack(0,
            BentoKit.KeyValue("App 版本", version),
            BentoKit.KeyValue("内核版本", _store.Core?.Version ?? "—"),
            BentoKit.KeyValue("MCP", $"{_store.Mcps.Count} 个，{_store.Mcps.Sum(m => m.ToolCount)} 个工具"),
            BentoKit.KeyValue("数据目录", BentoText.Make(DataDir.Path, BentoTextStyle.Mono)));
        var check = Bento.Button("检查更新…", null, BentoTone.Panel, () => _ = Updater.CheckNow(XamlRoot, _store), small: true);
        return SettingsCard("关于", head, rows, check);
    }
}
