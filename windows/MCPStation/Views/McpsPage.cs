using System.Text.Json;
using System.Text.Json.Nodes;
using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;

namespace MCPStation.Views;

/// MCP 页：左边列表，右边选中那个的详情。对应 Mac 端 ThemeBento/Pages/MCPs/。
public sealed class McpsPage : Grid
{
    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly StackPanel _list = Bento.VStack(BentoSpace.S8);
    private readonly TextBox _search;
    private readonly Border _countPill = new();
    private readonly Pressable _add;
    private readonly McpDetail _detail;
    private readonly DispatcherTimer _ticker = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly List<(TextBlock Text, Func<string> Line)> _countdowns = [];

    public McpsPage(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);
        ColumnSpacing = BentoSpace.S16;
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(296) });
        ColumnDefinitions.Add(new ColumnDefinition());

        // 左栏：标题、搜索、列表
        _add = Bento.Button("添加 MCP", BentoIcon.Add, BentoTone.InkTone, () => _ = AddMcpDialog(), small: true);
        var header = Bento.Row(BentoSpace.S8, Bento.HStack(BentoSpace.S8, BentoText.Make("MCP", BentoTextStyle.Headline, BentoColor.Ink.Black), _countPill), null, _add);
        header.Height = 40;
        var (searchBox, search) = BentoKit.SearchField("搜索 MCP");
        _search = search;
        _search.TextChanged += (_, _) => RenderList();
        var scroll = new ScrollViewer { Content = _list, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
        _list.Padding = new Thickness(0, 0, 0, BentoSpace.S12);
        var left = new Grid { RowSpacing = BentoSpace.S12 };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition());
        left.Children.Add(header);
        SetRow(searchBox, 1);
        left.Children.Add(searchBox);
        SetRow(scroll, 2);
        left.Children.Add(scroll);
        Children.Add(left);

        _detail = new McpDetail(store, nav, this);
        var panel = Bento.Panel(_detail);
        SetColumn(panel, 1);
        Children.Add(panel);

        store.McpsChanged += Refresh;
        store.ServicesChanged += RenderList;
        store.MemoryChanged += RenderList;
        store.CoreChanged += () => _add.IsEnabled = store.Core?.CanManage == true;
        nav.SelectionChanged += Refresh;
        _ticker.Tick += (_, _) => { foreach (var (t, line) in _countdowns) t.Text = line(); };
        Loaded += (_, _) => _ticker.Start();
        Unloaded += (_, _) => _ticker.Stop();
        Refresh();
    }

    private void Refresh()
    {
        // 进来没选中（或选中的被删了）就选第一个，右边不留空
        if (_store.Mcp(_nav.SelectedMcp) == null && _store.Mcps.Count > 0)
        {
            _nav.SelectMcp(_store.Mcps[0].Name);
            return;
        }
        RenderList();
        _detail.Render();
    }

    private static string Countdown(McpServer m)
    {
        var s = m.RetryAt is { } at ? Math.Max(0, (int)Math.Ceiling((at - DateTimeOffset.Now).TotalSeconds)) : 0;
        return $"等待重试 {s}s";
    }

    /// 列表行按名字缓存、原地更新（文字、内存、状态点、开关、选中框）。
    /// 不能每次推送都把整列表重建：内存每 5 秒来一次，重建会让所有行（尤其开关）一起闪一下（2026-11-17 用户反馈）。
    private readonly Dictionary<string, McpRow> _rows = [];
    private FrameworkElement? _emptyState;

    private void RenderList()
    {
        _countPill.Child = Bento.Pill($"{_store.Mcps.Count} 个", BentoTone.Panel);
        var q = _search.Text.Trim();
        var shown = _store.Mcps.Where(m => q.Length == 0 || m.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
        var canManage = _store.Core?.CanManage == true;

        foreach (var gone in _rows.Keys.Except(_store.Mcps.Select(m => m.Name)).ToList()) _rows.Remove(gone);
        _countdowns.Clear();
        var wanted = new List<UIElement>();
        foreach (var m in shown)
        {
            if (!_rows.TryGetValue(m.Name, out var row))
            {
                var name = m.Name;
                row = new McpRow(() => _nav.SelectMcp(name), on => _store.SetDefault(name, on));
                _rows[m.Name] = row;
            }
            var line = row.Update(m, m.Name == _nav.SelectedMcp, _store.UsedBy(m), canManage);
            if (line != null) _countdowns.Add((row.Summary, line));
            wanted.Add(row.Element);
        }
        if (_store.Mcps.Count == 0)
            wanted.Add(_emptyState = BentoKit.Empty(BentoIcon.Mcps, "还没有 MCP。点右上角「添加 MCP」，或在设置页导入现有的配置（Claude Code、Cursor 等的 mcpServers）"));
        else if (shown.Count == 0)
            wanted.Add(_emptyState = BentoKit.Empty(BentoIcon.Search, "没有符合条件的 MCP"));

        // 只有行的集合或顺序变了才重排
        if (!_list.Children.SequenceEqual(wanted))
        {
            _list.Children.Clear();
            foreach (var e in wanted) _list.Children.Add(e);
        }
    }

    private static string Summary(McpServer m, List<string> usedBy)
    {
        var services = usedBy.Count == 0 ? "没有服务用到" : string.Join("、", usedBy);
        return $"{m.Kind.Label()} · " + m.State switch
        {
            McpStateKind.Backoff => Countdown(m),
            McpStateKind.Ready => $"{m.ToolCount} 工具",
            _ => Format.StateLabel(m.State),
        } + $" · {services}";
    }

    /// 列表里的一行：状态点、名字、一句话摘要（「npx · 24 工具 · 默认、ios」，等待重试时中间是倒计时）、内存、默认服务开关。
    private sealed class McpRow
    {
        public Border Element { get; }
        public TextBlock Summary { get; }
        private readonly Pressable _button;
        private readonly Grid _dot = new() { VerticalAlignment = VerticalAlignment.Center };
        private readonly TextBlock _name;
        private readonly TextBlock _memory;
        private readonly StackPanel _trailing;
        private readonly Action<bool> _setDefault;
        /// 开关在第一次拿到数据时才建（按真实初始值建，免得新建时滑块滑一下）。
        private BentoSwitch? _switch;
        private BentoStatus? _status;

        public McpRow(Action select, Action<bool> setDefault)
        {
            _name = BentoText.Make("", BentoTextStyle.BodyStrong);
            Summary = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Secondary);
            var names = Bento.VStack(0, _name, Summary);
            names.VerticalAlignment = VerticalAlignment.Center;
            _memory = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Tertiary);
            _setDefault = setDefault;
            _trailing = Bento.HStack(BentoSpace.S8, _memory);
            var grid = Bento.Row(BentoSpace.S12, _dot, names, _trailing);
            _button = new Pressable(PressableKind.Fill, BentoTone.Surface, BentoRadius.Md)
            {
                Height = 58,
                Padding = new Thickness(BentoSpace.S16, 0, BentoSpace.S14, 0),
                InnerContent = grid,
                HorizontalAlignment = HorizontalAlignment.Stretch,
            };
            _button.Click += (_, _) => select();
            Element = new Border
            {
                CornerRadius = new CornerRadius(BentoRadius.Md),
                BorderThickness = new Thickness(BentoMetric.SelectionStroke),
                Child = _button,
            };
        }

        /// 按最新状态改各处；等待重试时返回每秒重算摘要的函数。
        public Func<string>? Update(McpServer m, bool selected, List<string> usedBy, bool canManage)
        {
            _name.Text = m.Name;
            _name.Foreground = (m.State == McpStateKind.Stopped ? BentoColor.Ink.Tertiary : BentoColor.Ink.Primary).Brush();
            Summary.Text = McpsPage.Summary(m, usedBy);
            _memory.Text = m.Memory != null ? Format.Bytes(m.Memory) : "";
            _memory.Visibility = m.Memory != null ? Visibility.Visible : Visibility.Collapsed;
            var status = BentoStatusExt.Of(m.State);
            if (_status != status)
            {
                // 状态点只在状态变了时换（busy 的点带闪动动画，重建会打断它）
                _status = status;
                _dot.Children.Clear();
                _dot.Children.Add(Bento.StatusDot(status));
            }
            if (_switch == null)
            {
                _switch = new BentoSwitch(m.InDefault);
                _switch.Toggled += _setDefault;
                _trailing.Children.Add(_switch);
            }
            else if (_switch.IsOn != m.InDefault) _switch.IsOn = m.InDefault;
            _switch.IsEnabled = canManage;
            ToolTipService.SetToolTip(_switch, $"{m.Name} 加入默认服务");
            Element.BorderBrush = (selected ? BentoColor.Ink.Black : Microsoft.UI.Colors.Transparent).Brush();
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_button, $"{m.Name}，{Format.StateLabel(m.State)}");
            return m.State == McpStateKind.Backoff ? () => McpsPage.Summary(m, usedBy) : null;
        }
    }

    // MARK: 添加 MCP

    /// 添加 MCP 的弹窗表单。提交成功才关闭并选中新加的 MCP；失败原因用 toast 提示，表单保持打开方便改。
    public async Task AddMcpDialog()
    {
        var draft = new McpDraft();
        await BentoKit.ShowDialog(XamlRoot, 460, close =>
        {
            var (nameBox, name) = BentoKit.Field("字母、数字、- 和 _");
            var (targetBox, target) = BentoKit.Field(draft.Kind.TargetPrompt());
            var (argsBox, args) = BentoKit.Field("可选，空格分开");
            var (extraBox, extra) = BentoKit.Field(draft.Kind.ExtraPrompt(), multiline: true);
            extraBox.Height = 100;
            var targetLabel = BentoKit.Section(draft.Kind.TargetLabel());
            var extraLabel = BentoKit.Section(draft.Kind.ExtraLabel());
            var kinds = new SegmentedPills<McpKind>(Enum.GetValues<McpKind>(), draft.Kind, k => k.Label());
            kinds.SelectionChanged += k =>
            {
                draft.Kind = k;
                targetLabel.Text = k.TargetLabel();
                target.PlaceholderText = k.TargetPrompt();
                extraLabel.Text = k.ExtraLabel();
                extra.PlaceholderText = k.ExtraPrompt();
                // 每种类型都是同样几栏，切换类型时弹窗高度不变：HTTP 不用参数，这一栏留着但置灰
                args.IsEnabled = k != McpKind.Http;
                args.PlaceholderText = k == McpKind.Http ? "HTTP 类型不用参数" : "可选，空格分开";
                argsBox.Opacity = k == McpKind.Http ? 0.4 : 1;
            };
            var sw = new BentoSwitch(true);
            sw.Toggled += on => draft.InDefault = on;
            var defaultRow = Bento.Row(BentoSpace.S12,
                Bento.VStack(BentoSpace.S2, BentoText.Make("加入默认服务", BentoTextStyle.BodyStrong), BentoText.Make("连在默认地址 /mcp 上的客户端都能用到它", BentoTextStyle.Label, BentoColor.Ink.Secondary)),
                null, sw);
            Pressable? submit = null;
            async void Submit()
            {
                draft.Name = name.Text;
                draft.Target = target.Text;
                draft.Args = args.IsEnabled ? args.Text : "";
                draft.Extra = extra.Text;
                submit!.IsEnabled = false;
                var ok = await _store.AddMcp(draft);
                submit.IsEnabled = true;
                if (!ok) return;
                _search.Text = "";
                _nav.SelectMcp(draft.Name.Trim(), Navigator.McpTab.Overview);
                close();
            }
            submit = Bento.Button("添加", null, BentoTone.InkTone, Submit);
            var buttons = Bento.HStack(BentoSpace.S8, Bento.Button("取消", null, BentoTone.Panel, close), submit);
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            name.Loaded += (_, _) => name.Focus(FocusState.Programmatic);
            return Bento.VStack(BentoSpace.S14,
                BentoText.Make("添加 MCP", BentoTextStyle.Title),
                kinds,
                BentoKit.Labeled("名字", nameBox),
                Bento.VStack(BentoSpace.S6, targetLabel, targetBox),
                BentoKit.Labeled("参数", argsBox),
                Bento.VStack(BentoSpace.S6, extraLabel, extraBox),
                defaultRow,
                buttons);
        });
    }

    // MARK: 试调用

    /// 试调用一个工具的弹窗：填参数（JSON）→ 调用 → 看返回内容。每次调用都会记进调用记录。
    public Task ToolCallDialog(string mcp, ToolInfo tool) => BentoKit.ShowDialog(XamlRoot, 560, close =>
    {
        var (argsBox, args) = BentoKit.Field("{}", multiline: true);
        argsBox.Height = 132;
        args.Text = Template(tool.InputSchema);
        var result = BentoKit.Wrap("点「调用」后在这里显示返回内容", BentoTextStyle.Mono, BentoColor.Ink.Secondary, selectable: true);
        var resultTitle = BentoKit.Section("结果");
        Pressable? run = null;
        async void Run()
        {
            run!.IsEnabled = false;
            result.Text = "正在调用…";
            result.Foreground = BentoColor.Ink.Secondary.Brush();
            var r = await _store.CallTool(mcp, tool.Name, args.Text);
            run.IsEnabled = true;
            if (r is not { } v) { result.Text = "没有结果"; return; }
            result.Text = v.Text.Length == 0 ? "（没有文字内容）" : v.Text;
            result.Foreground = (v.IsError ? BentoTone.Rose.Ink : BentoColor.Ink.Primary).Brush();
            resultTitle.Text = $"结果 · {(v.IsError ? "出错" : "成功")} · {v.Ms} ms";
        }
        run = Bento.Button("调用", null, BentoTone.InkTone, Run);
        args.KeyDown += (_, e) =>
        {
            var ctrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            if (ctrl && e.Key == Windows.System.VirtualKey.Enter) { e.Handled = true; Run(); }
        };
        var footer = Bento.Row(BentoSpace.S8, BentoText.Make("每次调用都会记进「调用记录」· Ctrl+Enter 调用", BentoTextStyle.Label, BentoColor.Ink.Tertiary), null,
            Bento.HStack(BentoSpace.S8, Bento.Button("关闭", null, BentoTone.Panel, close), run));
        var head = Bento.VStack(BentoSpace.S2, BentoKit.Section("试调用"), BentoText.Make($"{mcp} · {tool.Name}", BentoTextStyle.Title));
        if (tool.Summary.Length > 0) head.Children.Add(BentoKit.Wrap(tool.Summary, BentoTextStyle.Label, BentoColor.Ink.Secondary));
        var stack = Bento.VStack(BentoSpace.S14, head, BentoKit.Labeled("参数（JSON）", argsBox));
        if (tool.InputSchema != null) stack.Children.Add(BentoKit.Labeled("参数说明", Box(BentoKit.Wrap(tool.InputSchema, BentoTextStyle.Mono, BentoColor.Ink.Secondary, true), 96)));
        stack.Children.Add(Bento.VStack(BentoSpace.S6, resultTitle, Box(result, 160)));
        stack.Children.Add(footer);
        return stack;
    });

    /// 只读的等宽文字框，可以选中复制，内容多了在框里滚动。
    private static Border Box(UIElement content, double height) => new()
    {
        Height = height,
        Background = BentoColor.Bg.Panel.Brush(),
        CornerRadius = new CornerRadius(BentoRadius.Md),
        Child = new ScrollViewer { Content = content, Padding = new Thickness(BentoSpace.S10) },
    };

    /// 按 inputSchema 生成参数模板：只列必填项，按类型填空值（有 default 就用 default）。
    public static string Template(string? schema)
    {
        try
        {
            if (schema == null || JsonNode.Parse(schema) is not JsonObject obj || obj["properties"] is not JsonObject props) return "{}";
            var outObj = new JsonObject();
            foreach (var key in (obj["required"] as JsonArray ?? []).Select(x => x?.ToString() ?? ""))
            {
                var p = props[key] as JsonObject ?? new JsonObject();
                if (p["default"] is { } d) { outObj[key] = d.DeepClone(); continue; }
                outObj[key] = p["type"]?.ToString() switch
                {
                    "string" => "",
                    "integer" or "number" => 0,
                    "boolean" => false,
                    "array" => new JsonArray(),
                    "object" => new JsonObject(),
                    _ => null,
                };
            }
            return outObj.Count == 0 ? "{}" : outObj.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
        }
        catch { return "{}"; }
    }
}

