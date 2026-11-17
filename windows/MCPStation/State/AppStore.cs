using MCPStation.Core;
using Microsoft.UI.Dispatching;

namespace MCPStation.State;

/// 全局状态仓库：持有内核推来的状态，提供派生数据和操作。对应 Mac 端 State/AppStore.swift。
///
/// 状态按块存放（core / mcps / services / calls / memory），每块变了只发自己的事件，
/// 所以调用记录每秒刷新时，只有读调用记录的视图跟着重画。所有成员只在 UI 线程上访问。
public sealed class AppStore
{
    public static AppStore Shared { get; private set; } = null!;

    public CoreStatus? Core { get; private set; }
    public List<McpServer> Mcps { get; private set; } = [];
    public List<NamedService> NamedServices { get; private set; } = [];
    public List<CallRecord> Calls { get; private set; } = [];
    public CallStats Stats { get; private set; } = new([], DateTimeOffset.Now);

    public event Action? CoreChanged;
    public event Action? McpsChanged;
    public event Action? ServicesChanged;
    public event Action? CallsChanged;
    public event Action? MemoryChanged;
    public event Action<string, bool>? Toast;
    public event Action? BusyChanged;

    /// 保留多少条调用记录（够画 7 小时的柱状图）。
    public const int MaxCalls = 3000;

    private readonly CoreClient _client = new();
    private readonly DispatcherQueue _ui;
    private readonly HashSet<string> _busy = [];
    /// 正在重试的 MCP：重试出结果前仍算"需要处理"，卡片不消失（Mac 端 2026-11-14 用户反馈）。
    private readonly HashSet<string> _retrying = [];
    private readonly List<CallRecord> _pendingCalls = [];
    private bool _flushScheduled;
    private CancellationTokenSource? _cts;
    // 计时器必须由字段持有：只有局部变量引用的 DispatcherQueueTimer 会被回收，之后再也不触发
    private readonly DispatcherQueueTimer _statsTimer;
    private readonly DispatcherQueueTimer _flushTimer;

    public AppStore(DispatcherQueue ui)
    {
        _ui = ui;
        Shared = this;
        // 半分钟重算一次统计：整点换小时时柱状图要往前挪
        _statsTimer = ui.CreateTimer();
        _statsTimer.Interval = TimeSpan.FromSeconds(30);
        _statsTimer.Tick += (_, _) => { Stats = new CallStats(Calls, DateTimeOffset.Now); CallsChanged?.Invoke(); };
        _statsTimer.Start();
        _flushTimer = ui.CreateTimer();
        _flushTimer.Interval = TimeSpan.FromMilliseconds(300);
        _flushTimer.IsRepeating = false;
        _flushTimer.Tick += (_, _) => FlushCalls();
    }

    public void Start()
    {
        if (_cts != null) return;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        Task.Run(() => _client.RunAsync(u => _ui.TryEnqueue(() => Apply(u)), ct));
    }

    public void Stop() => _cts?.Cancel();

    private void Apply(CoreUpdate update)
    {
        switch (update)
        {
            case CoreUpdate.Snapshot s:
                Core = s.Core;
                // 断线重连后保留内存趋势
                foreach (var m in s.Mcps)
                    if (Mcp(m.Name) is { } old) m.MemoryHistory = old.MemoryHistory;
                Mcps = s.Mcps;
                NamedServices = s.Services;
                Calls = s.Calls;
                _pendingCalls.Clear();
                _retrying.RemoveWhere(n => !Mcps.Any(m => m.Name == n && m.State == McpStateKind.Starting));
                Stats = new CallStats(Calls, DateTimeOffset.Now);
                CoreChanged?.Invoke();
                McpsChanged?.Invoke();
                ServicesChanged?.Invoke();
                CallsChanged?.Invoke();
                MemoryChanged?.Invoke();
                break;
            case CoreUpdate.CoreChanged c:
                var memory = Core?.Memory;
                Core = c.Status;
                Core.Memory ??= memory;
                CoreChanged?.Invoke();
                break;
            case CoreUpdate.McpChanged { Server: var m }:
                var i = Mcps.FindIndex(x => x.Name == m.Name);
                if (m.State != McpStateKind.Starting) _retrying.Remove(m.Name);
                else if (i >= 0 && (Mcps[i].NeedsAttention || _retrying.Contains(m.Name))) _retrying.Add(m.Name);
                if (i >= 0)
                {
                    m.MemoryHistory = Mcps[i].MemoryHistory;
                    if (m.Memory == null && m.IsHealthy) m.Memory = Mcps[i].Memory;
                    Mcps[i] = m;
                }
                else Mcps.Add(m);
                McpsChanged?.Invoke();
                ServicesChanged?.Invoke();
                break;
            case CoreUpdate.ServicesChanged s:
                NamedServices = s.List;
                ServicesChanged?.Invoke();
                break;
            case CoreUpdate.MemorySample mem:
                if (Core != null) Core.Memory = mem.CoreBytes;
                foreach (var m in Mcps)
                {
                    m.Memory = mem.Mcps.TryGetValue(m.Name, out var v) ? v : null;
                    if (m.Memory is { } bytes)
                    {
                        m.MemoryHistory.Add(bytes);
                        if (m.MemoryHistory.Count > 30) m.MemoryHistory.RemoveAt(0);
                    }
                }
                MemoryChanged?.Invoke();
                break;
            case CoreUpdate.CallsAdded c:
                // 攒 300 毫秒再落地：一阵调用不会让表格和统计连着重算好几次
                _pendingCalls.AddRange(c.Batch);
                if (_flushScheduled) return;
                _flushScheduled = true;
                _flushTimer.Start();
                break;
        }
    }

