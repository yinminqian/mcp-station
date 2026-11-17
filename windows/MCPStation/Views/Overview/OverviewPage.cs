using System.Diagnostics;
using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;

namespace MCPStation.Views;

/// 概览页。后台服务在运行时是「主体 + 右栏」；没运行时整页换成出错说明。对应 Mac 端 BentoOverviewPage.swift。
///
/// 左边的主体讲「量」：调用和内存两张卡并排等高，下面是最近的调用，占满剩下的高度。
/// 「态」（后台服务、MCP 正不正常、需要处理的、服务入口）都在右栏，这里不重复。
public sealed class OverviewPage : Grid
{
    private readonly AppStore _store;
    private readonly Grid _normal = new() { ColumnSpacing = BentoSpace.S20 };
    private readonly ContentControl _down = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };

    public OverviewPage(AppStore store, Navigator nav)
    {
        _store = store;
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);

        var main = new Grid { RowSpacing = BentoSpace.S12 };
        main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        main.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        // 等高：这一排取两张卡里高的那个，矮的由卡片内部拉满
        var cards = new Grid { ColumnSpacing = BentoSpace.S12 };
        cards.ColumnDefinitions.Add(new ColumnDefinition());
        cards.ColumnDefinitions.Add(new ColumnDefinition());
        cards.Children.Add(new Overview.CallChartCard(store, nav));
        var memory = new Overview.MemoryCard(store, nav);
        Grid.SetColumn(memory, 1);
        cards.Children.Add(memory);
        main.Children.Add(cards);
        var table = new CallTable(store, _ => true, showsService: false, limit: 50);
        Grid.SetRow(table, 1);
        main.Children.Add(table);

        _normal.ColumnDefinitions.Add(new ColumnDefinition());
        _normal.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(BentoMetric.SidePanelWidth) });
        _normal.Children.Add(main);
        var side = new Overview.OverviewSidePanel(store, nav);
        Grid.SetColumn(side, 1);
        _normal.Children.Add(side);

        foreach (var e in new FrameworkElement[] { _normal, _down })
            e.OpacityTransition = new ScalarTransition { Duration = TimeSpan.FromMilliseconds(280) };
        Children.Add(_normal);
        Children.Add(_down);

        store.CoreChanged += Render;
        Render();
    }

    private CoreDownReason? _shown;

    private void Render()
    {
        var reason = _store.Core is { State: CoreStateKind.Stopped, Down: { } r } ? r : null;
        _normal.Visibility = reason == null ? Visibility.Visible : Visibility.Collapsed;
        _down.Visibility = reason == null ? Visibility.Collapsed : Visibility.Visible;
        if (reason != null && reason != _shown) _down.Content = CoreDownView(reason);
        _shown = reason;
    }

    /// 管不了的时候：后台服务没在跑 / 配置文件读不了。对应 Mac 端 BentoCoreDownView.swift。
    private UIElement CoreDownView(CoreDownReason reason)
    {
        var detail = BentoText.Make(reason.Detail, BentoTextStyle.Body, BentoTone.Rose.Ink);
        detail.TextWrapping = TextWrapping.Wrap;
        detail.IsTextSelectionEnabled = true;
        var actions = Bento.HStack(BentoSpace.S8,
            Bento.Button(_store.Core?.RestartTitle ?? "重启后台服务", BentoIcon.Restart, BentoTone.InkTone, () => _store.RestartCore(), small: true),
            Bento.Button("在资源管理器中显示配置文件", BentoIcon.Folder, BentoTone.Surface, RevealConfig, small: true));
        var alert = Bento.Card(Bento.VStack(BentoSpace.S12,
                Bento.HStack(BentoSpace.S12, Bento.IconCircleOn(BentoIcon.Warning, BentoTone.Rose), BentoText.Make(reason.Title, BentoTextStyle.Title, BentoTone.Rose.Ink)),
                detail,
                actions),
            BentoTone.Rose, BentoRadius.Xl);
        alert.MaxWidth = 440;
        alert.HorizontalAlignment = HorizontalAlignment.Left;

        var stack = Bento.VStack(BentoSpace.S12,
            Bento.HStack(BentoSpace.S8, Bento.StatusDot(BentoStatus.Error), BentoText.Make(reason.Title, BentoTextStyle.Headline, BentoColor.Ink.Black)),
            alert);
        stack.Padding = new Thickness(BentoSpace.S16, 0, BentoSpace.S24, BentoSpace.S20);
        if (reason.LogTail is { Count: > 0 } tail)
        {
            var lines = Bento.VStack(0);
            foreach (var line in tail)
            {
                var t = BentoText.Make(line, BentoTextStyle.Mono, line.Contains("ERROR") ? BentoColor.Hex(0xFF9A93) : line.Contains("WARN") ? BentoColor.Hex(0xF5C875) : BentoColor.Ink.Inverse);
                t.IsTextSelectionEnabled = true;
                lines.Children.Add(t);
            }
            stack.Children.Add(Bento.Card(Bento.VStack(BentoSpace.S8,
                BentoText.Make($"日志最后 {tail.Count} 行", BentoTextStyle.Label, BentoColor.Ink.InverseMuted), lines), BentoTone.Inverse));
        }
        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }

    private static void RevealConfig()
    {
        var path = DataDir.File("config.json");
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", File.Exists(path) ? $"/select,\"{path}\"" : $"\"{DataDir.Path}\"") { UseShellExecute = true });
        }
        catch { }
    }
}