/// MCP 详情：名字和操作、页签、页签内容。所有页签一开始就建好、一直留着，切换只是换哪个显示。
internal sealed class McpDetail : Grid
{
    private static readonly Navigator.McpTab[] Tabs = Enum.GetValues<Navigator.McpTab>();

    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly McpsPage _page;
    private readonly Grid _header = new() { Height = 40 };
    private readonly SegmentedPills<Navigator.McpTab> _tabs;
    private readonly Dictionary<Navigator.McpTab, ContentControl> _hosts = [];
    private readonly CallTable _calls;
    private readonly FrameworkElement _empty;
    private readonly Grid _body = new() { RowSpacing = BentoSpace.S16, Padding = new Thickness(BentoSpace.S20) };
    private readonly DispatcherTimer _ticker = new() { Interval = TimeSpan.FromSeconds(1) };
    private string _toolsKey = "";
    private Action? _tick;
    /// 上次建页签内容时的 MCP 对象和端口。内核只在这个 MCP 自己变了时推一个新对象，没变就不重建，
    /// 免得点开的密钥被打回码、滚动位置丢掉。
    private McpServer? _renderedMcp;
    private int _renderedPort;
    // 运行数据卡里每 5 秒要更新的几处
    private TextBlock? _memoryText, _uptimeText;
    private Grid? _sparkHost;

