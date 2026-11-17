using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.Views;

/// 服务页：左边服务卡片，右边选中那个的详情。对应 Mac 端 ThemeBento/Pages/Services/。
public sealed class ServicesPage : Grid
{
    private enum Client { ClaudeCode, Docker, Json }

    private static readonly Navigator.ServiceTab[] Tabs = Enum.GetValues<Navigator.ServiceTab>();

    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly StackPanel _list = Bento.VStack(BentoSpace.S10);
    private readonly Pressable _create;
    private readonly Grid _header = new() { Height = 40 };
    private readonly SegmentedPills<Navigator.ServiceTab> _tabs;
    private readonly Dictionary<Navigator.ServiceTab, ContentControl> _hosts = [];
    private readonly CallTable _calls;
    private readonly Grid _body = new() { RowSpacing = BentoSpace.S16, Padding = new Thickness(BentoSpace.S20) };
    private readonly FrameworkElement _empty;
    private Client _client = Client.ClaudeCode;
    private string? _shown;

    public ServicesPage(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);
        ColumnSpacing = BentoSpace.S16;
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(296) });
        ColumnDefinitions.Add(new ColumnDefinition());

        // 左栏
        _create = Bento.Button("新建服务", BentoIcon.Add, BentoTone.InkTone, () => _ = BentoKit.AskName(XamlRoot, "新建服务", "创建", "", async name =>
        {
            var ok = await _store.CreateService(name);
            if (ok) _nav.SelectService(name);
            return ok;
        }), small: true);
        var header = Bento.Row(BentoSpace.S8, BentoText.Make("服务", BentoTextStyle.Headline, BentoColor.Ink.Black), null, _create);
        header.Height = 40;
        // 卡片悬停的投影会画到卡片外面，ScrollViewer 会按视口裁掉：列表四周留出 12 的空，再用负外边距把位置抵回去
        _list.Padding = new Thickness(BentoSpace.S12, BentoSpace.S12, BentoSpace.S12, BentoSpace.S12);
        var scroll = new ScrollViewer
        {
            Content = _list,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            Margin = new Thickness(-BentoSpace.S12, -BentoSpace.S12, -BentoSpace.S12, 0),
        };
        var left = new Grid { RowSpacing = BentoSpace.S12 };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition());
        left.Children.Add(header);
        SetRow(scroll, 1);
        left.Children.Add(scroll);
        Children.Add(left);

        // 右栏
        _tabs = new SegmentedPills<Navigator.ServiceTab>(Tabs, nav.CurrentServiceTab, TabTitle);
        _tabs.SelectionChanged += t => nav.SetServiceTab(t);
        _calls = new CallTable(store, c => c.Service == _nav.SelectedService, showsService: false);
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
        _hosts[Navigator.ServiceTab.Calls].Content = _calls;
        SetRow(stack, 2);
        _body.Children.Add(stack);
        var detail = new Grid();
        detail.Children.Add(_body);
        _empty = BentoKit.Empty(BentoIcon.Services, "在左边选一个服务");
        _empty.VerticalAlignment = VerticalAlignment.Center;
        detail.Children.Add(_empty);
        var panel = Bento.Panel(detail);
        SetColumn(panel, 1);
        Children.Add(panel);

        store.ServicesChanged += Render;
        store.McpsChanged += Render;
        store.CoreChanged += Render;
        nav.SelectionChanged += Render;
        Render();
    }

    private ServiceSummary? Selected => _store.Services.FirstOrDefault(s => s.Name == _nav.SelectedService);

    private string TabTitle(Navigator.ServiceTab t) => t switch
    {
        Navigator.ServiceTab.Members => "组成",
        Navigator.ServiceTab.Tools => $"聚合后的工具 · {Selected?.ToolCount ?? 0}",
        Navigator.ServiceTab.Instructions => "合并后的说明",
        _ => "调用",
    };

    private void Render()
    {
        var services = _store.Services;
        var tones = new BentoServiceTones(services);
        var canManage = _store.Core?.CanManage == true;
        _create.IsEnabled = canManage;

        _list.Children.Clear();
        foreach (var s in services) _list.Children.Add(Card(s, tones[s.Name], s.Name == _nav.SelectedService));
        var foot = BentoKit.Wrap("每个 MCP 也有自己的单独地址 /servers/<名字>/mcp（工具名不加前缀）", BentoTextStyle.Label, BentoColor.Ink.Tertiary);
        foot.Margin = new Thickness(0, BentoSpace.S2, 0, 0);
        _list.Children.Add(foot);

        var sel = Selected;
        _body.Visibility = sel == null ? Visibility.Collapsed : Visibility.Visible;
        _empty.Visibility = sel == null ? Visibility.Visible : Visibility.Collapsed;
        if (sel == null) return;
        _tabs.Select(_nav.CurrentServiceTab);
        foreach (var t in Tabs)
        {
            _tabs.SetTitle(t, TabTitle(t));
            _hosts[t].Visibility = t == _nav.CurrentServiceTab ? Visibility.Visible : Visibility.Collapsed;
        }
        RenderHeader(sel, canManage);
        _hosts[Navigator.ServiceTab.Members].Content = MembersTab(sel, canManage);
        _hosts[Navigator.ServiceTab.Tools].Content = McpDetail.ToolList(
            sel.Members.SelectMany(m => m.Tools.Select(t => ($"{m.Name}__{t.Name}", t.Summary, (ToolInfo?)null))).ToList(), 340, null, "这个服务里还没有工具");
        _hosts[Navigator.ServiceTab.Instructions].Content = InstructionsTab(sel);
        if (_shown != sel.Name)
        {
            _shown = sel.Name;
            _calls.Reload();
        }
    }

    /// 服务卡片：图标、地址、会话数；名字；几个 MCP · 多少工具；健康状况。
    private UIElement Card(ServiceSummary s, BentoTone tone, bool selected)
    {
        var health = Health(s);
        var top = Bento.Row(BentoSpace.S8, Bento.IconCircleOn(BentoCatalog.Icon(s), tone), BentoText.Make(s.Path, BentoTextStyle.Mono, tone.Ink), Bento.Pill($"{s.Sessions} 个会话"));
        var name = BentoText.Make(s.Name, BentoTextStyle.Title);
        name.Margin = new Thickness(0, BentoSpace.S20, 0, 0);
        var counts = BentoText.Make($"{s.Members.Count} 个 MCP · {s.ToolCount} 工具", BentoTextStyle.Label, tone.Ink);
        var healthRow = Bento.HStack(BentoSpace.S6, Bento.StatusDot(health.Status),
            BentoText.Make(s.IsDefault ? $"= 所有开关打开的 MCP · {health.Text}" : health.Text, BentoTextStyle.Label, tone.Ink));
        healthRow.Margin = new Thickness(0, BentoSpace.S20, 0, 0);
        var card = Bento.Card(Bento.VStack(0, top, name, counts, healthRow), tone, BentoRadius.Xl, BentoSpace.S16);
        card.BorderBrush = (selected ? BentoColor.Ink.Black : Microsoft.UI.Colors.Transparent).Brush();
        card.BorderThickness = new Thickness(BentoMetric.SelectionStroke);
        // 底色铺到描边下面：没选中时描边透明，不然会露出一圈底色
        card.BackgroundSizing = BackgroundSizing.OuterBorderEdge;
        var b = new Pressable(PressableKind.Card, radius: BentoRadius.Xl) { InnerContent = card };
        b.Click += (_, _) => _nav.SelectService(s.Name);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, $"服务 {s.Name}");
        return b;
    }

    /// 服务的健康状况：「3 个都正常」/「1 个不正常」/「还没有 MCP」。
    private static (string Text, BentoStatus Status) Health(ServiceSummary s)
    {
        var n = s.Members.Count;
        if (n == 0) return ("还没有 MCP", BentoStatus.Idle);
        return s.Healthy == n ? ($"{n} 个都正常", BentoStatus.Ok) : ($"{n - s.Healthy} 个不正常", BentoStatus.Warn);
    }

    private void RenderHeader(ServiceSummary s, bool canManage)
    {
        _header.Children.Clear();
        var health = Health(s);
        var title = Bento.HStack(BentoSpace.S12, BentoText.Make(s.Name, BentoTextStyle.Headline, BentoColor.Ink.Black), Bento.Pill(health.Text, health.Status.Tone(), health.Status));
        StackPanel? actions = null;
        if (!s.IsDefault)
        {
            var rename = Bento.Button("重命名", BentoIcon.Edit, BentoTone.Surface, () => _ = BentoKit.AskName(XamlRoot, $"重命名「{s.Name}」", "保存", s.Name, async newName =>
            {
                var ok = await _store.RenameService(s.Name, newName);
                if (ok) _nav.SelectService(newName);
                return ok;
            }));
            var delete = Bento.Button("删除", BentoIcon.Delete, BentoTone.Rose, async () =>
            {
                if (!await BentoKit.Confirm(XamlRoot, $"删除服务「{s.Name}」？", $"地址 {s.Path} 会失效；里面的 MCP 本身不会被删。", "删除")) return;
                _store.DeleteService(s.Name);
                _nav.SelectService("默认");
            });
            rename.IsEnabled = delete.IsEnabled = canManage;
            actions = Bento.HStack(BentoSpace.S8, rename, delete);
        }
        _header.Children.Add(Bento.Row(BentoSpace.S12, title, null, actions));
    }

    // MARK: 组成

    private UIElement MembersTab(ServiceSummary s, bool canManage)
    {
        var stack = Bento.VStack(BentoSpace.S12, MembersCard(s, canManage));
        if (_store.Core is { } core) stack.Children.Add(ClientConfigCard(s, core.Port));
        stack.Children.Add(ChecksCard(s));
        stack.Children.Add(BentoKit.Note("说明", Note(s), BentoTone.Surface));
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }

    /// 包含的 MCP：两列勾选框。默认服务勾选 = 拨 MCP 的默认开关；命名服务勾选 = 成员。
    private UIElement MembersCard(ServiceSummary s, bool canManage)
    {
        var members = s.Members.Select(m => m.Name).ToHashSet();
        var grid = new Grid { ColumnSpacing = BentoSpace.S16, RowSpacing = BentoSpace.S2 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        for (var i = 0; i < _store.Mcps.Count; i++)
        {
            var m = _store.Mcps[i];
            if (i % 2 == 0) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(32) });
            var isMember = members.Contains(m.Name);
            var label = Bento.HStack(BentoSpace.S8, Bento.StatusDot(BentoStatusExt.Of(m.State)), BentoText.Make(m.Name, BentoTextStyle.Body),
                BentoText.Make(m.ToolCount.ToString(), BentoTextStyle.Body, BentoColor.Ink.Tertiary));
            if (isMember && !m.InDefault) label.Children.Add(Bento.Pill("默认已关", BentoTone.Panel));
            var name = m.Name;
            var box = BentoKit.Checkbox(isMember, label, on =>
            {
                if (s.IsDefault) _store.SetDefault(name, on);
                else _store.ToggleMember(name, s.Name);
            });
            box.IsEnabled = canManage;
            box.VerticalAlignment = VerticalAlignment.Center;
            SetRow(box, i / 2);
            SetColumn(box, i % 2);
            grid.Children.Add(box);
        }
        var title = BentoKit.Section(s.IsDefault ? "包含的 MCP（= 所有开关打开的 MCP）" : "包含的 MCP（勾选即生效，不受“默认服务”开关影响）");
        return Bento.Card(Bento.VStack(BentoSpace.S8, title, grid));
    }

    /// 客户端配置：Claude Code 命令 / 容器里 / JSON，一键复制。
    private UIElement ClientConfigCard(ServiceSummary s, int port)
    {
        var command = BentoKit.Wrap("", BentoTextStyle.Mono, selectable: true);
        var hint = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Tertiary);
        void Show()
        {
            command.Text = Command(s, _client, port);
            hint.Text = _client switch
            {
                Client.ClaudeCode => "在本机终端里运行一次即可；地址只监听 127.0.0.1",
                Client.Docker => "容器里用 host.docker.internal 代替 127.0.0.1，换网络不受影响",
                _ => "写进客户端的 MCP 配置文件；容器里把 127.0.0.1 换成 host.docker.internal",
            };
        }
        Show();
        var pills = new SegmentedPills<Client>(Enum.GetValues<Client>(), _client,
            c => c switch { Client.ClaudeCode => "Claude Code", Client.Docker => "Docker 容器里", _ => "JSON 配置" }, BentoColor.Bg.Panel);
        pills.SelectionChanged += c => { _client = c; Show(); };
        var box = new Grid { ColumnSpacing = BentoSpace.S12 };
        box.ColumnDefinitions.Add(new ColumnDefinition());
        box.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        command.MinHeight = 30;
        command.VerticalAlignment = VerticalAlignment.Center;
        box.Children.Add(command);
        var copy = BentoKit.CopyButton(() => command.Text, "复制", BentoTone.InkTone, labeled: true);
        copy.VerticalAlignment = VerticalAlignment.Top;
        SetColumn(copy, 1);
        box.Children.Add(copy);
        var boxed = new Border
        {
            Background = BentoColor.Bg.Panel.Brush(),
            CornerRadius = new CornerRadius(BentoRadius.Md),
            Padding = new Thickness(BentoSpace.S16, BentoSpace.S8, BentoSpace.S8, BentoSpace.S8),
            Child = box,
        };
        return Bento.Card(Bento.VStack(BentoSpace.S12, BentoKit.Section("客户端配置"), pills, boxed, hint));
    }

    private static string Command(ServiceSummary s, Client c, int port)
    {
        var url = $"http://{(c == Client.Docker ? "host.docker.internal" : "127.0.0.1")}:{port}{s.Path}";
        var name = s.IsDefault ? "station" : $"station-{s.Name}";
        return c == Client.Json
            ? $"{{\n  \"mcpServers\": {{\n    \"{name}\": {{ \"type\": \"http\", \"url\": \"{url}\" }}\n  }}\n}}"
            : $"claude mcp add --transport http {name} {url}";
    }

    private static UIElement ChecksCard(ServiceSummary s)
    {
        var longest = s.LongestToolName;
        var health = Health(s);
        UIElement Check(string key, BentoStatus status, string text) =>
            BentoKit.KeyValue(key, Bento.HStack(BentoSpace.S8, Bento.StatusDot(status), BentoText.Make(text, BentoTextStyle.Body)));
        var stack = Bento.VStack(0, BentoKit.Section("检查"),
            Check("工具名", longest <= ServiceSummary.ToolNameLimit ? BentoStatus.Ok : BentoStatus.Error, $"最长 {longest} 字符（上限 {ServiceSummary.ToolNameLimit}）"),
            Check("名字冲突", BentoStatus.Ok, "无（工具名都带 MCP 名前缀）"),
            Check("合并后的说明", BentoStatus.Ok, s.WithInstructions > 0 ? $"{s.WithInstructions} 个 MCP 有说明，共 {Format.Count(s.InstructionsLength)} 字" : "没有 MCP 带说明"),
            Check("MCP 状态", health.Status, health.Text));
        ((FrameworkElement)stack.Children[0]).Margin = new Thickness(0, 0, 0, BentoSpace.S4);
        return Bento.Card(stack);
    }

    private static string Note(ServiceSummary s)
    {
        if (s.IsDefault) return "默认服务 = 所有开关打开的 MCP。在这里勾选，和在 MCP 页拨开关是同一件事。";
        var off = s.Members.Where(m => !m.InDefault).Select(m => m.Name).ToList();
        const string baseText = "开关只管默认服务；命名服务按勾选。";
        return off.Count == 0 ? baseText : baseText + $"{string.Join("、", off)} 的默认开关是关的，但在 {s.Name} 里照样有。";
    }

    // MARK: 合并后的说明

    private static UIElement InstructionsTab(ServiceSummary s)
    {
        var rows = Bento.VStack(0, BentoKit.Section($"拼接顺序（共 {Format.Count(s.InstructionsLength)} 字）"));
        ((FrameworkElement)rows.Children[0]).Margin = new Thickness(0, 0, 0, BentoSpace.S4);
        foreach (var m in s.Members)
        {
            var r = Bento.Row(BentoSpace.S12, BentoText.Make($"## {m.Name}", BentoTextStyle.Mono), null,
                BentoText.Make(m.InstructionsLength > 0 ? $"{Format.Count(m.InstructionsLength)} 字" : "没有说明", BentoTextStyle.Body,
                    m.InstructionsLength > 0 ? BentoColor.Ink.Primary : BentoColor.Ink.Tertiary));
            r.MinHeight = 32;
            rows.Children.Add(r);
        }
        if (s.Members.Count == 0) rows.Children.Add(BentoKit.Empty(BentoIcon.Document, "这个服务里还没有 MCP"));
        var stack = Bento.VStack(BentoSpace.S12, Bento.Card(rows),
            BentoKit.Note("说明", "客户端连上时在 initialize 里拿到这段合并后的说明。如果客户端对长度有上限，后面的会被截掉。", BentoTone.Surface));
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }
}
