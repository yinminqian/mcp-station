using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace MCPStation.Core;

/// 推给界面的一次变化。对应 Mac 端 CoreUpdate。
public abstract record CoreUpdate
{
    public sealed record Snapshot(CoreStatus Core, List<McpServer> Mcps, List<NamedService> Services, List<CallRecord> Calls) : CoreUpdate;
    public sealed record CoreChanged(CoreStatus Status) : CoreUpdate;
    public sealed record McpChanged(McpServer Server) : CoreUpdate;
    public sealed record ServicesChanged(List<NamedService> List) : CoreUpdate;
    public sealed record CallsAdded(List<CallRecord> Batch) : CoreUpdate;
    public sealed record MemorySample(long? CoreBytes, Dictionary<string, long> Mcps) : CoreUpdate;
}

public sealed class CoreApiException(string message) : Exception(message);

/// 内核（mcp-core）控制接口的客户端。对应 Mac 端 HTTPCoreClient.swift。
///
/// - 端口和令牌在内核写的 runtime.json 里；
/// - 实时状态订阅 GET /control/events（SSE，每个事件固定 `event:` + `data:` 两行）；
/// - 断了每秒重连；连不上几次后问 `mcp-core status`，没在跑就拉起来（Windows 上内核还不能装成自启服务）。
public sealed class CoreClient
{
    public const int ApiVersion = 1;

    private static readonly HttpClient Http = new(new SocketsHttpHandler { UseProxy = false }) { Timeout = Timeout.InfiniteTimeSpan };

    private CoreStatus _lastCore = new() { State = CoreStateKind.Restarting };
    private DateTimeOffset _lastLaunch = DateTimeOffset.MinValue;