    public McpDetail(AppStore store, Navigator nav, McpsPage page)
    {
        _store = store;
        _nav = nav;
        _page = page;
        _tabs = new SegmentedPills<Navigator.McpTab>(Tabs, nav.CurrentMcpTab, TabTitle);
        _tabs.SelectionChanged += t => nav.SetMcpTab(t);
        _calls = new CallTable(store, c => c.Mcp == _nav.SelectedMcp, showsMcp: false);

        _body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _body.RowDefinitions.Add(new RowDefinition());
        _body.Children.Add(_header);
        SetRow(_tabs, 1);
        _body.Children.Add(_tabs);
        var stack = new Grid();
        foreach (var t in Tabs)
        {
            var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
            _hosts[t] = host;
            stack.Children.Add(host);
        }
        _hosts[Navigator.McpTab.Calls].Content = _calls;
        SetRow(stack, 2);
        _body.Children.Add(stack);
        Children.Add(_body);
        _empty = BentoKit.Empty(BentoIcon.Mcps, "在左边选一个 MCP");
        _empty.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(_empty);

        store.MemoryChanged += UpdateMemory;
        store.CoreChanged += Render;
        store.BusyChanged += RenderHeader;
        _ticker.Tick += (_, _) => _tick?.Invoke();
        Loaded += (_, _) => _ticker.Start();
        Unloaded += (_, _) => _ticker.Stop();
    }

