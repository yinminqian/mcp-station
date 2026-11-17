using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.Views.Overview;

/// 概览页的内存卡片：合计（后台服务 + 所有 MCP），和占用最多的几个 MCP。
/// 和调用卡并排、同一副骨架，两张卡逐行对齐。对应 Mac 端 BentoMemoryCard.swift。
public sealed class MemoryCard : UserControl
{
    private const int TopCount = 6;

    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly TextBlock _total;
    private readonly StackPanel _rows = Bento.VStack(BentoSpace.S4);

    public MemoryCard(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;
        _total = BentoText.Make("—", BentoTextStyle.Headline, BentoColor.Ink.Black);
        var stack = Bento.VStack(BentoSpace.S8,
            BentoText.Make("内存 · 合计", BentoTextStyle.Label, BentoColor.Ink.Secondary),
            _total,
            _rows);
        stack.VerticalAlignment = VerticalAlignment.Top;
        var card = Bento.Card(stack, radius: BentoRadius.Xl, padding: BentoSpace.S16);
        card.VerticalAlignment = VerticalAlignment.Stretch;
        Content = card;
        store.MemoryChanged += Render;
        store.McpsChanged += Render;
        Render();
    }

    private readonly List<(string Name, Border Bar, TextBlock Value)> _cells = [];

    private void Render()
    {
        var top = _store.MemoryRanking.Take(TopCount).ToList();
        var peak = top.FirstOrDefault()?.Memory ?? 0;
        // 一个采样都没有时显示「—」，不是「<1 MB」
        _total.Text = Format.Bytes(top.Count == 0 ? null : _store.TotalMemory);
        // 排名里的 MCP 和顺序都没变：只改数值和比例条。每 5 秒一次采样，整行重建会闪（2026-11-17 用户反馈）
        if (top.Count > 0 && top.Select(m => m.Name).SequenceEqual(_cells.Select(c => c.Name)))
        {
            for (var i = 0; i < top.Count; i++)
            {
                _cells[i].Value.Text = Format.Bytes(top[i].Memory);
                _cells[i].Bar.Width = 72 * Math.Max(0.04, peak > 0 ? (double)(top[i].Memory ?? 0) / peak : 0);
            }
            return;
        }
        _cells.Clear();
        _rows.Children.Clear();
        if (top.Count == 0)
        {
            var text = _store.Mcps.Any(m => m.State == McpStateKind.Ready) ? "正在采样…" : "没有在跑的本地 MCP";
            _rows.Children.Add(BentoText.Make(text, BentoTextStyle.Label, BentoColor.Ink.Tertiary));
        }
        foreach (var m in top) _rows.Children.Add(MakeRow(m, peak > 0 ? (double)(m.Memory ?? 0) / peak : 0));
    }

    /// 一行：名字、相对最大者的比例条、数值。
    private Pressable MakeRow(McpServer m, double share)
    {
        var grid = new Grid { ColumnSpacing = BentoSpace.S8, Height = BentoSpace.S20 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(52) });
        grid.Children.Add(BentoText.Make(m.Name, BentoTextStyle.Body));
        var track = new Grid { Height = BentoSpace.S6, VerticalAlignment = VerticalAlignment.Center };
        track.Children.Add(new Border { Background = BentoColor.Bg.Panel.Brush(), CornerRadius = new CornerRadius(3) });
        var bar = new Border
        {
            Background = BentoCatalog.Look(m).Tone.Ink.Brush(),
            CornerRadius = new CornerRadius(3),
            HorizontalAlignment = HorizontalAlignment.Left,
            Width = 72 * Math.Max(0.04, share),
        };
        track.Children.Add(bar);
        Grid.SetColumn(track, 1);
        grid.Children.Add(track);
        var value = BentoText.Make(Format.Bytes(m.Memory), BentoTextStyle.Label, BentoColor.Ink.Secondary);
        value.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(value, 2);
        grid.Children.Add(value);
        _cells.Add((m.Name, bar, value));
        var row = new Pressable(PressableKind.Row, radius: BentoRadius.Xs) { InnerContent = grid };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(row, $"{m.Name} {Format.Bytes(m.Memory)}");
        row.Click += (_, _) => _nav.ShowMcp(m.Name);
        return row;
    }
}
