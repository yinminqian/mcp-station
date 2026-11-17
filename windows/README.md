# MCP Station for Windows

Windows 版界面：WinUI 3（Windows App SDK 2.6）原生应用，C# / .NET 9。和 Mac 版一样只是内核 `mcp-core` 的一个前端——读数据目录里的 `runtime.json`，走 `/control/*` 控制接口，界面里不直接碰 MCP。

目前做了 Pastel Bento 一套界面（概览、MCP、服务、调用记录、设置），外观照 Mac 端 `ThemeBento/` 移植；Mac 的 Liquid Glass 对应的 Fluent 主题还没做。

## 和 Mac 版的不同

| | Mac | Windows |
| --- | --- | --- |
| 数据目录 | `~/Library/Application Support/MCP Station` | `%LOCALAPPDATA%\MCP Station` |
| 内核常驻 | LaunchAgent（开机自启、崩溃拉起） | App 拉起内核；设置页可以打开「开机自启」（写 `HKCU\…\Run`，登录后只进托盘） |
| 菜单栏 / 托盘 | 菜单栏图标 | 通知区域图标；关窗口只是收进托盘，退出 App 内核照常运行 |
| 更新 | Sparkle 自动下载安装 | 启动时查 GitHub Releases 上 `windows-v*` 的版本，有新版弹窗，点「下载」打开发布页 |

## 安装

从 Releases 下载 `MCP-Station-Windows-x64-<版本>.zip`，解压到任意目录，运行 `MCPStation.exe`。包里自带 .NET 和 Windows App SDK 运行时，不用另装；`mcp-core.exe` 在同一目录下。

需要 Windows 10 2004（19041）及以上，x64。

## 自己编译

需要 .NET 9 SDK 和 Rust 工具链（MSVC）。

```sh
(cd core && cargo build --release)
cd windows/MCPStation
dotnet publish -c Release -r win-x64 -p:Platform=x64 --self-contained true -o ../../build/windows/MCP-Station
cp ../../core/target/release/mcp-core.exe ../../build/windows/MCP-Station/
```

开发时直接 `dotnet build` 后运行 `bin/x64/Debug/.../MCPStation.exe`，它会在仓库的 `core/target/` 下找内核。用 `MCPSTATION_HOME=<目录>` 把数据目录指到别处，就不会碰正式的配置（内核也认这个变量）。

崩溃时异常写在数据目录的 `logs/app-crash.log`。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `Core/` | 数据模型、控制接口客户端（事件流、重连、拉起内核） |
| `State/` | 状态仓库、导航、开机自启、检查更新 |
| `Theme/` | Bento 的设计变量（`Bento.cs`）和组件 |
| `Views/` | 侧边栏和各个页面 |
| `TrayIcon.cs`、`Program.cs` | 托盘图标（Win32）、单实例入口 |
