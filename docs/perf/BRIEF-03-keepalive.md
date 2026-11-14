# 任务 03：验收第 2 步（页面常驻）

规则同前：只测不改源码、不重新构建。报告写到 `docs/perf/REPORT-03-keepalive.md`，最后一行 `STATUS: DONE` 或 `STATUS: BLOCKED: <原因>`。

## 被测对象

| 名称 | 路径（Mac） | sha256 前 16 位 |
|---|---|---|
| 第 1 步 | `/Users/yinminqian/Code/iHealth/mcp-mac/build-step1/MCP Mac.app` | `e865188807e0a776` |
| 第 2 步 | `/Users/yinminqian/Code/iHealth/mcp-mac/build-step2/MCP Mac.app` | `47792a98a31d5674` |

两套主题都测：`-appearance.theme glass|bento`。

## 第 2 步改了什么

- 新增 `Shared/KeepAlivePages.swift`：访问过的页面常驻在一个 ZStack 里，切换只改 **opacity、zIndex、accessibilityHidden**；每页垫一层固定不变的不透明背景挡住下面隐藏页的点击。glass 和 bento 都接入了。
- 我做的对照实验（forced，各 20 次切页）：去掉 `allowsHitTesting` 切换后 glass 再次进入从 180～330ms 降到 100～180ms，所以这个修饰符已删除；`accessibilityHidden` 的成本可以忽略；自定义环境值切换的成本小。
- 自测（forced，再次进入）：bento 47～78ms → 6～16ms；glass 约 190ms → 约 130ms。

## bench 的变化（第 2 步副本里有）

- natural 模式改成"主线程连续空闲超过 10ms 才停表"（修了你在报告 02 指出的提前停表）。
- signpost 类别改成 `.pointsOfInterest`（subsystem `com.example.mcp-mac`，name `switch`，message 是 route）。
- 测前先把窗口激活到前台，打印 `bench window onScreen=… occluded=…`；**natural 模式下窗口被遮挡会直接退出（码 3）**，因为窗口不可见时 SwiftUI 不做布局和绘制，量不到东西。forced 不受影响。
- `MCPMAC_SWITCH_STAY=1`：切完不退出，停在概览页（用来测访问过所有页面后的空闲 CPU）。
- 第 1 步副本里 natural 还是旧的（会提前停表），对比请用 forced 或你的忙区间方法。

## 要你回答

1. **背靠背**（交替，各 3 轮以上），两套主题每页忙区间中位数，**首次进入和再次进入分开**：第 1 步 vs 第 2 步。
2. **glass 再次进入还剩约 130ms，它花在哪**（按报告 01 的归类）。我特别想知道：
   - opacity 切换是否也在逐个更新 AppKit 视图（`NSHostingView`/platform view 的 alpha、layer 更新、`updateEnvironment`、`DisplayList`），占多少；
   - 工具栏内容更新（报告 02 的 15～39ms）和窗口标题、侧边栏选中各多少；
   - 隐藏页是否在切页时参与了布局（访问过的页面越多越慢吗？可以对比"首次进入第 2 页"和"全部访问过之后"）。
3. **空闲 CPU 门槛**：用第 2 步副本 + `MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=1`（切完停在概览页，所有页面都已常驻），窗口在前台可见时停留 20 秒的 CPU 平均与峰值；对照第 1 步副本停在概览页的空闲 CPU。要求第 2 步不高于第 1 步。再看一下内存（RSS）。
4. 如果你有辅助功能权限以外的办法确认"点击不会穿透到隐藏页"，请验证；没有就写明没验证。
5. 你的判断：glass 要再降一截，下一步该做什么（比如把每页放进独立 NSHostingView、在 AppKit 层切 `isHidden`；或者先处理 Table 自动行高）。
