using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPStation.Views.Overview;

/// 一根柱子：一个小时，里面按服务分段。
public sealed record ChartColumn(string Label, List<(string Service, int From, int To)> Segments, int Total, int Errors)
{
    /// 把小时统计排成柱子。`order` 以外的服务（比如已经删掉的、「试调用」）按名字排在最上面。
    public static List<ChartColumn> Make(List<HourBucket> hourly, List<string> order) => hourly.Select(b =>
    {
        var extra = b.ByService.Keys.Where(k => !order.Contains(k)).OrderBy(k => k);
        var running = 0;
        var segs = new List<(string, int, int)>();
        foreach (var s in order.Concat(extra))
        {
            if (!b.ByService.TryGetValue(s, out var n) || n <= 0) continue;
            segs.Add((s, running, running + n));
            running += n;
        }
        return new ChartColumn(b.Hour.ToString("00"), segs, running, b.Errors);
    }).ToList();
}

/// 概览页的调用卡片：最近几个小时的调用数，按服务堆叠。和内存卡并排、同一副骨架（小标题 / 大数字 / 明细）。
/// 对应 Mac 端 ThemeBento/Pages/Overview/BentoCallChartCard.swift。概览页只有这张卡片读调用统计。
public sealed class CallChartCard : UserControl
{
    private readonly AppStore _store;
    private readonly Navigator _nav;
    private readonly TextBlock _label;
    private readonly StackPanel _legend = Bento.HStack(BentoSpace.S12);
    private readonly TextBlock _total;
    private readonly Pressable _errors;
    private readonly Border _errorsPill = new();
    private readonly CallChart _chart = new();
    private List<ChartColumn> _columns = [];
    private List<string> _order = [];
    private BentoServiceTones _tones = new([]);

    public CallChartCard(AppStore store, Navigator nav)
    {
        _store = store;
        _nav = nav;
        _label = BentoText.Make("", BentoTextStyle.Label, BentoColor.Ink.Secondary);
        _total = BentoText.Make("", BentoTextStyle.Headline, BentoColor.Ink.Black);
        _legend.HorizontalAlignment = HorizontalAlignment.Right;
        _errors = new Pressable(PressableKind.Plain) { InnerContent = _errorsPill, VerticalAlignment = VerticalAlignment.Center };
        _errors.Click += (_, _) => _nav.ShowCalls(Navigator.CallFilter.Errors);

        var grid = new Grid { RowSpacing = BentoSpace.S8 };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = BentoMetric.ChartHeight + CallChart.AxisHeight });
        grid.Children.Add(Bento.Row(BentoSpace.S8, _label, _legend, null));
        var head = Bento.HStack(BentoSpace.S10, _total, _errors);
        Grid.SetRow(head, 1);
        grid.Children.Add(head);
        Grid.SetRow(_chart, 2);
        grid.Children.Add(_chart);

        Content = Bento.Card(grid, radius: BentoRadius.Xl, padding: BentoSpace.S16);
        _chart.HoverChanged += Render;
        store.CallsChanged += Rebuild;
        store.ServicesChanged += Rebuild;
        SizeChanged += (_, _) => RenderLegend();
        Rebuild();
    }

    private void Rebuild()
    {
        var services = _store.Services;
        _order = services.Select(s => s.Name).ToList();
        _tones = new BentoServiceTones(services);
        _columns = ChartColumn.Make(_store.Stats.Hourly, _order);
        _chart.Update(_columns, _tones);
        RenderLegend();
        Render();
    }

    private void Render()
    {
        var hovered = _chart.Hovered;
        var focus = _columns.FirstOrDefault(c => c.Label == hovered);
        var hovering = focus != null;
        var total = hovering ? focus!.Total : _columns.Sum(c => c.Total);
        var errors = hovering ? focus!.Errors : _columns.Sum(c => c.Errors);
        _label.Text = hovering ? $"调用 · {focus!.Label} 点这一小时" : $"调用 · 近 {_columns.Count} 小时";
        _total.Text = $"{Format.Count(total)} 次";
        _errorsPill.Child = Bento.Pill(errors == 0 ? "没有失败" : $"{Format.Count(errors)} 次失败", errors == 0 ? BentoTone.Panel : BentoTone.Rose);
        _errors.IsHitTestVisible = errors > 0;
        ToolTipService.SetToolTip(_errors, errors > 0 ? "查看失败的调用" : null);
    }

    /// 图例：卡片窄到放不下时整个不显示（右栏「我的服务」的颜色和它一致）。
    private void RenderLegend()
    {
        var present = _columns.SelectMany(c => c.Segments.Select(s => s.Service)).ToHashSet();
        var names = _order.Where(present.Contains).Concat(present.Except(_order).OrderBy(n => n));
        _legend.Children.Clear();
        foreach (var n in names)
            _legend.Children.Add(Bento.HStack(BentoSpace.S6,
                new Ellipse { Width = 10, Height = 10, Fill = _tones[n].Fill.Brush(), VerticalAlignment = VerticalAlignment.Center },
                BentoText.Make(n, BentoTextStyle.Label, BentoColor.Ink.Secondary)));
        _legend.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        _label.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var room = ActualWidth - BentoSpace.S16 * 2 - _label.DesiredSize.Width - BentoSpace.S8;
        _legend.Visibility = _legend.DesiredSize.Width <= room ? Visibility.Visible : Visibility.Collapsed;
    }
}

