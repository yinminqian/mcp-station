using System.Runtime.InteropServices;
using MCPStation.Core;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace MCPStation;

/// 自己写的入口（关掉了 XAML 生成的 Main）：只允许开一个实例。
/// 再打开一次时把激活转给已经在跑的那个（它会把窗口调到前面），自己退出。
/// 实例按数据目录区分：开发时用 MCPSTATION_HOME 指到别处的，可以和正式的同时开。
public static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        var key = "MCPStation-" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(DataDir.Path.ToLowerInvariant())))[..16];
        var main = AppInstance.FindOrRegisterForKey(key);
        if (!main.IsCurrent)
        {
            Redirect(main);
            return 0;
        }
        Application.Start(p =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new App();
        });
        return 0;
    }

    /// 把这次激活转给已经在跑的实例。转发是异步的，主线程是 STA，要边等边处理 COM 消息（官方示例的写法）。
    private static void Redirect(AppInstance target)
    {
        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        var done = CreateEvent(IntPtr.Zero, true, false, null);
        Task.Run(() =>
        {
            try { target.RedirectActivationToAsync(activation).AsTask().Wait(); }
            finally { SetEvent(done); }
        });
        CoWaitForMultipleObjects(0, 0xFFFFFFFF, 1, [done], out _);
        CloseHandle(done);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CreateEvent(IntPtr attrs, bool manualReset, bool initial, string? name);
    [DllImport("kernel32.dll")] private static extern bool SetEvent(IntPtr h);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr h);
    [DllImport("ole32.dll")] private static extern uint CoWaitForMultipleObjects(uint flags, uint timeout, uint count, IntPtr[] handles, out uint index);
}
