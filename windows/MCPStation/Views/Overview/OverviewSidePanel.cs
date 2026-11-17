using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.Views.Overview;

/// 概览右栏，讲「态」：后台服务 → MCP 正不正常 → 需要处理的（有才出现）→ 我的服务。
/// 对应 Mac 端 BentoOverviewSidePanel.swift。
public sealed class OverviewSidePanel : UserControl
{
    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly Grid _coreDot = new();
    private readonly TextBlock _coreHeadline;
    private readonly TextBlock _coreDetail;
    private readonly Border _healthPill = new();
    private readonly StackPanel _attention = Bento.VStack(BentoSpace.S10);
    private readonly StackPanel _services = Bento.VStack(BentoSpace.S10);
    private readonly Pressable _restart;
    private readonly DispatcherTimer _ticker = new() { Interval = TimeSpan.FromSeconds(1) };

    public OverviewSidePanel(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;

        // 顶部：后台服务的大图标、状态、地址和运行时长、重启
        _restart = Bento.IconButton(BentoIcon.Restart, "重启后台服务", () => _store.RestartCore());
        var top = Bento.Row(0,
            Bento.IconButton(BentoIcon.Terminal, "后台服务设置", () => _nav.Current = Navigator.Route.Settings),
            Bento.IconCircle(BentoIcon.Core, BentoMetric.IconCircleLarge, BentoColor.Ink.Black, BentoColor.Ink.Inverse),
            _restart);
        ((FrameworkElement)top.Children[1]).HorizontalAlignment = HorizontalAlignment.Center;
        _coreHeadline = BentoText.Make("", BentoTextStyle.Title);
        var headline = Bento.HStack(BentoSpace.S8, _coreDot, _coreHeadline);
        headline.HorizontalAlignment = HorizontalAlignment.Center;
        _coreDetail = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Secondary);
        _coreDetail.HorizontalAlignment = HorizontalAlignment.Center;
        var header = Bento.VStack(BentoSpace.S6, top, headline, _coreDetail);

        // 「MCP　● 12 / 13 正常 ›」
        var mcpIcon = Bento.IconCircle(BentoIcon.Mcps, BentoSpace.S32, BentoColor.Bg.Panel);
        var chevron = BentoIcon.Make(BentoIcon.ChevronRight, BentoMetric.IconSizeSmall, BentoColor.Ink.Primary);
        var healthRow = Bento.Row(BentoSpace.S10, Bento.HStack(BentoSpace.S10, mcpIcon, BentoText.Make("MCP", BentoTextStyle.BodyStrong)), null,
            Bento.HStack(BentoSpace.S10, _healthPill, chevron));
        var health = new Pressable(PressableKind.Card, BentoTone.Surface, BentoMetric.RailButton / 2)
        {
            Height = BentoMetric.RailButton,
            Padding = new Thickness(BentoSpace.S6, 0, BentoSpace.S14, 0),
            InnerContent = healthRow,
        };
        health.Click += (_, _) =>
        {
            if (_store.Attention.FirstOrDefault() is { } first) _nav.ShowMcp(first.Name);
            else _nav.Current = Navigator.Route.Mcps;
        };
        // Card 类的 Pressable 不铺底色，自己垫一层白
        health.InnerContent = new Border { Background = BentoColor.Bg.Surface.Brush(), CornerRadius = new CornerRadius(BentoMetric.RailButton / 2), Padding = new Thickness(BentoSpace.S6, 0, BentoSpace.S14, 0), Child = healthRow };
        health.Padding = new Thickness(0);

        var stack = Bento.VStack(BentoSpace.S10,
            header,
            health,
            _attention,
            BentoText.Make("我的服务", BentoTextStyle.Body, BentoColor.Ink.Secondary),
            _services);
        stack.Padding = new Thickness(BentoSpace.S16);