    /// 在后台线程上持续读事件流，每个变化回调一次。取消 `ct` 结束。
    public async Task RunAsync(Action<CoreUpdate> emit, CancellationToken ct)
    {
        var failures = 0;
        while (!ct.IsCancellationRequested)
        {
            var rt = Runtime.Read();
            if (rt != null)
            {
                try
                {
                    using var req = new HttpRequestMessage(HttpMethod.Get, rt.Url("/control/events"));
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", rt.Token);
                    using var resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
                    if (resp.StatusCode != HttpStatusCode.OK) throw new CoreApiException("not running");
                    using var stream = await resp.Content.ReadAsStreamAsync(ct);
                    using var reader = new StreamReader(stream, Encoding.UTF8);
                    var ev = "";
                    while (await reader.ReadLineAsync(ct) is { } line)
                    {
                        if (line.StartsWith("event:")) ev = line[6..].Trim();
                        else if (line.StartsWith("data:"))
                        {
                            failures = 0;
                            var u = Decode(ev, line[5..]);
                            if (u != null) emit(u);
                        }
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested) { return; }
                catch { }
            }
            if (ct.IsCancellationRequested) return;
            failures++;
            if (failures == 1)
            {
                _lastCore = _lastCore with { State = CoreStateKind.Restarting };
                emit(new CoreUpdate.CoreChanged(_lastCore));
                // 一上来就连不上（比如刚开机、内核还没起）：直接拉起，不等几秒
                if (rt == null) TryLaunch();
            }
            else if (failures % 5 == 0)
            {
                _lastCore = _lastCore with { State = await DiagnoseAsync() };
                if (_lastCore.State == CoreStateKind.Stopped) _lastCore = _lastCore with { Down = _lastDown };
                emit(new CoreUpdate.CoreChanged(_lastCore));
            }
            try { await Task.Delay(1000, ct); } catch { return; }
        }
    }

    private CoreDownReason? _lastDown;

    /// 内核连不上：问 `mcp-core status` 为什么；没在跑就拉起一次（最多 30 秒一次）。
    private async Task<CoreStateKind> DiagnoseAsync()
    {
        if (DateTimeOffset.Now - _lastLaunch > TimeSpan.FromSeconds(30) && TryLaunch())
            return CoreStateKind.Restarting;
        var st = await CoreLauncher.StatusAsync();
        var tail = st?["logTail"]?.AsArray().Select(x => x?.ToString() ?? "").ToList() ?? [];
        var exit = st?["lastExitCode"]?.GetValue<int>() ?? 0;
        var owner = st?["portOwner"]?.ToString();
        _lastDown = CoreLauncher.Binary == null
            ? new CoreDownReason("找不到内核", "没有找到 mcp-core.exe。把它放在 App 旁边，或者先在 core 目录 cargo build。")
            : exit != 0
                ? new CoreDownReason($"后台服务启动后退出了（退出码 {exit}）", "下面是内核日志的最后几行。点「重启」再试一次。", owner, exit, tail)
                : new CoreDownReason("后台服务没有运行", "点「重启」启动它。", owner, exit, tail);
        return CoreStateKind.Stopped;
    }

    private bool TryLaunch()
    {
        _lastLaunch = DateTimeOffset.Now;
        return CoreLauncher.Launch();
    }

    // MARK: 事件 → CoreUpdate

    private CoreUpdate? Decode(string ev, string data)
    {
        JsonNode? obj;
        try { obj = JsonNode.Parse(data); } catch { return null; }
        if (obj == null) return null;
        switch (ev)
        {
            case "snapshot":
                if (obj["core"] is not JsonObject c) return null;
                _lastCore = ParseCore(c);
                return new CoreUpdate.Snapshot(_lastCore,
                    Arr(obj["mcps"]).Select(ParseMcp).ToList(),
                    Arr(obj["services"]).Select(ParseService).ToList(),
                    Arr(obj["calls"]).Select(ParseCall).ToList());
            case "core":
                if (obj is not JsonObject cc) return null;
                _lastCore = ParseCore(cc);
                return new CoreUpdate.CoreChanged(_lastCore);
            case "mcp":
                return obj is JsonObject m ? new CoreUpdate.McpChanged(ParseMcp(m)) : null;
            case "services":
                return new CoreUpdate.ServicesChanged(Arr(obj).Select(ParseService).ToList());
            case "calls":
                return new CoreUpdate.CallsAdded(Arr(obj).Select(ParseCall).ToList());
            case "memory":
                var mcps = new Dictionary<string, long>();
                if (obj["mcps"] is JsonObject mm)
                    foreach (var (k, v) in mm) if (v is JsonValue jv && jv.TryGetValue<long>(out var n)) mcps[k] = n;
                return new CoreUpdate.MemorySample(Long(obj["core"]), mcps);
            default:
                return null;
        }
    }

    private static IEnumerable<JsonObject> Arr(JsonNode? n) => n is JsonArray a ? a.OfType<JsonObject>() : [];
    private static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    private static int? Int(JsonNode? n) => n is JsonValue v && v.TryGetValue<double>(out var d) ? (int)d : null;
    private static long? Long(JsonNode? n) => n is JsonValue v && v.TryGetValue<double>(out var d) ? (long)d : null;
    private static bool? Bool(JsonNode? n) => n is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;
    private static DateTimeOffset? Date(JsonNode? n) =>
        n is JsonValue v && v.TryGetValue<double>(out var d) ? DateTimeOffset.FromUnixTimeMilliseconds((long)(d * 1000)).ToLocalTime() : null;

    private static CoreStatus ParseCore(JsonObject c)
    {
        CoreStateKind state;
        CoreDownReason? down = null;
        if (Int(c["api"]) != ApiVersion)
        {
            state = CoreStateKind.Stopped;
            down = new("内核版本不对", $"运行的内核接口版本是 {c["api"]}，这个 App 需要 {ApiVersion}。点「重启」会换成 App 带的内核，客户端会断几秒。");
        }
        else if (Str(c["configError"]) is { } e)
        {
            state = CoreStateKind.Stopped;
            down = new("配置文件读不了", $"{e}\n修好或移走这个文件后点「重启」。在修好之前不会改动它（现在用的是上一份能用的备份）。");
        }
        else if (Str(c["gatewayError"]) != null) state = CoreStateKind.NotInstalled;
        else state = CoreStateKind.Running;
        return new CoreStatus
        {
            Version = Str(c["version"]) ?? "—",
            Port = Int(c["port"]) ?? 8090,
            State = state,
            Pid = Int(c["pid"]) ?? 0,
            Since = Date(c["startedAt"]) ?? DateTimeOffset.Now,
            Down = down,
            GatewayError = Str(c["gatewayError"]),
            DefaultSessions = Int(c["defaultSessions"]) ?? 0,
            Memory = Long(c["memory"]),
        };
    }

    private static McpServer ParseMcp(JsonObject d)
    {
        var entry = d["entry"] as JsonObject ?? new JsonObject();
        var error = Str(d["error"]) ?? "";
        var state = Str(d["state"]) switch
        {
            "ready" => McpStateKind.Ready,
            "starting" => McpStateKind.Starting,
            "backoff" => McpStateKind.Backoff,
            "config_error" => McpStateKind.ConfigError,
            _ => McpStateKind.Stopped,
        };
        var tools = Arr(d["tools"]).Select(t =>
        {
            var desc = Str(t["description"]);
            return new ToolInfo(Str(t["name"]) ?? "", Summary(desc), desc,
                t["inputSchema"]?.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }).ToList();
        var log = Arr(d["log"]).Select(l => new LogLine(Long(l["id"]) ?? 0, Date(l["t"]) ?? DateTimeOffset.Now,
            Str(l["level"]) switch { "error" => LogLevel.Error, "warn" => LogLevel.Warn, _ => LogLevel.Info },
            Str(l["text"]) ?? "")).ToList();
        return new McpServer
        {
            Name = Str(d["name"]) ?? "",
            Kind = KindOf(entry),
            Entry = (JsonObject)entry.DeepClone(),
            Tools = tools,
            ResourceCount = Int(d["resources"]) ?? 0,
            PromptCount = Int(d["prompts"]) ?? 0,
            InstructionsLength = Int(d["instructionsLength"]) ?? 0,
            InDefault = Bool(d["default"]) ?? true,
            State = state,
            Error = error,
            RetryAt = Date(d["retryAt"]),
            Attempts = Int(d["attempts"]) ?? 1,
            Pid = Int(d["pid"]),
            StartedAt = Date(d["startedAt"]),
            Restarts = Int(d["restarts"]) ?? 0,
            Log = log,
            Memory = Long(d["memory"]),
        };
    }

    public static McpKind KindOf(JsonObject entry)
    {
        if (Str(entry["url"]) != null) return McpKind.Http;
        var cmd = Str(entry["command"]);
        var name = cmd == null ? "" : System.IO.Path.GetFileNameWithoutExtension(cmd).ToLowerInvariant();
        return name switch { "npx" => McpKind.Npx, "uvx" => McpKind.Uvx, _ => McpKind.Command };
    }

    private static NamedService ParseService(JsonObject d) =>
        new(Str(d["name"]) ?? "", Arr2(d["mcps"]), Int(d["sessions"]) ?? 0);

    private static List<string> Arr2(JsonNode? n) => n is JsonArray a ? a.Select(x => x?.ToString() ?? "").ToList() : [];

    private static CallRecord ParseCall(JsonObject d)
    {
        var service = Str(d["route"]) switch
        {
            "default" => "默认",
            "test" => "试调用",
            "single" => "单独地址",
            _ => Str(d["service"]) ?? "—",
        };
        return new CallRecord(Long(d["id"]) ?? 0, Date(d["t"]) ?? DateTimeOffset.Now, Str(d["mcp"]) ?? "", Str(d["tool"]) ?? "",
            service, Str(d["client"]) ?? "未知客户端", Int(d["ms"]) ?? 0, Str(d["error"]));
    }

    /// 工具说明只留第一行，最多 120 个字。
    private static string Summary(string? s)
    {
        var line = s?.Split('\n', 2)[0].Trim() ?? "";
        return line.Length > 120 ? line[..119] + "…" : line;
    }

    // MARK: 操作

    public Task SetDefaultAsync(string mcp, bool on) => SendAsync("PUT", $"/control/mcps/{Uri.EscapeDataString(mcp)}/default", new JsonObject { ["on"] = on });
    public Task RestartAsync(string mcp) => SendAsync("POST", $"/control/mcps/{Uri.EscapeDataString(mcp)}/restart");
    public Task RetryNowAsync(string mcp) => SendAsync("POST", $"/control/mcps/{Uri.EscapeDataString(mcp)}/retry");

    public Task AddMcpAsync(string name, JsonObject entry) => SendAsync("POST", "/control/mcps", new JsonObject { ["name"] = name, ["entry"] = entry });
    public Task CreateServiceAsync(string name, IEnumerable<string> mcps) =>
        SendAsync("POST", "/control/services", new JsonObject { ["name"] = name, ["mcps"] = StrArray(mcps) });
    public Task SetServiceMembersAsync(string service, IEnumerable<string> mcps) =>
        SendAsync("PUT", $"/control/services/{Uri.EscapeDataString(service)}", new JsonObject { ["mcps"] = StrArray(mcps) });
    public Task RenameServiceAsync(string name, string newName) => SendAsync("PUT", $"/control/services/{Uri.EscapeDataString(name)}", new JsonObject { ["name"] = newName });
    public Task DeleteServiceAsync(string name) => SendAsync("DELETE", $"/control/services/{Uri.EscapeDataString(name)}");
    public Task SetPortAsync(int port) => SendAsync("PUT", "/control/settings", new JsonObject { ["port"] = port });
    public Task<string> ExportAsync() => RequestAsync("GET", "/control/export");

    private static JsonArray StrArray(IEnumerable<string> xs) => new(xs.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());

    /// 导入一份配置（本软件导出的文件，或 Claude / Cursor 等的 mcpServers），返回给人看的结果。
    public async Task<string> ImportAsync(string json)
    {
        var r = JsonNode.Parse(await RequestAsync("POST", "/control/import", json));
        var parts = new List<string> { $"导入完成：新增 {Int(r?["added"]) ?? 0} 个 MCP" };
        if (Int(r?["updated"]) is { } u && u > 0) parts.Add($"更新 {u} 个");
        if (Int(r?["services"]) is { } sv && sv > 0) parts.Add($"{sv} 个服务");
        if (r?["skipped"] is JsonArray { Count: > 0 } skipped)
            parts.Add($"跳过名字不合法的 {skipped.Count} 个（{string.Join("、", skipped.Take(3).Select(x => x?.ToString()))}）");
        return string.Join("，", parts);
    }

    /// 直接调一次某个 MCP 的工具，结果记进调用记录。参数是一段 JSON 对象文本。
    public async Task<(bool IsError, string Text, int Ms)> CallToolAsync(string mcp, string tool, string argumentsJson)
    {
        JsonNode args;
        var trimmed = argumentsJson.Trim();
        if (trimmed.Length == 0) args = new JsonObject();
        else
        {
            try { args = JsonNode.Parse(trimmed) as JsonObject ?? throw new FormatException(); }
            catch { return (true, "参数不是合法的 JSON 对象", 0); }
        }
        var r = await SendAsync("POST", $"/control/mcps/{Uri.EscapeDataString(mcp)}/call", new JsonObject { ["tool"] = tool, ["arguments"] = args });
        return (Bool(r?["isError"]) ?? true, Str(r?["text"]) ?? "", Int(r?["ms"]) ?? 0);
    }

    /// 重启内核。Windows 上内核还没有自启服务，由 App 直接结束并重新拉起。
    public async Task RestartCoreAsync()
    {
        await Task.Run(() =>
        {
            CoreLauncher.Kill(Runtime.Read()?.Pid);
            if (!CoreLauncher.Launch()) throw new CoreApiException("找不到内核 mcp-core.exe");
        });
        _lastLaunch = DateTimeOffset.Now;
    }

    public async Task<JsonNode?> SendAsync(string method, string path, JsonNode? body = null)
    {
        var text = await RequestAsync(method, path, body?.ToJsonString());
        return string.IsNullOrEmpty(text) ? null : JsonNode.Parse(text);
    }

    /// 发一个控制请求，返回响应正文。令牌不对（内核重启换了令牌）或连不上时重读 runtime.json 再试一次。
    public async Task<string> RequestAsync(string method, string path, string? body = null)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var rt = Runtime.Read() ?? throw new CoreApiException("后台服务没有运行");
            using var req = new HttpRequestMessage(new HttpMethod(method), rt.Url(path));
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", rt.Token);
            if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            HttpResponseMessage resp;
            try { resp = await Http.SendAsync(req); }
            catch
            {
                if (attempt == 0) { await Task.Delay(500); continue; }
                throw new CoreApiException("后台服务没有运行");
            }
            using (resp)
            {
                var text = await resp.Content.ReadAsStringAsync();
                if (resp.StatusCode == HttpStatusCode.Unauthorized && attempt == 0) continue;
                if (resp.IsSuccessStatusCode) return text;
                string? message = null;
                try { message = Str(JsonNode.Parse(text)?["error"]?["message"]); } catch { }
                throw new CoreApiException(message ?? "内核返回了错误");
            }
        }
        throw new CoreApiException("后台服务没有运行");
    }
}