    private string TabTitle(Navigator.McpTab t)
    {
        var m = _store.Mcp(_nav.SelectedMcp);
        return t switch
        {
            Navigator.McpTab.Overview => "概况",
            Navigator.McpTab.Tools => $"工具 · {m?.ToolCount ?? 0}",
            Navigator.McpTab.Resources => $"Resources · {m?.ResourceCount ?? 0}",
            Navigator.McpTab.Logs => "日志",
            _ => "调用",
        };
    }

    private string? _shownMcp;

    public void Render()
    {
        var m = _store.Mcp(_nav.SelectedMcp);
        _body.Visibility = m == null ? Visibility.Collapsed : Visibility.Visible;
        _empty.Visibility = m == null ? Visibility.Visible : Visibility.Collapsed;
        if (m == null) return;
        _tabs.Select(_nav.CurrentMcpTab);
        foreach (var t in Tabs)
        {
            _tabs.SetTitle(t, TabTitle(t));
            _hosts[t].Visibility = t == _nav.CurrentMcpTab ? Visibility.Visible : Visibility.Collapsed;
        }
        RenderHeader();
        var port = _store.Core?.Port ?? 0;
        if (!ReferenceEquals(m, _renderedMcp) || port != _renderedPort)
        {
            _renderedMcp = m;
            _renderedPort = port;
            _tick = null;
            _memoryText = _uptimeText = null;
            _sparkHost = null;
            _hosts[Navigator.McpTab.Overview].Content = OverviewTab(m);
            _hosts[Navigator.McpTab.Resources].Content = ResourcesTab(m);
            _hosts[Navigator.McpTab.Logs].Content = BentoKit.LogBlock($"stderr（最近 {m.Log.Count} 行）", m.Log, fillsHeight: true);
        }
        // 工具列表只在工具变了时重建，免得每次状态推送都把滚动位置丢掉
        var toolsKey = m.Name + "|" + string.Join(",", m.Tools.Select(t => t.Name));
        if (toolsKey != _toolsKey)
        {
            _toolsKey = toolsKey;
            _hosts[Navigator.McpTab.Tools].Content = ToolsTab(m);
        }
        if (_shownMcp != m.Name)
        {
            _shownMcp = m.Name;
            _calls.Reload();
        }
    }

