using MCPStation.Core;

namespace MCPStation.Theme;

// 这套主题自己加的一层「长相」：MCP 的图标、色调，服务的图标和色调。对应 Mac 端 ThemeBento/BentoCatalog.swift。
// 内核的数据里没有这些概念，所以放在主题里，用一张小表维护；表里没有的按启动方式兜底。

public sealed record BentoMcpLook(BentoTone Tone, string Icon);

public static class BentoCatalog
{
    private static readonly Dictionary<string, BentoMcpLook> Known = new()
    {
        ["chrome-devtools"] = new(BentoTone.Sky, BentoIcon.Browser),
        ["mobile"] = new(BentoTone.Sky, BentoIcon.Phone),
        ["clickhouse"] = new(BentoTone.Mint, BentoIcon.Database),
        ["postgres"] = new(BentoTone.Mint, BentoIcon.Database),
        ["obsidian"] = new(BentoTone.Lavender, BentoIcon.Document),
        ["filesystem"] = new(BentoTone.Lavender, BentoIcon.Folder),
        ["wordcraft"] = new(BentoTone.Sky, BentoIcon.Document),
        ["desktop"] = new(BentoTone.Mint, BentoIcon.Terminal),
        ["peekaboo"] = new(BentoTone.Sky, BentoIcon.Eye),
    };

    private static readonly Dictionary<string, string> KnownServiceIcons = new()
    {
        ["ios"] = BentoIcon.Phone,
        ["data"] = BentoIcon.Database,
    };

    public static BentoMcpLook Look(McpServer m) =>
        Known.TryGetValue(m.Name, out var look) ? look : m.Kind switch
        {
            McpKind.Http => new(BentoTone.Sky, BentoIcon.Http),
            McpKind.Npx or McpKind.Uvx => new(BentoTone.Lavender, BentoIcon.Package),
            _ => new(BentoTone.Mint, BentoIcon.Terminal),
        };

    public static string Icon(ServiceSummary s) =>
        s.IsDefault ? BentoIcon.Services : KnownServiceIcons.GetValueOrDefault(s.Name, BentoIcon.Services);

    /// 卡片的色调：状态优先（等待重试 peach、配置错误 rose、已停止灰），正常时用表里的颜色。
    public static BentoTone CardTone(McpServer m) => m.State switch
    {
        McpStateKind.Backoff => BentoTone.Peach,
        McpStateKind.ConfigError => BentoTone.Rose,
        McpStateKind.Stopped => BentoTone.Sunken,
        _ => Look(m).Tone,
    };
}

/// 每个服务的色调。默认服务固定 lavender，命名服务按顺序轮流取色；
/// 概览的柱状图、服务卡片都用这同一份，颜色才对得上。
public sealed class BentoServiceTones
{
    private readonly Dictionary<string, BentoTone> _byName = [];

    public BentoServiceTones(IEnumerable<ServiceSummary> services)
    {
        var named = 0;
        foreach (var s in services)
            _byName[s.Name] = s.IsDefault ? BentoTone.Lavender : BentoTone.ServiceCycle[named++ % BentoTone.ServiceCycle.Length];
    }

    public BentoTone this[string name] => _byName.GetValueOrDefault(name, BentoTone.Stone);
}