/// 数据目录。开发时用环境变量 MCPSTATION_HOME 指到别处（内核也认这个变量）。
public static class DataDir
{
    public static string Path
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("MCPSTATION_HOME");
            if (!string.IsNullOrEmpty(env)) return env;
            return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MCP Station");
        }
    }

    public static string File(string name) => System.IO.Path.Combine(Path, name);
}

/// 内核写的 runtime.json：控制接口的端口和令牌。
internal sealed record Runtime(int ControlPort, string Token, int? Pid)
{
    public static Runtime? Read()
    {
        try
        {
            var o = JsonNode.Parse(System.IO.File.ReadAllText(DataDir.File("runtime.json")));
            var port = o?["controlPort"]?.GetValue<int>();
            var token = o?["token"]?.GetValue<string>();
            if (port == null || token == null) return null;
            return new Runtime(port.Value, token, o?["pid"]?.GetValue<int>());
        }
        catch { return null; }
    }

    public Uri Url(string path) => new($"http://127.0.0.1:{ControlPort}{path}");
}

/// 找内核、拉起内核、结束内核。Mac 上这些是 LaunchAgent 的事；Windows 上内核的自启还没做，先由 App 管。
public static class CoreLauncher
{
    /// mcp-core.exe 在哪：App 旁边 → 环境变量 MCPSTATION_CORE → 开发时仓库里 core/target 下编译出来的。
    public static string? Binary
    {
        get
        {
            var beside = Path.Combine(AppContext.BaseDirectory, "mcp-core.exe");
            if (File.Exists(beside)) return beside;
            var env = Environment.GetEnvironmentVariable("MCPSTATION_CORE");
            if (!string.IsNullOrEmpty(env) && File.Exists(env)) return env;
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            {
                foreach (var profile in new[] { "release", "debug" })
                {
                    var p = Path.Combine(dir.FullName, "core", "target", profile, "mcp-core.exe");
                    if (File.Exists(p)) return p;
                }
            }
            return null;
        }
    }

