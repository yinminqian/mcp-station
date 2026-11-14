# 任务 01：性能基线测量（交给"大力999"会话）

你负责**测试和测量**，另一个会话（team-lead）负责改代码。你**不要修改** `app/` 下的任何源码、`scripts/build-app.sh`、`Package.swift`。
你可以新建：`docs/perf/` 下的报告，`scripts/perf/` 下的测量脚本。

## 环境

- 你在 Linux 容器里，项目在 `/workspace/iHealth/mcp-mac`（Mac 上是 `~/Code/iHealth/mcp-mac`，同一份文件）。
- 构建、运行、Instruments 只能在 Mac 上做：用你已连接的 **desktop**（Desktop Commander）MCP 的 `start_process` 在 Mac 上执行命令，路径用 Mac 路径 `/Users/yinminqian/Code/iHealth/mcp-mac`。先跑一个 `sw_vers && xcrun xctrace version` 确认通了。
- 如果 desktop MCP 不可用，停下来，在报告里写明原因，不要绕路。

## App 概况

- macOS 27 原生 SwiftUI App「MCP Mac」，两套主题：`glass`（NavigationSplitView + 原生 Table/Form）与 `bento`（自建组件）。演示数据（SimulatedCore），不连真实服务。
- 构建：`scripts/build-app.sh`（release，产物 `build/MCP Mac.app`），`--debug` 为 debug。
- 主题：`defaults write com.example.mcp-mac appearance.theme glass|bento`（直接运行 `build/MCP Mac.app/Contents/MacOS/MCPMac` 时读这个域）。
- 调试开关（环境变量）：
  - `MCPMAC_START_ROUTE=overview|mcps|services|calls|settings` 以指定页面启动
  - `MCPMAC_SWITCH_BENCH=1` 启动 4 秒后每 0.5 秒切一次页面共 16 次，stderr 打印 `bench <route>: <ms...>` 后退出。计时方式是切页后同步 `layoutSubtreeIfNeeded()+displayIfNeeded()`，**偏悲观，只适合相对比较**。
  - `MCPMAC_SNAPSHOT_DIR=<dir>` 逐页自截图后退出（不需要屏幕录制权限）。

## 已知数据（team-lead 测的）

- 空闲 CPU：去掉实时数字的 `.contentTransition(.numericText())` 后两套主题各页 0%～6%（之前 28%～60%）。
- 切页阻塞（上述 bench）：glass 115～370ms，bento 45～117ms。去掉各页 `.toolbar/.searchable` 后 glass 的 MCP 页 340→200ms、服务页 260→140ms；detail 换成同一种简单视图时 5～20ms。

## 要你做的

1. **复现**：两套主题各跑 3 次 `MCPMAC_SWITCH_BENCH=1`，给出每页中位数。
2. **Instruments**：用 SwiftUI 模板录 glass 主题的切页（可以 `xcrun xctrace record --template 'SwiftUI' --launch -- <app 可执行文件>` 配合 `MCPMAC_SWITCH_BENCH=1`，或 attach）。导出并给出：
   - Hitches / Hangs：每次切页的掉帧或卡顿时长（这才是绝对值）；
   - Long View Body Updates、**Long Representable Updates**（AppKit 桥接控件）里排前 10 的视图或类型及耗时；
   - 能定位到的话：MCP 页和服务页构建里 Form 行 / Toggle / Table / Charts 各占多少。
   如果 xctrace 需要授权或命令行导出不了某些泳道，写明卡在哪，不要猜数。
3. **空闲 CPU**：两套主题各页停留 20 秒的 CPU 平均和峰值（`top -l` 或 `ps`）。
4. **报告**写到 `docs/perf/REPORT-01-baseline.md`：方法、原始数据、结论（哪几个组件最重，按耗时排序），以及你建议 team-lead 优先改什么。最后一行写 `STATUS: DONE`（或 `STATUS: BLOCKED: <原因>`），team-lead 靠这一行判断你写完了。