    /// 每 5 秒一次内存采样：只改运行数据卡里的内存、趋势线和运行时长。
    private void UpdateMemory()
    {
        if (_store.Mcp(_nav.SelectedMcp) is not { } m || _memoryText == null) return;
        _memoryText.Text = Format.Bytes(m.Memory);
        if (_uptimeText != null && m.StartedAt is { } s) _uptimeText.Text = Format.Uptime(s);
        if (_sparkHost != null)
        {
            _sparkHost.Children.Clear();
            if (m.MemoryHistory.Count > 1) _sparkHost.Children.Add(BentoKit.Sparkline(m.MemoryHistory, BentoTone.Mint.Ink));
        }
    }

    /// 名字、状态药丸、当前状态下能做的那个操作。
    private void RenderHeader()
    {
        var m = _store.Mcp(_nav.SelectedMcp);
        _header.Children.Clear();
        if (m == null) return;
        var status = BentoStatusExt.Of(m.State);
        var title = BentoText.Make(m.Name, BentoTextStyle.Headline, BentoColor.Ink.Black);
        UIElement? action = null;
        if (m.State != McpStateKind.Stopped)
        {
            var retry = m.State == McpStateKind.Backoff;
            var key = retry ? $"retry:{m.Name}" : $"restart:{m.Name}";
            var b = Bento.Button(retry ? "立即重试" : "重启", BentoIcon.Restart, BentoTone.InkTone,
                () => { if (retry) _store.RetryNow(m.Name); else _store.Restart(m.Name); });
            b.IsEnabled = !_store.IsBusy(key) && m.State != McpStateKind.Starting && _store.Core?.CanManage == true;
            action = b;
        }
        _header.Children.Add(Bento.Row(BentoSpace.S12, Bento.HStack(BentoSpace.S12, title, Bento.Pill(Format.StateLabel(m.State), status.Tone(), status)), null, action));
    }