    private void FlushCalls()
    {
        _flushScheduled = false;
        if (_pendingCalls.Count == 0) return;
        Calls.AddRange(_pendingCalls);
        _pendingCalls.Clear();
        if (Calls.Count > MaxCalls) Calls.RemoveRange(0, Calls.Count - MaxCalls);
        Stats = new CallStats(Calls, DateTimeOffset.Now);
        CallsChanged?.Invoke();
    }

    // MARK: 派生数据

    public McpServer? Mcp(string? name) => name == null ? null : Mcps.FirstOrDefault(m => m.Name == name);

    public IEnumerable<McpServer> ActiveMcps => Mcps.Where(m => m.State != McpStateKind.Stopped);
    public int HealthyCount => Mcps.Count(m => m.IsHealthy);
    /// 需要处理的 MCP，包括正在重试、还没出结果的。
    public List<McpServer> Attention => Mcps.Where(m => m.NeedsAttention || _retrying.Contains(m.Name)).ToList();
    /// 内存合计：后台服务 + 所有 MCP 进程树。
    public long TotalMemory => (Core?.Memory ?? 0) + Mcps.Sum(m => m.Memory ?? 0);
    public List<McpServer> MemoryRanking => Mcps.Where(m => m.Memory != null).OrderByDescending(m => m.Memory).ToList();

    /// 默认服务在最前，后面是命名服务。默认服务的成员由开关推出。
    public List<ServiceSummary> Services
    {
        get
        {
            var byName = Mcps.ToDictionary(m => m.Name);
            var list = new List<ServiceSummary>
            {
                new() { Name = "默认", Path = "/mcp", IsDefault = true, Members = Mcps.Where(m => m.InDefault).ToList(), Sessions = Core?.DefaultSessions ?? 0 },
            };
            list.AddRange(NamedServices.Select(s => new ServiceSummary
            {
                Name = s.Name, Path = $"/s/{s.Name}/mcp", Members = s.McpNames.Where(byName.ContainsKey).Select(n => byName[n]).ToList(), Sessions = s.Sessions,
            }));
            return list;
        }
    }

    // MARK: 操作

    public bool IsBusy(string key) => _busy.Contains(key);

    public void SetDefault(string name, bool on)
    {
        if (Mcp(name) is not { } m || m.InDefault == on) return;
        m.InDefault = on;
        McpsChanged?.Invoke();
        ServicesChanged?.Invoke();
        Perform($"default:{name}", () => _client.SetDefaultAsync(name, on), () =>
        {
            if (Mcp(name) is { } back) back.InDefault = !on;
            McpsChanged?.Invoke();
            ServicesChanged?.Invoke();
        });
    }

    public void Restart(string name) => Perform($"restart:{name}", () => _client.RestartAsync(name));
    public void RetryNow(string name) => Perform($"retry:{name}", () => _client.RetryNowAsync(name));
    public void RestartCore() => Perform("core-restart", _client.RestartCoreAsync);

