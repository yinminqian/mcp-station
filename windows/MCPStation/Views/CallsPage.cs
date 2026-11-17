using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.Views;

/// 调用记录页：统计、筛选（全部 / 错误 / 慢调用）、搜索、表格。对应 Mac 端 BentoCallsPage.swift。
public sealed class CallsPage : Grid
{
    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly Grid _tiles = new() { ColumnSpacing = BentoSpace.S12 };
    private readonly SegmentedPills<Navigator.CallFilter> _filter;
    private readonly TextBox _search;
    private readonly CallTable _table;

    public CallsPage(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;
        Margin = new Thickness(BentoSpace.S20, BentoMetric.TitleBarInset, BentoMetric.WindowInset, BentoMetric.WindowInset);
        RowSpacing = BentoSpace.S12;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition());

        var (searchBox, search) = BentoKit.SearchField("搜索 MCP 或工具", BentoColor.Bg.Panel);
        searchBox.Width = 296;
        _search = search;
        var header = Bento.Row(BentoSpace.S12, BentoText.Make("调用记录", BentoTextStyle.Headline, BentoColor.Ink.Black), null, searchBox);
        header.Height = 40;
        header.Margin = new Thickness(BentoSpace.S4, 0, 0, 0);
        Children.Add(header);

        for (var i = 0; i < 4; i++) _tiles.ColumnDefinitions.Add(new ColumnDefinition());
        _filter = new SegmentedPills<Navigator.CallFilter>(Enum.GetValues<Navigator.CallFilter>(), nav.CurrentCallFilter, Navigator.Title);
        _filter.SelectionChanged += f => nav.SetCallFilter(f);
        _table = new CallTable(store, c =>
        {
            var q = _search.Text.Trim();
            return Navigator.Matches(_nav.CurrentCallFilter, c)
                && (q.Length == 0 || c.Mcp.Contains(q, StringComparison.OrdinalIgnoreCase) || c.Tool.Contains(q, StringComparison.OrdinalIgnoreCase));
        });
        var body = new Grid { RowSpacing = BentoSpace.S12, Padding = new Thickness(BentoSpace.S20) };
        body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        body.RowDefinitions.Add(new RowDefinition());
        body.Children.Add(_tiles);
        SetRow(_filter, 1);
        body.Children.Add(_filter);
        SetRow(_table, 2);
        body.Children.Add(_table);
        var panel = Bento.Panel(body);
        SetRow(panel, 1);
        Children.Add(panel);

        _search.TextChanged += (_, _) => _table.Reload();
        nav.SelectionChanged += () => { _filter.Select(nav.CurrentCallFilter); _table.Reload(); };
        store.CallsChanged += RenderTiles;
        RenderTiles();
    }

    private void RenderTiles()
    {
        var s = _store.Stats;
        _tiles.Children.Clear();
        var tiles = new[]
        {
            BentoKit.StatTile("调用数", Format.Count(s.Total1h), BentoTone.Lavender, "近 1 小时"),
            BentoKit.StatTile("错误", Format.Count(s.Errors1h), s.Errors1h > 0 ? BentoTone.Rose : BentoTone.Mint,
                s.ErrorSources.Count == 0 ? "没有失败" : string.Join("、", s.ErrorSources)),
            BentoKit.StatTile("平均耗时", s.AvgMs is { } avg ? Format.Duration(avg) : "—", BentoTone.Surface, "近 1 小时"),
            BentoKit.StatTile("P95", s.P95Ms is { } p95 ? Format.Duration(p95) : "—", BentoTone.Surface, "慢调用门槛 2.0s"),
        };
        for (var i = 0; i < tiles.Length; i++)
        {
            SetColumn(tiles[i], i);
            _tiles.Children.Add(tiles[i]);
        }
    }
}