    // MARK: 概况

    private UIElement OverviewTab(McpServer m)
    {
        var stack = Bento.VStack(BentoSpace.S12, StateCard(m), DefinitionCard(m));
        var tail = m.Log.TakeLast(6).ToList();
        stack.Children.Add(BentoKit.LogBlock(tail.Count == 0 ? "最近日志（stderr）" : $"最近日志（stderr 最后 {tail.Count} 行）", tail));
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }

    /// 按状态换内容的那张卡片：等待重试（带倒计时）、配置错误、启动中、已停止、正常运行。
    private UIElement StateCard(McpServer m)
    {
        var othersHealthy = _store.HealthyCount - (m.IsHealthy ? 1 : 0);
        switch (m.State)
        {
            case McpStateKind.Backoff:
                var title = BentoText.Make("", BentoTextStyle.Title);
                void Tick()
                {
                    var s = m.RetryAt is { } at ? Math.Max(0, (int)Math.Ceiling((at - DateTimeOffset.Now).TotalSeconds)) : 0;
                    title.Text = s > 0 ? $"连不上上游，{s} 秒后自动重试（已重试 {m.Attempts} 次）" : $"正在重试…（已重试 {m.Attempts} 次）";
                }
                Tick();
                _tick = Tick;
                var msg = new List<UIElement> { BentoKit.Wrap(m.Error, BentoTextStyle.Body, BentoTone.Peach.Ink, true) };
                if (othersHealthy > 0) msg.Add(BentoText.Make($"其他 {othersHealthy} 个 MCP 不受影响", BentoTextStyle.Label, BentoTone.Peach.Ink));
                return BentoKit.Alert(BentoTone.Peach, BentoIcon.Warning, title, msg);
            case McpStateKind.ConfigError:
                return BentoKit.Alert(BentoTone.Rose, BentoIcon.Warning, BentoText.Make("配置有问题，没有启动", BentoTextStyle.Title),
                    [BentoKit.Wrap(m.Error, BentoTextStyle.Body, BentoTone.Rose.Ink, true)]);
            case McpStateKind.Starting:
                return BentoKit.Alert(BentoTone.Sky, BentoIcon.Clock, BentoText.Make("正在启动…", BentoTextStyle.Title),
                    [BentoKit.Wrap("握手完成后就能用了。", BentoTextStyle.Body, BentoTone.Sky.Ink)]);
            case McpStateKind.Stopped:
                return BentoKit.Alert(BentoTone.Sunken, BentoIcon.Info, BentoText.Make("没有在运行", BentoTextStyle.Title),
                    [BentoKit.Wrap("没有任何服务用到它，所以没启动。打开左边的开关（加入默认服务），或者把它加进某个服务，它就会启动。", BentoTextStyle.Body, BentoTone.Sunken.Ink)]);
            default:
                return RuntimeCard(m);
        }
    }

