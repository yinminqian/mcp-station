using System.Text.Json.Nodes;

namespace MCPStation.Core;

// 与内核控制接口（core/src/control.rs、docs/ARCHITECTURE.md §4.1）一一对应的数据模型。
// 对应 Mac 端 app/Sources/MCPStation/Core/Models.swift。界面只依赖这些类型。

public enum McpKind { Npx, Uvx, Command, Http }

public enum McpStateKind { Starting, Ready, Backoff, ConfigError, Stopped }

public sealed record ToolInfo(string Name, string Summary, string? Description, string? InputSchema);

public enum LogLevel { Info, Warn, Error }

public sealed record LogLine(long Id, DateTimeOffset Time, LogLevel Level, string Text);

public sealed record DefinitionField(string Key, string Value, bool Secret = false, bool Monospaced = false);

/// 新增 MCP 时填的定义。对应 Mac 端 MCPDraft 和 ConfigFile.MCPEntry(draft:)。
public sealed class McpDraft
{
    public string Name { get; set; } = "";
    public McpKind Kind { get; set; } = McpKind.Npx;
    /// npx / uvx 是包名，命令是可执行文件，HTTP 是地址。
    public string Target { get; set; } = "";
    /// 启动参数，空格分开。HTTP 上游不用。
    public string Args { get; set; } = "";
    /// 每行一条：环境变量 KEY=VALUE，或 HTTP 请求头「名字: 值」。
    public string Extra { get; set; } = "";
    public bool InDefault { get; set; } = true;

    public JsonObject ToEntry()
    {
        var target = Target.Trim();
        var args = Args.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var pairs = new JsonObject();
        foreach (var line in Extra.Split('\n', '\r'))
        {
            var i = line.IndexOf(Kind == McpKind.Http ? ':' : '=');
            if (i <= 0) continue;
            var key = line[..i].Trim();
            if (key.Length > 0) pairs[key] = line[(i + 1)..].Trim();
        }
        static JsonArray Arr(IEnumerable<string> xs) => new(xs.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
        var e = new JsonObject();
        switch (Kind)
        {
            case McpKind.Npx: e["command"] = "npx"; e["args"] = Arr(new[] { "-y", target }.Concat(args)); break;
            case McpKind.Uvx: e["command"] = "uvx"; e["args"] = Arr(new[] { target }.Concat(args)); break;
            case McpKind.Command: e["command"] = target; if (args.Length > 0) e["args"] = Arr(args); break;
            case McpKind.Http: e["url"] = target; break;
        }
        if (pairs.Count > 0) e[Kind == McpKind.Http ? "headers" : "env"] = pairs;
        if (!InDefault) e["x"] = new JsonObject { ["default"] = false };
        return e;
    }
}

public static class McpKindExt
{
    public static string Label(this McpKind k) => k switch { McpKind.Npx => "npx", McpKind.Uvx => "uvx", McpKind.Command => "命令", _ => "HTTP" };
    public static string TargetLabel(this McpKind k) => k switch { McpKind.Npx or McpKind.Uvx => "包", McpKind.Command => "命令", _ => "地址" };
    public static string TargetPrompt(this McpKind k) => k switch
    {
        McpKind.Npx => "@modelcontextprotocol/server-filesystem",
        McpKind.Uvx => "mcp-server-fetch",
        McpKind.Command => @"C:\Python313\python.exe",
        _ => "https://example.com/mcp",
    };
    public static string ExtraLabel(this McpKind k) => k == McpKind.Http ? "请求头" : "环境变量";
    public static string ExtraPrompt(this McpKind k) => k == McpKind.Http ? "每行一个，如 Authorization: Bearer xxx" : "每行一个，如 API_KEY=xxx";
}

public sealed class McpServer
{
    public required string Name { get; init; }
    public McpKind Kind { get; init; }
    public JsonObject Entry { get; init; } = new();
    public List<ToolInfo> Tools { get; init; } = [];
    public int ResourceCount { get; init; }
    public int PromptCount { get; init; }
    public int InstructionsLength { get; init; }
    /// 开关：是否在默认服务里。
    public bool InDefault { get; set; }
    public McpStateKind State { get; init; }
    /// backoff / config_error 时的原因。
    public string Error { get; init; } = "";
    public DateTimeOffset? RetryAt { get; init; }
    public int Attempts { get; init; }
    public int? Pid { get; init; }
    public DateTimeOffset? StartedAt { get; init; }
    public int Restarts { get; init; }
    public List<LogLine> Log { get; init; } = [];
    /// 进程树的常驻内存合计，字节。没在运行或 HTTP 上游时为 null。
    public long? Memory { get; set; }
    /// 最近 30 次采样（每 5 秒一次），画趋势用。
    public List<long> MemoryHistory { get; set; } = [];