    /// 某个 MCP 被哪些服务用到（"默认" 在前）。
    public List<string> UsedBy(McpServer m) =>
        (m.InDefault ? ["默认"] : new List<string>()).Concat(NamedServices.Where(s => s.McpNames.Contains(m.Name)).Select(s => s.Name)).ToList();

    public void SetMembers(string service, IEnumerable<string> members)
    {
        var i = NamedServices.FindIndex(s => s.Name == service);
        if (i < 0) return;
        var confirmed = NamedServices[i];
        var set = members.ToHashSet();
        var ordered = Mcps.Select(m => m.Name).Where(set.Contains).ToList();
        NamedServices[i] = confirmed with { McpNames = ordered };
        ServicesChanged?.Invoke();
        Perform($"members:{service}", () => _client.SetServiceMembersAsync(service, ordered), () =>
        {
            var j = NamedServices.FindIndex(s => s.Name == service);
            if (j >= 0) NamedServices[j] = confirmed;
            ServicesChanged?.Invoke();
        }, allowConcurrent: true);
    }

    public void ToggleMember(string mcp, string service)
    {
        if (NamedServices.FirstOrDefault(s => s.Name == service) is not { } s) return;
        SetMembers(service, s.McpNames.Contains(mcp) ? s.McpNames.Where(n => n != mcp) : s.McpNames.Append(mcp));
    }

    /// 新增 MCP。成功返回 true；失败原因用 toast 提示，表单保持打开方便改。
    public Task<bool> AddMcp(McpDraft d)
    {
        var name = d.Name.Trim();
        if (name.Length == 0) { ShowToast("请填写「名字」", true); return Task.FromResult(false); }
        if (d.Target.Trim().Length == 0) { ShowToast($"请填写「{d.Kind.TargetLabel()}」", true); return Task.FromResult(false); }
        return Run("add-mcp", () => _client.AddMcpAsync(name, d.ToEntry()));
    }

    public Task<bool> CreateService(string name) => Run("create-service", () => _client.CreateServiceAsync(name.Trim(), []));
    public Task<bool> RenameService(string name, string newName) => Run($"rename:{name}", () => _client.RenameServiceAsync(name, newName.Trim()));
    public void DeleteService(string name) => Perform($"delete:{name}", () => _client.DeleteServiceAsync(name));
    public Task<bool> SetPort(int port) => Run("port", () => _client.SetPortAsync(port));

    public async Task ImportConfig(string path)
    {
        _busy.Add("import");
        BusyChanged?.Invoke();
        try { ShowToast(await _client.ImportAsync(await File.ReadAllTextAsync(path))); }
        catch (Exception e) { ShowToast(e.Message, true); }
        _busy.Remove("import");
        BusyChanged?.Invoke();
    }

    /// 导出当前配置到文件（里面有密钥明文）。
    public async Task ExportConfig(string path)
    {
        try
        {
            await File.WriteAllTextAsync(path, await _client.ExportAsync());
            ShowToast($"已导出到 {Path.GetFileName(path)}");
        }
        catch (Exception e) { ShowToast(e.Message, true); }
    }

    /// 试调用一个工具。出错（连不上、参数不对）时也返回结果，由界面显示；只有 App 自己出问题才用 toast。
    public async Task<(bool IsError, string Text, int Ms)?> CallTool(string mcp, string tool, string argumentsJson)
    {
        _busy.Add($"call:{mcp}");
        BusyChanged?.Invoke();
        try { return await _client.CallToolAsync(mcp, tool, argumentsJson); }
        catch (Exception e) { ShowToast(e.Message, true); return null; }
        finally { _busy.Remove($"call:{mcp}"); BusyChanged?.Invoke(); }
    }

    private async Task<bool> Run(string key, Func<Task> op)
    {
        _busy.Add(key);
        BusyChanged?.Invoke();
        try { await op(); return true; }
        catch (Exception e) { ShowToast(e.Message, true); return false; }
        finally { _busy.Remove(key); BusyChanged?.Invoke(); }
    }

    public void ShowToast(string text, bool isError = false) => Toast?.Invoke(text, isError);

    private async void Perform(string key, Func<Task> op, Action? rollback = null, bool allowConcurrent = false)
    {
        if (!_busy.Add(key) && !allowConcurrent) return;
        BusyChanged?.Invoke();
        try { await op(); }
        catch (Exception e)
        {
            rollback?.Invoke();
            ShowToast(e.Message, isError: true);
        }
        _busy.Remove(key);
        BusyChanged?.Invoke();
    }
}
