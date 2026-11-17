using MCPStation.State;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace MCPStation;

public partial class App : Application
{
    public static MainWindow? MainWindow { get; private set; }

    public App()
    {
        InitializeComponent();
        // 未处理的异常写进数据目录的 logs/app-crash.log，方便排查（发布版没有调试器）
        UnhandledException += (_, e) => CrashLog("UI", e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => CrashLog("AppDomain", e.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, e) => CrashLog("Task", e.Exception);
    }

    public static void CrashLog(string where, Exception? e)
    {
        try
        {
            var dir = Path.Combine(Core.DataDir.Path, "logs");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "app-crash.log"), $"{DateTimeOffset.Now:O} [{where}] {e}{Environment.NewLine}{Environment.NewLine}");
        }
        catch { }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var ui = DispatcherQueue.GetForCurrentThread();
        var store = new AppStore(ui);
        MainWindow = new MainWindow(store);
        // 开机自启时只进托盘，不弹窗口
        if (!Environment.GetCommandLineArgs().Contains(Autostart.BackgroundArg)) MainWindow.ShowAndFocus();
        store.Start();
        // 用户又打开了一次（第二个实例把激活转过来了）：把窗口调到前面
        AppInstance.GetCurrent().Activated += (_, _) => ui.TryEnqueue(() => MainWindow.ShowAndFocus());
    }
}