    /// 正常运行时的几项运行数据；内存带最近一段的趋势线。
    private UIElement RuntimeCard(McpServer m)
    {
        var tone = BentoTone.Mint;
        var g = new Grid { ColumnSpacing = BentoSpace.S12 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        for (var i = 0; i < 4; i++) g.ColumnDefinitions.Add(new ColumnDefinition());
        g.Children.Add(Bento.IconCircleOn(BentoIcon.Check, tone));
        var uptime = _uptimeText = BentoText.Make(m.StartedAt is { } s ? Format.Uptime(s) : "—", BentoTextStyle.BodyStrong);
        _memoryText = BentoText.Make(Format.Bytes(m.Memory), BentoTextStyle.BodyStrong);
        _sparkHost = new Grid();
        if (m.MemoryHistory.Count > 1) _sparkHost.Children.Add(BentoKit.Sparkline(m.MemoryHistory, tone.Ink));
        var memory = Bento.HStack(BentoSpace.S8, _memoryText, _sparkHost);
        var facts = new (string, UIElement)[]
        {
            ("进程", BentoText.Make(m.Pid is { } pid ? $"pid {pid}" : "无本地进程", BentoTextStyle.BodyStrong)),
            ("已运行", uptime),
            ("重启次数", BentoText.Make($"{m.Restarts} 次", BentoTextStyle.BodyStrong)),
            ("内存", memory),
        };
        for (var i = 0; i < facts.Length; i++)
        {
            var f = Bento.VStack(0, BentoKit.Section(facts[i].Item1, tone.Ink), facts[i].Item2);
            SetColumn(f, i + 1);
            g.Children.Add(f);
        }
        return Bento.Card(g, tone, BentoRadius.Xl);
    }

    private UIElement DefinitionCard(McpServer m)
    {
        var s = Bento.VStack(0, BentoKit.Section("定义"));
        ((FrameworkElement)s.Children[0]).Margin = new Thickness(0, 0, 0, BentoSpace.S4);
        s.Children.Add(BentoKit.KeyValue("类型", m.Kind.Label()));
        foreach (var f in m.Definition)
            s.Children.Add(f.Secret ? BentoKit.SecretRow(f.Key, f.Value) : BentoKit.KeyValue(f.Key, f.Value, f.Monospaced));
        var usedBy = _store.UsedBy(m);
        s.Children.Add(BentoKit.KeyValue("用到它的服务", usedBy.Count == 0 ? "没有" : string.Join("、", usedBy)));
        if (_store.Core is { } core)
        {
            var url = $"http://127.0.0.1:{core.Port}/servers/{m.Name}/mcp";
            s.Children.Add(BentoKit.KeyValue("单独地址", BentoKit.Wrap(url, BentoTextStyle.Mono, selectable: true), BentoKit.CopyButton(() => url, "复制单独地址")));
        }
        return Bento.Card(s);
    }

    // MARK: 工具

    private const string ToolRowTemplate =
        "<DataTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><Grid Height='36' Background='Transparent' /></DataTemplate>";

    /// 「工具」：名字 + 一句话说明。双击一行或右键「试调用…」，可以直接调一次这个工具。
    private UIElement ToolsTab(McpServer m) => ToolList(m.Tools.Select(t => (t.Name, t.Summary, (ToolInfo?)t)).ToList(), 260,
        t => _ = _page.ToolCallDialog(m.Name, t), "还没拿到工具列表");

    /// 工具列表（放在白卡片里的原生列表）。MCP 详情和服务的「聚合后的工具」共用。
    public static UIElement ToolList(List<(string Name, string Summary, ToolInfo? Tool)> rows, double nameWidth, Action<ToolInfo>? onTry, string emptyText)
    {
        if (rows.Count == 0) return Bento.Card(BentoKit.Empty(BentoIcon.Tools, emptyText));
        var list = new ListView
        {
            SelectionMode = ListViewSelectionMode.None,
            ItemContainerStyle = (Style)Application.Current.Resources["BentoListRow"],
            ItemTemplate = (DataTemplate)XamlReader.Load(ToolRowTemplate),
            Padding = new Thickness(BentoSpace.S8, BentoSpace.S8, BentoSpace.S8, BentoSpace.S8),
            ItemsSource = rows.Select((r, i) => i).ToList(),
        };
        foreach (var key in new[] { "ListViewItemBackgroundPointerOver", "ListViewItemBackgroundPressed" })
            list.Resources[key] = BentoColor.Bg.Panel.Brush();
        list.ContainerContentChanging += (_, args) =>
        {
            if (args.InRecycleQueue || args.ItemContainer.ContentTemplateRoot is not Grid g || args.Item is not int i) return;
            var r = rows[i];
            if (g.Children.Count == 0)
            {
                g.ColumnSpacing = BentoSpace.S16;
                g.Padding = new Thickness(BentoSpace.S12, 0, BentoSpace.S12, 0);
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(nameWidth) });
                g.ColumnDefinitions.Add(new ColumnDefinition());
                g.Children.Add(BentoText.Make("", BentoTextStyle.Mono));
                var sum = BentoText.Make("", BentoTextStyle.Body, BentoColor.Ink.Secondary);
                SetColumn(sum, 1);
                g.Children.Add(sum);
            }
            ((TextBlock)g.Children[0]).Text = r.Name;
            ((TextBlock)g.Children[1]).Text = r.Summary;
            ToolTipService.SetToolTip(g, string.IsNullOrEmpty(r.Summary) ? r.Name : $"{r.Name}\n{r.Summary}");
            g.Tag = i;
            g.DoubleTapped -= OnDoubleTapped;
            g.DoubleTapped += OnDoubleTapped;
            var menu = new MenuFlyout();
            if (onTry != null && r.Tool != null)
            {
                var tryItem = new MenuFlyoutItem { Text = "试调用…", Icon = new FontIcon { Glyph = BentoIcon.Calls } };
                tryItem.Click += (_, _) => onTry(r.Tool);
                menu.Items.Add(tryItem);
            }
            var copy = new MenuFlyoutItem { Text = "拷贝工具名", Icon = new FontIcon { Glyph = BentoIcon.Copy } };
            copy.Click += (_, _) => { var p = new DataPackage(); p.SetText(r.Name); Clipboard.SetContent(p); };
            menu.Items.Add(copy);
            g.ContextFlyout = menu;
        };
        void OnDoubleTapped(object s, Microsoft.UI.Xaml.Input.DoubleTappedRoutedEventArgs e)
        {
            if (s is Grid { Tag: int i } && rows[i].Tool is { } t) onTry?.Invoke(t);
        }
        var card = Bento.Card(list, padding: 0);
        card.VerticalAlignment = VerticalAlignment.Stretch;
        return card;
    }

    // MARK: Resources

    private static UIElement ResourcesTab(McpServer m)
    {
        var s = Bento.VStack(0, BentoKit.Section("除了工具，它还提供"),
            BentoKit.KeyValue("Resources", $"{m.ResourceCount} 个"),
            BentoKit.KeyValue("Prompts", $"{m.PromptCount} 个"),
            BentoKit.KeyValue("使用说明", m.InstructionsLength > 0 ? $"{Format.Count(m.InstructionsLength)} 字" : "没有"));
        ((FrameworkElement)s.Children[0]).Margin = new Thickness(0, 0, 0, BentoSpace.S4);
        var stack = Bento.VStack(BentoSpace.S12, Bento.Card(s),
            BentoKit.Note("说明", $"聚合进服务时：resources 的 URI 保持原样，prompts 的名字加上「{m.Name}__」前缀，使用说明前面加「## {m.Name}」小标题后拼在一起。", BentoTone.Surface));
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }
}
