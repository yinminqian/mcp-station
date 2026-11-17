using MCPStation.Core;
using MCPStation.State;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPStation.Views;

/// 调用记录表：白卡片里的一张表，最新的在最上面。对应 Mac 端 BentoCallTable.swift。
///
/// 表体是原生 ListView（行虚拟化、容器复用）：行模板只是一个空 Grid，容器第一次出现时建好各列，
/// 之后复用时只改文字和颜色——不在滚动时现建控件。行不带悬停和动画、行高固定。
public sealed class CallTable : UserControl
{
    private readonly AppStore _store;
    private readonly Func<CallRecord, bool> _matches;
    private readonly bool _showsMcp;
    private readonly bool _showsService;
    private readonly int _limit;
    private readonly ListView _list;
    private readonly Grid _header;
    private readonly FrameworkElement _empty;
    private bool _showsClient = true;

    private const string RowTemplate =
        "<DataTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><Grid Height='36' /></DataTemplate>";

    public CallTable(AppStore store, Func<CallRecord, bool> matches, bool showsMcp = true, bool showsService = true, int limit = 200)
    {
        _store = store;
        _matches = matches;
        _showsMcp = showsMcp;
        _showsService = showsService;
        _limit = limit;

        _header = new Grid { Height = BentoSpace.S32, Margin = new Thickness(BentoSpace.S8, BentoSpace.S8, BentoSpace.S8, 0) };
        _list = new ListView
        {
            SelectionMode = ListViewSelectionMode.None,
            IsItemClickEnabled = false,
            ItemContainerStyle = (Style)Application.Current.Resources["BentoListRow"],
            ItemTemplate = (DataTemplate)XamlReader.Load(RowTemplate),
            Padding = new Thickness(BentoSpace.S8, 0, BentoSpace.S8, BentoRadius.Lg / 2),
        };
        // 行没有悬停、按下底色
        foreach (var key in new[] { "ListViewItemBackgroundPointerOver", "ListViewItemBackgroundPressed", "ListViewItemBackgroundSelected",
                     "ListViewItemBackgroundSelectedPointerOver", "ListViewItemBackgroundSelectedPressed" })
            _list.Resources[key] = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        _list.ContainerContentChanging += OnContainerContentChanging;

        _empty = Bento.VStack(BentoSpace.S10,
            Bento.IconCircle(BentoIcon.Calls, fill: BentoColor.Bg.Sunken, ink: BentoColor.Ink.Secondary),
            BentoText.Make("没有符合条件的调用", BentoTextStyle.Body, BentoColor.Ink.Secondary));
        _empty.HorizontalAlignment = HorizontalAlignment.Center;
        _empty.VerticalAlignment = VerticalAlignment.Top;
        _empty.Margin = new Thickness(0, BentoSpace.S32, 0, 0);
        foreach (var c in ((StackPanel)_empty).Children) ((FrameworkElement)c).HorizontalAlignment = HorizontalAlignment.Center;

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(_header);
        Grid.SetRow(_list, 1);
        grid.Children.Add(_list);
        Grid.SetRow(_empty, 1);
        grid.Children.Add(_empty);

        var card = Bento.Card(grid, padding: 0);
        Content = card;

        SizeChanged += (_, e) =>
        {
            var wide = e.NewSize.Width >= BentoMetric.CallTableCompactWidth;
            if (wide == _showsClient && _header.Children.Count > 0) return;
            _showsClient = wide;
            BuildHeader();
            Reload();
        };
        store.CallsChanged += Reload;
        BuildHeader();
        Reload();
    }

    /// 筛选条件变了（调用页的筛选按钮）时调用。
    public void Reload()
    {
        var rows = new List<CallRecord>(_limit);
        for (var i = _store.Calls.Count - 1; i >= 0 && rows.Count < _limit; i--)
            if (_matches(_store.Calls[i])) rows.Add(_store.Calls[i]);
        _list.ItemsSource = rows;
        _empty.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    /// 表头和每一行共用的列布局，保证对得齐。
    private void Columns(Grid g)
    {
        g.ColumnDefinitions.Clear();
        g.ColumnSpacing = BentoSpace.S12;
        g.Padding = new Thickness(BentoSpace.S12, 0, BentoSpace.S12, 0);
        void Col(double w) => g.ColumnDefinitions.Add(new ColumnDefinition { Width = w > 0 ? new GridLength(w) : new GridLength(0) });
        Col(68);                               // 时间
        Col(_showsMcp ? 116 : 0);              // MCP
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); // 工具
        Col(_showsService ? 56 : 0);           // 服务
        Col(_showsClient ? 128 : 0);           // 客户端
        Col(56);                               // 耗时
        Col(60);                               // 结果
    }

