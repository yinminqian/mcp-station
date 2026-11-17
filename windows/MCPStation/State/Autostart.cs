using Microsoft.Win32;

namespace MCPStation.State;

/// 登录 Windows 时自动打开（只在托盘里，不弹窗口）。写当前用户的 Run 键，不需要管理员。
/// Mac 上这件事由内核的 LaunchAgent 负责；Windows 上内核由 App 拉起，所以让 App 开机自启。
public static class Autostart
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "MCP Station";
    /// 开机自启时带这个参数：只进托盘，不打开主窗口。
    public const string BackgroundArg = "--background";

    private static string Command => $"\"{Environment.ProcessPath}\" {BackgroundArg}";

    public static bool IsEnabled
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return k?.GetValue(Name) is string v && v.Contains(Environment.ProcessPath ?? "\0", StringComparison.OrdinalIgnoreCase);
        }
    }

    public static void Set(bool on)
    {
        using var k = Registry.CurrentUser.CreateSubKey(Key);
        if (on) k.SetValue(Name, Command);
        else k.DeleteValue(Name, throwOnMissingValue: false);
    }
}