    public int ToolCount => Tools.Count;

    /// 详情页显示的定义行。名字里像密钥的（KEY、TOKEN、SECRET、PASSWORD、AUTH）默认打码。对应 Mac 端 MCPEntry.displayFields。
    public List<DefinitionField> Definition
    {
        get
        {
            static string? S(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
            static bool Secret(string k) => new[] { "KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH" }.Any(k.ToUpperInvariant().Contains);
            var args = Entry["args"] is JsonArray a ? a.Select(x => x?.ToString() ?? "").ToList() : [];
            var list = new List<DefinitionField>();
            switch (Kind)
            {
                case McpKind.Http:
                    list.Add(new("地址", S(Entry["url"]) ?? "", Monospaced: true));
                    if (Entry["headers"] is JsonObject h)
                        foreach (var (k, v) in h.OrderBy(p => p.Key)) list.Add(new(k, v?.ToString() ?? "", Secret(k), true));
                    if (S(Entry["x"]?["caCert"]) is { } ca) list.Add(new("CA 证书", ca, Monospaced: true));
                    break;
                case McpKind.Npx or McpKind.Uvx:
                    var pkg = args.FindIndex(x => !x.StartsWith('-'));
                    if (pkg >= 0) list.Add(new("包", args[pkg], Monospaced: true));
                    var rest = args.Where((x, i) => i != pkg && x != "-y").ToList();
                    if (rest.Count > 0) list.Add(new("参数", string.Join(" ", rest), Monospaced: true));
                    break;
                default:
                    list.Add(new("命令", S(Entry["command"]) ?? "", Monospaced: true));
                    if (args.Count > 0) list.Add(new("参数", string.Join(" ", args), Monospaced: true));
                    break;
            }
            if (Entry["env"] is JsonObject env)
                foreach (var (k, v) in env.OrderBy(p => p.Key)) list.Add(new(k, v?.ToString() ?? "", Secret(k), true));
            if (S(Entry["x"]?["notes"]) is { Length: > 0 } notes) list.Add(new("备注", notes));
            return list;
        }
    }

    public bool IsHealthy => State == McpStateKind.Ready;
    public bool NeedsAttention => State is McpStateKind.Backoff or McpStateKind.ConfigError;
}

/// 命名服务。默认服务不在这里，它由各 MCP 的开关推出。
public sealed record NamedService(string Name, List<string> McpNames, int Sessions);

public sealed record CallRecord(long Id, DateTimeOffset Time, string Mcp, string Tool, string Service, string Client, int Ms, string? Error)
{
    public bool IsError => Error != null;
    /// 慢调用门槛：2 秒（和 Mac 端 Navigator.CallFilter.slowThreshold 一致）。
    public bool IsSlow => Ms >= 2000;
}

public enum CoreStateKind
{
    /// 还没连上过。
    Connecting,
    Running,
    /// 网关端口起不来：配置能管，客户端连不上。
    NotInstalled,
    Stopped,
    Restarting,
}

public sealed record CoreDownReason(string Title, string Detail, string? OccupiedBy = null, int LastExitCode = 0, IReadOnlyList<string>? LogTail = null);

public sealed record CoreStatus
{
    public string Version { get; init; } = "—";
    public int Port { get; init; } = 8090;
    public CoreStateKind State { get; init; } = CoreStateKind.Connecting;
    public int Pid { get; init; }
    public DateTimeOffset Since { get; init; } = DateTimeOffset.Now;
    public CoreDownReason? Down { get; init; }
    /// 网关端口起不来的原因（端口被占等），此时 State 是 NotInstalled。
    public string? GatewayError { get; init; }
    public int DefaultSessions { get; init; }
    /// 后台服务自身的常驻内存，字节。
    public long? Memory { get; set; }

