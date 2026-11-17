using System.Runtime.InteropServices;

namespace MCPStation;

/// 通知区域（托盘）图标。Mac 端是菜单栏图标；这里直接用 Win32 的 Shell_NotifyIcon，菜单是系统原生的弹出菜单。
///
/// 消息挂在主窗口上（SetWindowSubclass）：左键打开窗口，右键弹菜单。资源管理器重启后自动把图标加回来。
public sealed class TrayIcon : IDisposable
{
    public enum Command { Open = 1, RestartCore = 2, Quit = 3 }

    private const uint CallbackMessage = 0x8000 + 1; // WM_APP + 1
    private const uint WM_LBUTTONUP = 0x0202, WM_RBUTTONUP = 0x0205, WM_LBUTTONDBLCLK = 0x0203;
    private const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2;
    private const uint NIF_MESSAGE = 1, NIF_ICON = 2, NIF_TIP = 4, NIF_SHOWTIP = 0x80;
    private const uint MF_STRING = 0, MF_GRAYED = 1, MF_SEPARATOR = 0x800;
    private const uint TPM_RETURNCMD = 0x100, TPM_RIGHTBUTTON = 2;

    private readonly IntPtr _hwnd;
    private readonly IntPtr _icon;
    private readonly uint _taskbarCreated;
    private readonly SubclassProc _proc; // 必须由字段持有，否则委托被回收后窗口消息会崩
    private string _tip = "MCP Station";
    private string _status = "";
    private bool _disposed;

    public event Action<Command>? Invoked;

    public TrayIcon(IntPtr hwnd, string iconPath)
    {
        _hwnd = hwnd;
        var size = GetSystemMetrics(49 /* SM_CXSMICON */);
        _icon = LoadImage(IntPtr.Zero, iconPath, 1 /* IMAGE_ICON */, size, size, 0x10 /* LR_LOADFROMFILE */);
        _taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        _proc = WndProc;
        SetWindowSubclass(hwnd, _proc, 1, IntPtr.Zero);
        Add();
    }

    /// 悬停提示和菜单顶上的那行状态（「● 后台服务运行中」）。
    public void SetStatus(string status)
    {
        _status = status;
        _tip = $"MCP Station — {status}";
        var d = Data(NIF_TIP | NIF_SHOWTIP);
        Shell_NotifyIcon(NIM_MODIFY, ref d);
    }

    private void Add()
    {
        var d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        Shell_NotifyIcon(NIM_ADD, ref d);
    }

    private NOTIFYICONDATAW Data(uint flags) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATAW>(),
        hWnd = _hwnd,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = CallbackMessage,
        hIcon = _icon,
        szTip = _tip.Length > 127 ? _tip[..127] : _tip,
        szInfo = "",
        szInfoTitle = "",
    };

    private IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, IntPtr data)
    {
        if (msg == CallbackMessage)
        {
            switch ((uint)lParam.ToInt64() & 0xFFFF)
            {
                case WM_LBUTTONUP or WM_LBUTTONDBLCLK:
                    Invoked?.Invoke(Command.Open);
                    break;
                case WM_RBUTTONUP:
                    ShowMenu();
                    break;
            }
            return IntPtr.Zero;
        }
        if (msg == _taskbarCreated) Add();
        return DefSubclassProc(hwnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        AppendMenu(menu, MF_STRING | MF_GRAYED, 0, $"● {_status}");
        AppendMenu(menu, MF_SEPARATOR, 0, null);
        AppendMenu(menu, MF_STRING, (uint)Command.Open, "打开 MCP Station");
        AppendMenu(menu, MF_STRING, (uint)Command.RestartCore, "重启后台服务");
        AppendMenu(menu, MF_SEPARATOR, 0, null);
        AppendMenu(menu, MF_STRING, (uint)Command.Quit, "退出（网关保持运行）");
        GetCursorPos(out var pt);
        // 不先把自己设成前台窗口，点菜单外面时菜单不会消失
        SetForegroundWindow(_hwnd);
        var cmd = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.X, pt.Y, _hwnd, IntPtr.Zero);
        DestroyMenu(menu);
        if (cmd != 0) Invoked?.Invoke((Command)cmd);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var d = Data(0);
        Shell_NotifyIcon(NIM_DELETE, ref d);
        RemoveWindowSubclass(_hwnd, _proc, 1);
        if (_icon != IntPtr.Zero) DestroyIcon(_icon);
    }

    // MARK: Win32

    private delegate IntPtr SubclassProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, IntPtr data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "Shell_NotifyIconW")]
    private static extern bool Shell_NotifyIcon(uint msg, ref NOTIFYICONDATAW data);
    [DllImport("comctl32.dll")] private static extern bool SetWindowSubclass(IntPtr hwnd, SubclassProc proc, uint id, IntPtr data);
    [DllImport("comctl32.dll")] private static extern bool RemoveWindowSubclass(IntPtr hwnd, SubclassProc proc, uint id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr LoadImage(IntPtr hinst, string name, uint type, int cx, int cy, uint load);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "AppendMenuW")] private static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string? text);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenuEx(IntPtr menu, uint flags, int x, int y, IntPtr hwnd, IntPtr tpm);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
}
