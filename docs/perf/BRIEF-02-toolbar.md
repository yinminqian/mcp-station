# 任务 02：验收第 1 步（工具栏上提）

规则同任务 01：你只测，不改 `app/` 源码，不重新构建（我构建好了冻结的副本）。报告写到 `docs/perf/REPORT-02-toolbar.md`，最后一行 `STATUS: DONE` 或 `STATUS: BLOCKED: <原因>`。

## 被测对象（都用这两个冻结副本，背靠背、交替运行）

| 名称 | 路径（Mac） | sha256 前 16 位 |
|---|---|---|
| 基线 | `/Users/yinminqian/Code/iHealth/mcp-mac/build-baseline/MCP Mac.app` | `fbde70a18d0dac3d` |
| 第 1 步 | `/Users/yinminqian/Code/iHealth/mcp-mac/build-step1/MCP Mac.app` | `e865188807e0a776` |

主题用参数域：`MCPMac -appearance.theme glass`（只测 glass；bento 这一步没改）。

## 第 1 步改了什么

- glass 的工具栏、搜索框原来由每个页面各自声明，现在只在 `GlassRoot`（切页时不重新求值的那一层）声明一次，工具项集合固定：左侧筛选菜单、中间分段 Picker（同一个 Picker，按分区换段；概览/设置没有分段时 opacity 0 占位）、右侧主操作 + 更多菜单、固定间隔、新建服务按钮。
- 页面里的 `.toolbar` / `.searchable` 全部删除；`navigationTitle/Subtitle` 仍在随切页求值的 `GlassDetail` 上。
- 分段标题去掉了计数。

## 基准测试有变化（只在第 1 步副本里有）

- `MCPMAC_SWITCH_MODE=natural`（默认）：只设 route，计时到主线程下一次进入空闲；`forced`：与基线相同的强制同步布局。
- `MCPMAC_SWITCH_COUNT=<n>`；首次/再次进入分开打印：`bench[mode] <route>: first X | again a b c ms`。
- 每次切页有 os_signpost 区间：subsystem `com.example.mcp-mac`，category `perf`，name `switch`，message 是 route。
- 找不到可见窗口时退出码 2。
- 基线副本只有旧的 forced bench，对比请用 **forced**，或用你的 runloop 忙区间方法（两边都适用）。

## 要你回答

1. 背靠背（交替跑，各 3 轮）glass 每页忙区间中位数：基线 vs 第 1 步。
2. 第 1 步里，切页时**还有没有 NSToolbar 重建**：`ToolbarBridge.preferencesDidChange`、`makeStorage`、`AppKitToolbarStrategy.makeContent`、`-[NSToolbarView layout]` 每次切页各多少 ms；分段 Picker（`SystemSegmentedControl`）、搜索框各多少。如果还在重建，从调用栈看是什么触发的（比如标题变化、分段数量变化、Picker 的 selection 变化）。
3. 第 1 步里，设置页和概览页是否比基线慢、慢在哪一类（用你报告 01 第 3 节的归类）。
4. 用 natural 模式跑一次第 1 步，给出首次 / 再次进入的数字，并和 forced 对照。
5. 你的判断：下一步最该改什么。