        Content = Bento.Panel(new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollMode = ScrollMode.Disabled,
        });

        store.CoreChanged += RenderCore;
        store.BusyChanged += RenderCore;
        store.McpsChanged += RenderMcps;
        store.ServicesChanged += RenderServices;
        // 运行时长、重试倒计时每秒走
        _ticker.Tick += (_, _) => { RenderCoreDetail(); RenderCountdowns(); };
        Loaded += (_, _) => _ticker.Start();
        Unloaded += (_, _) => _ticker.Stop();
        RenderCore();
        RenderMcps();
        RenderServices();
    }

    private void RenderCore()
    {
        var core = _store.Core;
        _coreDot.Children.Clear();
        _coreDot.Children.Add(Bento.StatusDot(BentoStatusExt.Of(core)));
        _coreHeadline.Text = Format.CoreHeadline(core);
        var busy = _store.IsBusy("core-restart") || core?.State == CoreStateKind.Restarting;
        _restart.IsEnabled = !busy;
        ToolTipService.SetToolTip(_restart, core?.RestartTitle ?? "重新检测");
        RenderCoreDetail();
    }

    private void RenderCoreDetail()
    {
        var core = _store.Core;
        _coreDetail.Text = (core != null ? $"127.0.0.1:{core.Port} · " : "") + Format.CoreDetail(core, showsPid: false);
    }

    private readonly List<(TextBlock Text, McpServer Mcp)> _countdowns = [];

    private void RenderMcps()
    {
        var attention = _store.Attention;
        var allOk = attention.Count == 0;
        _healthPill.Child = Bento.Pill($"{_store.HealthyCount} / {_store.ActiveMcps.Count()} 正常", allOk ? BentoTone.Mint : BentoTone.Peach, allOk ? BentoStatus.Ok : BentoStatus.Warn);
        _attention.Children.Clear();
        _countdowns.Clear();
        foreach (var m in attention) _attention.Children.Add(AttentionCard(m));
        _attention.Visibility = attention.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RenderCountdowns()
    {
        foreach (var (text, m) in _countdowns) text.Text = CountdownText(m);
    }

    private static string CountdownText(McpServer m)
    {
        var s = m.RetryAt is { } at ? Math.Max(0, (int)Math.Ceiling((at - DateTimeOffset.Now).TotalSeconds)) : 0;
        return s > 0 ? $"{s} 秒后自动重试 · 已重试 {m.Attempts} 次" : $"正在重试… · 已重试 {m.Attempts} 次";
    }

    /// 需要处理的 MCP：原因、倒计时、「立即重试」「查看详情」。对应 Mac 端 BentoAttentionCard。
    private Border AttentionCard(McpServer m)
    {
        var tone = BentoCatalog.CardTone(m);
        var toggle = new BentoSwitch(m.InDefault);
        toggle.Toggled += on => _store.SetDefault(m.Name, on);
        ToolTipService.SetToolTip(toggle, "加入默认服务");
        var title = BentoText.Make(m.Name, BentoTextStyle.Title, tone.Ink);
        var stack = Bento.VStack(BentoSpace.S10,
            Bento.Row(BentoSpace.S12, Bento.IconCircleOn(BentoIcon.Warning, tone), title, toggle));

        switch (m.State)
        {
            case McpStateKind.Starting:
                stack.Children.Add(BentoText.Make("正在重试…", BentoTextStyle.Body, tone.Ink));
                break;
            case McpStateKind.Backoff:
                var reason = BentoText.Make(m.Error, BentoTextStyle.Body, tone.Ink);
                reason.TextWrapping = TextWrapping.Wrap;
                reason.MaxLines = 4;
                stack.Children.Add(reason);
                var countdown = BentoText.Make(CountdownText(m), BentoTextStyle.Label, tone.Ink);
                _countdowns.Add((countdown, m));
                stack.Children.Add(countdown);
                break;
            case McpStateKind.ConfigError:
                var msg = BentoText.Make(m.Error, BentoTextStyle.Body, tone.Ink);
                msg.TextWrapping = TextWrapping.Wrap;
                stack.Children.Add(msg);
                break;
        }

        var actions = Bento.HStack(BentoSpace.S8);
        var busy = m.State == McpStateKind.Starting || _store.IsBusy($"retry:{m.Name}");
        if (busy || m.State == McpStateKind.Backoff)
        {
            var retry = Bento.Button("立即重试", BentoIcon.Restart, BentoTone.InkTone, () => _store.RetryNow(m.Name), small: true);
            retry.IsEnabled = !busy;
            actions.Children.Add(retry);
        }
        actions.Children.Add(Bento.Button("查看详情", null, BentoTone.Surface, () => _nav.ShowMcp(m.Name), small: true));
        stack.Children.Add(actions);
        return Bento.Card(stack, tone, BentoRadius.Xl);
    }

    private void RenderServices()
    {
        var services = _store.Services;
        var tones = new BentoServiceTones(services);
        _services.Children.Clear();
        foreach (var s in services) _services.Children.Add(ServiceRow(s, tones[s.Name]));
    }

    /// 服务的一行卡片：图标、名字、地址、「几个 MCP · 多少工具」。对应 Mac 端 BentoServiceRow（紧凑版）。
    private Pressable ServiceRow(ServiceSummary s, BentoTone tone)
    {
        var names = Bento.VStack(0,
            BentoText.Make(s.Name, BentoTextStyle.BodyStrong),
            BentoText.Make(s.Path, BentoTextStyle.Mono, tone.Ink));
        names.VerticalAlignment = VerticalAlignment.Center;
        var row = Bento.Row(BentoSpace.S12, Bento.IconCircleOn(BentoCatalog.Icon(s), tone, BentoSpace.S32), names,
            Bento.Pill($"{s.Members.Count} 个 · {s.ToolCount} 工具"));
        var card = Bento.Card(row, tone, BentoRadius.Lg, BentoSpace.S8);
        var b = new Pressable(PressableKind.Card, radius: BentoRadius.Lg) { InnerContent = card };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, $"服务 {s.Name}");
        b.Click += (_, _) => _nav.ShowService(s.Name);
        return b;
    }
}
