using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using MCPStation.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPStation.State;

/// 检查更新（Mac 端是 Sparkle）。Windows 版发布在同一个仓库的 GitHub Releases 上，tag 是 `windows-v<版本>`。
/// 有新版本就弹窗显示版本和更新说明，点「下载」打开发布页；不自动替换安装。
public static class Updater
{
    private const string Repo = "yinminqian/mcp-station";
    private const string TagPrefix = "windows-v";

    public static Version Current => typeof(App).Assembly.GetName().Version ?? new Version(0, 0, 0);

    /// 启动后悄悄查一次：只在有新版本时弹窗，网络不通等错误都不提示。
    public static async Task CheckInBackground(XamlRoot root)
    {
        try
        {
            if (await Latest() is { } r && r.Version > Current) await Show(root, r);
        }
        catch { }
    }

    /// 设置页「检查更新…」：没有新版本、查不到也告诉用户。
    public static async Task CheckNow(XamlRoot root, AppStore store)
    {
        try
        {
            var r = await Latest();
            if (r != null && r.Version > Current) await Show(root, r);
            else store.ShowToast($"已经是最新版本（{Current.ToString(3)}）");
        }
        catch (Exception e)
        {
            store.ShowToast($"检查更新失败：{e.Message}", true);
        }
    }

    private sealed record Release(Version Version, string Notes, string Url);

    private static async Task<Release?> Latest()
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("MCPStation-Windows", Current.ToString(3)));
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        var list = JsonNode.Parse(await http.GetStringAsync($"https://api.github.com/repos/{Repo}/releases?per_page=30")) as JsonArray;
        Release? best = null;
        foreach (var r in list?.OfType<JsonObject>() ?? [])
        {
            if (r["draft"]?.GetValue<bool>() == true) continue;
            var tag = r["tag_name"]?.ToString() ?? "";
            if (!tag.StartsWith(TagPrefix) || !Version.TryParse(tag[TagPrefix.Length..], out var v)) continue;
            if (best == null || v > best.Version)
                best = new Release(v, r["body"]?.ToString() ?? "", r["html_url"]?.ToString() ?? $"https://github.com/{Repo}/releases");
        }
        return best;
    }

    private static Task Show(XamlRoot root, Release r) => BentoKit.ShowDialog(root, 440, close =>
    {
        var notes = BentoKit.Wrap(string.IsNullOrWhiteSpace(r.Notes) ? "这个版本没有写更新说明。" : r.Notes.Trim(), BentoTextStyle.Body, BentoColor.Ink.Secondary, selectable: true);
        var box = new Border
        {
            MaxHeight = 240,
            Background = BentoColor.Bg.Panel.Brush(),
            CornerRadius = new CornerRadius(BentoRadius.Md),
            Child = new ScrollViewer { Content = notes, Padding = new Thickness(BentoSpace.S12) },
        };
        var buttons = Bento.HStack(BentoSpace.S8,
            Bento.Button("以后再说", null, BentoTone.Panel, close),
            Bento.Button("下载", null, BentoTone.InkTone, () =>
            {
                try { Process.Start(new ProcessStartInfo(r.Url) { UseShellExecute = true }); } catch { }
                close();
            }));
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        return Bento.VStack(BentoSpace.S14,
            Bento.HStack(BentoSpace.S12,
                Bento.IconCircle(BentoIcon.Brand, BentoMetric.RailButton, BentoColor.Ink.Black, BentoColor.Ink.Inverse),
                Bento.VStack(0,
                    BentoText.Make("MCP Station 有新版本", BentoTextStyle.Title),
                    BentoText.Make($"{r.Version.ToString(3)}（当前 {Current.ToString(3)}）", BentoTextStyle.Label, BentoColor.Ink.Secondary))),
            box,
            buttons);
    });
}
