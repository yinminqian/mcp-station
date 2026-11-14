# 任务 04：验收 AppKit 层的页面常驻容器

规则同前：只测不改源码、不重新构建。报告写到 `docs/perf/REPORT-04-appkit-container.md`，最后一行 `STATUS: DONE` 或 `STATUS: BLOCKED: <原因>`。

## 被测对象

| 名称 | 路径（Mac） | sha256 前 16 位 |
|---|---|---|
| 第 1 步（对照） | `build-step1/MCP Mac.app` | `e865188807e0a776` |
| 第 2 步（SwiftUI ZStack 常驻，已否决，可选对照） | `build-step2/MCP Mac.app` | `47792a98a31d5674` |
| 第 3 步（AppKit 容器） | `build-step3/MCP Mac.app` | `bd1dda105fb50c7d` |

都在 `/Users/yinminqian/Code/iHealth/mcp-mac/` 下。两套主题都测。

## 第 3 步改了什么

- `Shared/KeepAlivePages.swift` 换成 AppKit 实现：`NSViewControllerRepresentable` 包一个 `tabStyle = .unspecified` 的 `NSTabViewController`，每页一个 `NSHostingController`（`sizingOptions = []`，rootView 只在创建时设一次，显式注入 store/nav/copy，不转发外层环境）。未选中的页由 NSTabView 移出窗口。bento 用 `.crossfade` 过渡（减少动态效果时不用）。
- glass 的"后台服务没运行"页盖在容器上面。bento 每页自己的根视图带上开关样式、浅色、`bentoCoreRunning`。

## 我的自测（forced，仅供参考）

- 再次进入：glass 约 175 → 约 100ms；bento 约 60 → 约 19ms（第 2 步 ZStack 是 6～16ms）。
- 全部页面访问过后停在概览页的空闲 CPU（3 轮）：glass 3.3～4.4% 对第 1 步 2.8～3.1%；bento 3.8% 对 4.5%。RSS：glass 约 223MB 对 138MB，bento 约 200MB 对 154MB。

## bench 新参数（第 3 步副本里有）

- `MCPMAC_SWITCH_ROUTES=a,b,...` 切页序列（循环）；`MCPMAC_SWITCH_DWELL_MS=<ms>` 每次切页后停留（默认 500）。
- `MCPMAC_SWITCH_STAY=<route>` 切完停在指定页（`1` 等于 overview）。
- 其余同任务 03（natural 遇到窗口遮挡会退出码 3）。

## 要你回答

1. **背靠背**（第 1 步 vs 第 3 步，可加第 2 步），两套主题每页忙区间中位数，首次 / 再次分开。门槛：glass 再次进入明显低于 150ms；bento 不比第 2 步差太多（说明差多少）。
2. **隐藏很久后切回**（阻塞项）：用 `MCPMAC_SWITCH_ROUTES=calls,overview MCPMAC_SWITCH_DWELL_MS=60000 MCPMAC_SWITCH_COUNT=4`（调用记录页每次隐藏 60 秒），切回调用记录页的忙区间。门槛：不超过调用记录页首次进入。两套主题都测。
3. **切回来时数据是最新的**：隐藏 60 秒切回后，调用记录页表格第一行的时间是不是"刚刚"（可以用 `MCPMAC_SNAPSHOT_DIR` 自截图，或 lldb 读视图，你选）。
4. **空闲 CPU 与内存**：
   - 全部页面访问过后停在概览页（`MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=overview`）vs 第 1 步停在概览页；窗口在前台可见，20 秒平均与峰值，至少 3 轮交替。门槛：不高于第 1 步（请给出差值和你判断是否在噪声内）。
   - 再测一组停在调用记录页（`STAY=calls`）。
   - **关掉主窗口后**的空闲 CPU（`MCPMAC_CLOSE_TEST=1`：启动 2 秒后关闭主窗口，进程继续运行）：第 1 步 vs 第 3 步。
   - RSS 走势（常驻后会不会继续涨）。
   - 隐藏页还有多少开销：attach Time Profiler 10 秒，对比"全部常驻"和"只开过概览"。
5. **版面**：第 3 步各页自截图（`MCPMAC_SNAPSHOT_DIR`）和第 2 步对比，有没有内容钻到工具栏下面、尺寸异常、空白。
6. 点击穿透：换成移出窗口后，按报告 03 的 lldb 方法抽查一次，确认隐藏页的视图不在窗口里。
7. 你的判断：能否装给用户试；如果空闲 CPU 仍略高，开销在哪。