    /// 在后台拉起 `mcp-core run`（不弹窗口）。内核自己有单实例锁，多拉一次也没关系。
    public static bool Launch()
    {
        var bin = Binary;
        if (bin == null) return false;
        try
        {
            var psi = new ProcessStartInfo(bin, "run")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(bin)!,
            };
            Process.Start(psi);
            return true;
        }
        catch { return false; }
    }

    /// 结束内核和它拉起的所有 MCP（整棵进程树）。
    public static void Kill(int? pid)
    {
        if (pid is not { } p) return;
        try
        {
            using var proc = Process.GetProcessById(p);
            if (!proc.ProcessName.Contains("mcp-core", StringComparison.OrdinalIgnoreCase)) return;
            proc.Kill(entireProcessTree: true);
            proc.WaitForExit(3000);
        }
        catch { }
    }

    public static async Task<JsonNode?> StatusAsync()
    {
        var bin = Binary;
        if (bin == null) return null;
        try
        {
            var psi = new ProcessStartInfo(bin, "status") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
            using var p = Process.Start(psi)!;
            var output = await p.StandardOutput.ReadToEndAsync();
            await p.WaitForExitAsync();
            var last = output.Split('\n', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
            return last == null ? null : JsonNode.Parse(last);
        }
        catch { return null; }
    }
}