/// 堆叠柱状图。当前（或鼠标指着的）那一小时背后铺一圈浅底，横轴上它的小时变成黑色药丸。
/// 柱子、浅底、小时药丸都在同一张画布上按同一套坐标画，中心线才是同一条。
public sealed class CallChart : Canvas
{
    /// 柱宽占一格的比例。
    private const double BarRatio = 0.74;
    /// 分段之间的缝。
    private const double Gap = BentoSpace.S2;
    /// 空小时那截矮桩的高度。
    private const double Stub = BentoSpace.S4;
    /// 小时药丸的高度和离柱子底的距离。
    private const double Pill = BentoSpace.S20;
    private const double PillTop = BentoSpace.S8;
    public const double AxisHeight = PillTop + Pill;

    private List<ChartColumn> _columns = [];
    private BentoServiceTones _tones = new([]);

    public string? Hovered { get; private set; }
    public event Action? HoverChanged;

    public CallChart()
    {
        Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        SizeChanged += (_, _) => Draw();
        PointerMoved += OnPointerMoved;
        PointerExited += (_, _) => SetHovered(null);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, "最近 7 小时的调用数");
    }

    public void Update(List<ChartColumn> columns, BentoServiceTones tones)
    {
        _columns = columns;
        _tones = tones;
        Draw();
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_columns.Count == 0) return;
        var x = e.GetCurrentPoint(this).Position.X;
        var i = (int)Math.Clamp(Math.Floor(x / (ActualWidth / _columns.Count)), 0, _columns.Count - 1);
        SetHovered(_columns[i].Label);
    }

    private void SetHovered(string? label)
    {
        if (Hovered == label) return;
        Hovered = label;
        Draw();
        HoverChanged?.Invoke();
    }

    private void Draw()
    {
        Children.Clear();
        double w = ActualWidth, h = ActualHeight;
        if (_columns.Count == 0 || w <= 0 || h <= 0) return;
        var plotH = Math.Max(1, h - AxisHeight);
        var baseline = plotH;
        var step = w / _columns.Count;
        var barW = step * BarRatio;
        var peak = Math.Max(1, _columns.Max(c => c.Total));
        double Y(double v) => baseline - v / peak * plotH;
        var focus = Hovered ?? _columns[^1].Label;

        for (var i = 0; i < _columns.Count; i++)
        {
            var col = _columns[i];
            var cx = step * (i + 0.5);
            var left = cx - barW / 2;
            var isFocus = col.Label == focus;
            // 这一小时实际画到多高（像素）：一段都画不出来时按矮桩算
            var drawable = col.Segments.Where(s => Y(s.From) - Y(s.To) - Gap > 0).ToList();
            var top = drawable.Count == 0 ? baseline - Stub : Y(drawable[^1].To) + Gap;

            if (isFocus)
            {
                const double pad = Gap * 2;
                AddRect(left - pad, top - pad, barW + pad * 2, baseline - top + pad * 2, BentoRadius.Sm, BentoColor.Bg.Panel);
            }

            if (drawable.Count == 0)
            {
                // 没有调用、或者少到画不出来的小时，都画一截矮桩：七个小时的位置一直都在，看得出是条时间轴
                var fill = col.Segments.Count > 0 ? _tones[col.Segments[0].Service].Fill : isFocus ? BentoColor.Ink.Tertiary : BentoColor.Bg.Sunken;
                AddRect(left, baseline - Stub, barW, Stub, BentoRadius.Xs, fill);
            }
            else
            {
                foreach (var s in drawable)
                {
                    var y0 = Y(s.To) + Gap;
                    AddRect(left, y0, barW, Y(s.From) - y0, BentoRadius.Xs + 1, _tones[s.Service].Fill);
                }
            }

            // 横轴上的小时，选中的那个垫一颗黑色药丸
            var label = new TextBlock
            {
                Text = col.Label,
                FontFamily = BentoText.LabelFont,
                FontSize = BentoText.Size(BentoTextStyle.Label),
                FontWeight = BentoText.Weight(BentoTextStyle.Label),
                Foreground = (isFocus ? BentoColor.Ink.Inverse : BentoColor.Ink.Tertiary).Brush(),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            var pill = new Border
            {
                Height = Pill,
                MinWidth = Pill,
                Padding = new Thickness(BentoSpace.S6, 0, BentoSpace.S6, 0),
                CornerRadius = new CornerRadius(Pill / 2),
                Background = isFocus ? BentoColor.Ink.Black.Brush() : null,
                Child = label,
                IsHitTestVisible = false,
            };
            pill.Measure(new Windows.Foundation.Size(double.PositiveInfinity, Pill));
            SetLeft(pill, cx - pill.DesiredSize.Width / 2);
            SetTop(pill, baseline + PillTop);
            Children.Add(pill);
        }
    }

    private void AddRect(double x, double y, double w, double h, double radius, Windows.UI.Color fill)
    {
        if (w <= 0 || h <= 0) return;
        var r = new Rectangle { Width = w, Height = h, RadiusX = Math.Min(radius, h / 2), RadiusY = Math.Min(radius, h / 2), Fill = fill.Brush(), IsHitTestVisible = false };
        SetLeft(r, x);
        SetTop(r, y);
        Children.Add(r);
    }
}
