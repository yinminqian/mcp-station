namespace MCPStation.State;

/// 页面与选中项。对应 Mac 端 State/Navigator.swift。
public sealed class Navigator
{
    public enum Route { Overview, Mcps, Services, Calls, Settings }
    public enum McpTab { Overview, Tools, Resources, Logs, Calls }
    public enum ServiceTab { Members, Tools, Instructions, Calls }
    public enum CallFilter { All, Errors, Slow }

    public static Navigator Shared { get; } = new();

    /// 换了页面。
    public event Action? RouteChanged;
    /// 换了选中的 MCP / 服务，或者页签、筛选。
    public event Action? SelectionChanged;

    private Route _route = Route.Overview;
    public Route Current
    {
        get => _route;
        set
        {
            if (_route == value) return;
            _route = value;
            RouteChanged?.Invoke();
        }
    }

    public string? SelectedMcp { get; private set; }
    public string? SelectedService { get; private set; } = "默认";
    public McpTab CurrentMcpTab { get; private set; } = McpTab.Overview;
    public ServiceTab CurrentServiceTab { get; private set; } = ServiceTab.Members;
    public CallFilter CurrentCallFilter { get; private set; } = CallFilter.All;

    public void SelectMcp(string? name, McpTab? tab = null)
    {
        SelectedMcp = name;
        if (tab is { } t) CurrentMcpTab = t;
        SelectionChanged?.Invoke();
    }

    public void SelectService(string? name)
    {
        SelectedService = name;
        SelectionChanged?.Invoke();
    }

    public void SetMcpTab(McpTab tab) { CurrentMcpTab = tab; SelectionChanged?.Invoke(); }
    public void SetServiceTab(ServiceTab tab) { CurrentServiceTab = tab; SelectionChanged?.Invoke(); }
    public void SetCallFilter(CallFilter f) { CurrentCallFilter = f; SelectionChanged?.Invoke(); }

    public void ShowMcp(string name)
    {
        SelectMcp(name, McpTab.Overview);
        Current = Route.Mcps;
    }

    public void ShowService(string name)
    {
        SelectService(name);
        Current = Route.Services;
    }

    public void ShowCalls(CallFilter filter)
    {
        SetCallFilter(filter);
        Current = Route.Calls;
    }

    public static string Title(Route r) => r switch
    {
        Route.Overview => "概览",
        Route.Mcps => "MCP",
        Route.Services => "服务",
        Route.Calls => "调用记录",
        _ => "设置",
    };

    public static string Icon(Route r) => r switch
    {
        Route.Overview => Theme.BentoIcon.Overview,
        Route.Mcps => Theme.BentoIcon.Mcps,
        Route.Services => Theme.BentoIcon.Services,
        Route.Calls => Theme.BentoIcon.Calls,
        _ => Theme.BentoIcon.Settings,
    };

    public static string Title(CallFilter f) => f switch { CallFilter.All => "全部", CallFilter.Errors => "错误", _ => "慢调用" };

    /// 慢调用门槛：2 秒。
    public static bool Matches(CallFilter f, Core.CallRecord c) => f switch
    {
        CallFilter.Errors => c.IsError,
        CallFilter.Slow => c.IsSlow,
        _ => true,
    };
}