    public bool CanManage => State is CoreStateKind.Running or CoreStateKind.NotInstalled;
    public string RestartTitle => State == CoreStateKind.NotInstalled ? "重新检测" : "重启后台服务";
}

/// 默认服务 + 命名服务汇总后的一项。
public sealed class ServiceSummary
{
    public required string Name { get; init; }
    public required string Path { get; init; }
    public bool IsDefault { get; init; }
    public List<McpServer> Members { get; init; } = [];
    public int Sessions { get; init; }

    public int ToolCount => Members.Sum(m => m.ToolCount);
    public int Healthy => Members.Count(m => m.IsHealthy);
    public int InstructionsLength => Members.Sum(m => m.InstructionsLength);
    public int WithInstructions => Members.Count(m => m.InstructionsLength > 0);
    /// 客户端对 MCP 工具名的长度上限（Claude Code 为 64）。
    public const int ToolNameLimit = 64;
    /// 聚合后最长的工具名（客户端看到的是 mcp__<客户端名>__<MCP>__<工具>，这里按 "station" 估）。
    public int LongestToolName => Members.SelectMany(m => m.Tools.Select(t => $"mcp__station__{m.Name}__{t.Name}".Length)).DefaultIfEmpty(0).Max();
}

/// 一小时的调用数，按服务拆分。
public sealed record HourBucket(int Hour, Dictionary<string, int> ByService, int Errors)
{
    public int Total => ByService.Values.Sum();
}

/// 调用统计，从调用记录算出来。对应 Mac 端 CallStats（只保留 Windows 版目前用到的部分）。
public sealed class CallStats
{
    public int Total1h { get; }
    public int Errors1h { get; }
    public List<HourBucket> Hourly { get; }
    public List<string> ErrorSources { get; } = [];
    public int? AvgMs { get; }
    public int? P95Ms { get; }

    public CallStats(IReadOnlyList<CallRecord> calls, DateTimeOffset now)
    {
        var hourAgo = now.AddHours(-1);
        Total1h = calls.Count(c => c.Time >= hourAgo);
        Errors1h = calls.Count(c => c.Time >= hourAgo && c.IsError);
        ErrorSources = calls.Where(c => c.Time >= hourAgo && c.IsError).Select(c => c.Mcp).Distinct().Order().ToList();
        var durations = calls.Where(c => c.Time >= hourAgo).Select(c => c.Ms).Order().ToList();
        if (durations.Count > 0)
        {
            AvgMs = (int)durations.Average();
            P95Ms = durations[Math.Min(durations.Count - 1, (int)(durations.Count * 0.95))];
        }
        var local = now.ToLocalTime();
        var startOfHour = new DateTimeOffset(local.Year, local.Month, local.Day, local.Hour, 0, 0, local.Offset);
        Hourly = [];
        for (var back = 6; back >= 0; back--)
        {
            var from = startOfHour.AddHours(-back);
            var to = from.AddHours(1);
            var by = new Dictionary<string, int>();
            var errors = 0;
            foreach (var c in calls)
            {
                if (c.Time < from || c.Time >= to) continue;
                by[c.Service] = by.GetValueOrDefault(c.Service) + 1;
                if (c.IsError) errors++;
            }
            Hourly.Add(new HourBucket(from.Hour, by, errors));
        }
    }
}