    private void BuildHeader()
    {
        _header.Children.Clear();
        Columns(_header);
        string[] titles = ["时间", "MCP", "工具", "服务", "客户端", "耗时", "结果"];
        for (var i = 0; i < titles.Length; i++)
        {
            var t = BentoText.Make(titles[i], BentoTextStyle.Label, BentoColor.Ink.Tertiary);
            if (i == 5) t.HorizontalAlignment = HorizontalAlignment.Right;
            Grid.SetColumn(t, i);
            _header.Children.Add(t);
        }
    }

    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.ItemContainer.ContentTemplateRoot is not Grid g || args.Item is not CallRecord r) return;
        if (g.Tag is not RowCells cells || cells.Layout != (_showsMcp, _showsService, _showsClient))
        {
            g.Children.Clear();
            Columns(g);
            cells = new RowCells(g, (_showsMcp, _showsService, _showsClient));
            g.Tag = cells;
        }
        cells.Fill(r);
    }

    private sealed class RowCells
    {
        public (bool, bool, bool) Layout { get; }
        private readonly TextBlock _time, _mcp, _tool, _error, _service, _client, _duration, _outcome;
        private readonly Ellipse _dot;
        private readonly Grid _row;

        public RowCells(Grid g, (bool, bool, bool) layout)
        {
            Layout = layout;
            _row = g;
            _time = Put(g, BentoText.Make("", BentoTextStyle.Mono, BentoColor.Ink.Secondary), 0);
            _mcp = Put(g, BentoText.Make("", BentoTextStyle.BodyStrong), 1);
            _tool = BentoText.Make("", BentoTextStyle.Mono);
            _error = BentoText.Make("", BentoTextStyle.Label, BentoTone.Rose.Ink);
            var toolStack = Bento.VStack(0, _tool, _error);
            toolStack.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(toolStack, 2);
            g.Children.Add(toolStack);
            _service = Put(g, BentoText.Make("", BentoTextStyle.Body, BentoColor.Ink.Secondary), 3);
            _client = Put(g, BentoText.Make("", BentoTextStyle.Body, BentoColor.Ink.Secondary), 4);
            _duration = Put(g, BentoText.Make("", BentoTextStyle.Mono, BentoColor.Ink.Secondary), 5);
            _duration.HorizontalAlignment = HorizontalAlignment.Right;
            // 纯色圆点：调用行用不上闪动动画
            _dot = new Ellipse { Width = BentoMetric.StatusDot, Height = BentoMetric.StatusDot, VerticalAlignment = VerticalAlignment.Center };
            _outcome = BentoText.Make("", BentoTextStyle.Body, BentoColor.Ink.Secondary);
            var outcome = Bento.HStack(BentoSpace.S6, _dot, _outcome);
            Grid.SetColumn(outcome, 6);
            g.Children.Add(outcome);
        }

        private static TextBlock Put(Grid g, TextBlock t, int col)
        {
            Grid.SetColumn(t, col);
            g.Children.Add(t);
            return t;
        }

        public void Fill(CallRecord r)
        {
            _time.Text = Format.Time(r.Time);
            _mcp.Text = r.Mcp;
            _tool.Text = r.Tool;
            _error.Text = r.Error ?? "";
            _error.Visibility = r.IsError ? Visibility.Visible : Visibility.Collapsed;
            _service.Text = r.Service;
            _client.Text = r.Client;
            _duration.Text = Format.Duration(r.Ms);
            _duration.Foreground = (r.IsSlow ? BentoTone.Peach.Ink : BentoColor.Ink.Secondary).Brush();
            _dot.Fill = (r.IsError ? BentoStatus.Error : r.IsSlow ? BentoStatus.Warn : BentoStatus.Ok).Color().Brush();
            _outcome.Text = r.IsError ? "失败" : "成功";
            _outcome.Foreground = (r.IsError ? BentoTone.Rose.Ink : BentoColor.Ink.Secondary).Brush();
            ToolTipService.SetToolTip(_row, r.Error);
        }
    }
}
