# 报告 01：性能基线测量

测量时间 2026-11-14 10:42～11:35，测量者"大力999"会话。没有改 `app/`、`scripts/build-app.sh`、`Package.swift`。

## 结论

1. **切页阻塞复现了，而且真实阻塞比 bench 打印的数更长。** glass 各页 bench 中位数 149～396ms，bento 62～90ms。用 Instruments 的 runloop 事件量出来的主线程连续忙碌时长（下称"忙区间"）是 glass 150～460ms、bento 91～120ms。bench 的计时在 `displayIfNeeded()` 返回时就停了，之后同一轮 runloop 里还有 26～176ms 的 CA 提交和绘制没算进去，所以它并不"偏悲观"。
2. **glass 最重的三项是工具栏重建、Table 自动行高、一段没定位到的软件绘制。** MCP 页和服务页每次切入，工具栏（含搜索框）占 131～136ms；带 Table 的页面里自动行高测量占 61～92ms；MCP 页和服务页在 CA 提交阶段还有 60～82ms 的 CPU 软件光栅化，其他页面只有 4～11ms。
3. **View body 不是瓶颈。** SwiftUI 泳道里 8 次切页共 10,461 次 body 更新，累计只占忙时长的 3.8%，App 自己的视图单次最长 3.7ms。耗时散在每次切页 1 万～4.6 万次的属性图节点创建和更新里，也就是"整页重建"本身。
4. **空闲 CPU 没问题。** 窗口在前台可见时，两套主题各页 20 秒平均 0.5%～4.5%，峰值不超过 8.6%。
5. **两处没测成，原因见"没做成的事"**：Hitches 泳道在切页期间是空的；不带强制同步布局的"自然切页"没法驱动。

## 环境

| 项 | 值 |
|---|---|
| 机器 | MacBook Pro，Apple M1 Max，10 核，32GB，内置 XDR 屏 3456×2234 |
| 系统 / 工具 | macOS 27.0.1 (26A434)，xctrace 27.2 (27B52)，SIP 关闭 |
| 被测构建 | 现成的 `build/MCP Mac.app`（release，10:27 构建，所有源码都比它旧），sha256 `fbde70a1…06644bb` |
| 机器负载 | 测量期间 load average 8.6～9.0，内存吃紧（31G 已用、有换页），Chrome 渲染进程和 WindowServer 各占 30%～60% CPU，用户同时在用这台机器 |
| 同时在跑 | `/Applications/MCP Mac.app` 的一个实例（pid 21001），没有动它 |

负载偏高，所以绝对值比 team-lead 测的高一成到两成，相对关系一致。

### 和 BRIEF 不一样的做法

- **主题用参数域传入**（`MCPMac -appearance.theme glass|bento`），没有用 `defaults write`。原因是 `/Applications` 里那个正在运行的实例读同一个 defaults 域，写进去会把它的主题也切掉。效果等价：bento 的调用栈里没有任何 NSToolbar / NSTableView 帧，数值也和 team-lead 的 bento 数据对得上。
- trace 文件放在 Mac 的 `/tmp/mcpmac-perf/`（每个约 160MB，没进仓库），导出的汇总在 `docs/perf/raw/`。

## 1. 切页 bench 复现

`MCPMAC_SWITCH_BENCH=1`，每轮每页 3 个样本。概览页每轮的第一个样本是"概览→概览"的空操作（恒为 0），已剔除。单位 ms。

| 页面 | glass 各轮中位数 | glass 全样本中位数（范围） | bento 各轮中位数 | bento 全样本中位数（范围） |
|---|---|---:|---|---:|
| 概览 | 198 / 184 / 269 / 172 | 183（165～475） | 85 / 78 / 77 | 82（59～87） |
| MCP | 412 / 353 / 387 / 404 | 396（313～449） | 94 / 80 / 90 | 90（66～163） |
| 服务 | 292 / 284 / 253 / 293 | 288（251～352） | 71 / 71 / 82 | 71（63～90） |
| 调用记录 | 254 / 228 / 242 / 251 | 247（215～286） | 64 / 75 / 61 | 64（53～87） |
| 设置 | 172 / 133 / 140 / 158 | 149（124～208） | 57 / 56 / 63 | 62（52～84） |

- glass 跑了 5 轮，**第 1 轮全是 0，作废**，所以有效的是 4 轮；bento 3 轮都有效。
- 第 1 轮全 0 的原因（推断）：bench 用 `NSApp.windows.first { $0.isVisible && $0.canBecomeMain }` 找窗口，找不到时只计 `nav.route = r` 这一句。从后台 shell 启动、不激活时，我多次实测到这个进程在当前屏幕上没有窗口（`CGWindowList` 返回 0 个），有时又有，推测和用户当时停在哪个桌面空间有关。8 次未激活的 bench 里只出现这 1 次全 0。
- 把 App 激活到前台再跑一轮 glass，数值没有明显差别（MCP 432/329/434，服务 311/269/262，调用 231/260/235，设置 150/113/127，概览 172/163/191）。
- bench 运行时 AppKit 打印了一次警告：`It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out`。说明强制同步布局发生在一次正在进行的布局里，这是 bench 自己的副作用。

## 2. Hangs：每次切页的真实阻塞

用 Time Profiler 模板录全程 bench（这个模板开销小，录制时 bench 数值和不录时一致）。忙区间 = 主线程从 runloop 被唤醒到下一次进入等待之间的时长，相邻间隔小于 5ms 的合并成一次。单位 ms。

**glass**

| 页面 | bench 打印（3 次） | 忙区间（3 次） | 忙区间中位数 | 比 bench 多出 |
|---|---|---|---:|---:|
| MCP | 399 / 332 / 304 | 544 / 460 / 430 | 460 | 126～145 |
| 服务 | 317 / 256 / 257 | 493 / 402 / 395 | 402 | 138～176 |
| 调用记录 | 216 / 314 / 228 | 266 / 365 / 300 | 300 | 50～72 |
| 概览 | 158 / 187 / 190 | 184 / 219 / 216 | 216 | 26～32 |
| 设置 | 120 / 122 / 112 | 161 / 150 / 149 | 150 | 28～41 |

Hangs 泳道（阈值 250ms）在 15 次切页里标出了 9 次：1 次 Hang（544ms），8 次 Microhang（266～462ms）。设置页和概览页的 6 次低于阈值，没被标出。另有 1 次启动阶段的 Microhang（326ms）。

**bento**（同样方法，作为对照）

| 页面 | bench 打印（3 次） | 忙区间（3 次） | 忙区间中位数 |
|---|---|---|---:|
| MCP | 122 / 66 / 56 | 167 / 99 / 87 | 99 |
| 服务 | 98 / 84 / 86 | 171 / 112 / 118 | 118 |
| 调用记录 | 93 / 78 / 79 | 130 / 120 / 109 | 120 |
| 设置 | 81 / 67 / 57 | 131 / 91 / 90 | 91 |
| 概览 | 61 / 71 / 74 | 93 / 161 / 109 | 109 |

bento 的 Hangs 泳道是 0 行。

**这组数的限制**：切页仍然是 bench 驱动的，带着强制同步布局。强制布局之后系统正常的那一轮更新可能有重复劳动，所以用户真实点击时的阻塞应该在"bench 打印值"和"忙区间"之间，我没法量到确切值。

## 3. Time Profiler 归因（glass）

把每个切页忙区间里的主线程采样（1ms 一个）按调用栈归类。归类规则：从栈底往栈顶找第一个命中具体控件的帧；都没命中再归到通用桶。每格是"每次切页的毫秒数（占该页比例）"，3 次切页平均。

| 归类 | MCP | 服务 | 调用记录 | 概览 | 设置 |
|---|---:|---:|---:|---:|---:|
| 工具栏 + 搜索框（NSToolbar） | 136（29%） | 131（32%） | 73（26%） | 21（10%） | 12（8%） |
| Table / List（NSTableView） | 92（20%） | 32（8%） | 110（39%） | 78（39%） | 33（22%） |
| SwiftUI 求值与布局（未归到控件） | 76（16%） | 59（15%） | 51（18%） | 50（25%） | 35（23%） |
| CG 软件光栅化（未归到控件） | 60（13%） | 82（20%） | 11（4%） | 9（4%） | 4（3%） |
| ScrollView（含 Form 的滚动容器） | 31（7%） | 49（12%） | 5（2%） | 14（7%） | 31（21%） |
| 销毁旧页面 | 22（5%） | 29（7%） | 11（4%） | 7（4%） | 18（12%） |
| 挂载 AppKit 视图 | 20（4%） | 2（1%） | 1（0%） | 2（1%） | 4（2%） |
| Form(.grouped) 自身布局 | 8（2%） | 6（2%） | 0 | 3（1%） | 8（5%） |
| Charts | 0 | 0 | 2（1%） | 3（2%） | 0 |
| 采样合计 | 467 | 406 | 281 | 200 | 152 |

几个子项（任意帧命中即计入，和上表有重叠）：

| 子项 | MCP | 服务 | 调用记录 | 概览 |
|---|---:|---:|---:|---:|
| Table 自动行高测量 | 61 | 9 | 92 | 68 |
| Table 建行、建单元格 | 16 | 3 | 38 | 28 |
| 工具栏里的分段 Picker | 25 | 21 | 18 | 0 |
| 搜索框 | 11 | 0 | 9 | 0 |
| Toggle（NSSwitch） | 13 | 0 | 0 | 0 |
| bench 强制同步阶段 | 320 | 220 | 225 | 165 |
| 随后的 CA 提交（不在 bench 计时内） | 98 | 102 | 33 | 23 |

### BRIEF 问的"MCP 页和服务页里 Form 行 / Toggle / Table / Charts 各占多少"

| 组件 | MCP 页（467ms） | 服务页（406ms） |
|---|---|---|
| Table | 92ms（20%），其中自动行高 61ms | 32ms（8%） |
| Toggle | 13ms（3%），多数落在 Table 的调用栈下面（表格"默认"列的开关） | 测不出（接近 0） |
| Form 行 | 分不干净。能确定的是 Form 自身布局 8ms 加它的滚动容器 31ms，约 39ms（8%）；其余混在"SwiftUI 求值与布局"的 76ms 里 | 同样分不干净。能确定的约 55ms（14%）：Form 布局 6ms 加滚动容器 49ms |
| Charts | 这页没有图表 | 这页没有图表 |

Form 分不干净的原因：macOS 上 `Form(.grouped)` 不是单个 AppKit 控件，它的开销摊在 SwiftUI 的属性图求值和 ScrollView 的 `sizeThatFits` 里，调用栈上没有能把"第几行"区分出来的帧。

### 三个值得注意的点

- **工具栏的 131～136ms 和 team-lead 的对照实验对得上**（去掉 toolbar 后 MCP 340→200、服务 260→140）。栈上是 `ToolbarBridge.preferencesDidChange → makeStorage → AppKitToolbarStrategy.makeContent` 加上 `-[NSToolbarView layout]`，也就是每次切页重新创建工具栏项再让 NSToolbar 重排。
- **Table 的自动行高**：栈是 `SwiftUITableHostCell.hostingView(_:didUpdateIdealHeight:) → noteHeightOfRowsWithIndexesChanged → _automaticRowHeightsUpdateVisibleRowViews`。每个单元格的 hosting view 上报理想高度，NSTableView 逐行重新测量。
- **那段软件光栅化没定位到具体视图。** 栈是 `CA::Transaction::commit → CA::Layer::display_ → CABackingStoreUpdate_ → CGDisplayListDrawInContextDelegate → ripc_DrawRects → A8_mark_inner`，即某个 AppKit 图层在 CPU 上往 alpha 蒙版里填矩形。它发生在回放绘制指令的阶段，栈上已经看不到是哪个视图发起的。只在 MCP 页和服务页明显（60～82ms），而且在 bench 计时之外。

## 4. SwiftUI 泳道（glass）

### 录制上的问题

- 全程 bench（15～20 秒）用 SwiftUI 模板录了 3 次，**每次都报 `Trace file had no SwiftUI data`**，所有 `swiftui-*` 表 0 行。试过给 App 副本补 `get-task-allow` 重签、用 `--time-limit` 在 App 退出前停录，都没用。
- 6 秒和 9 秒的短录制正常。所以改成两段 9 秒录制：第一段从概览启动，录到 MCP、服务、调用记录、设置；第二段用 `MCPMAC_START_ROUTE=settings` 启动，录到概览、MCP、服务、调用记录。共 8 个切页窗口。
- **开着 SwiftUI 探针时切页被拖慢到 1.5～3 倍**（MCP 721～1347ms，服务 612～680ms，调用 440～577ms，概览 445ms，设置 280ms），所以下面的毫秒只能用来排序，不是真实耗时。第一段里的 MCP（1347ms）还是进程里第一次进这个页面，带冷启动成本。

### 汇总（8 个切页窗口合计，忙时长共 5101ms）

| 更新类型 | 次数 | 累计 ms | 占忙时长 |
|---|---:|---:|---:|
| View Body Updates | 10,461 | 193 | 3.8% |
| Representable Updates | 262 | 130 | 2.5% |
| Other Updates（属性图节点） | 225,390 | 2201 | 43.2% |

单个窗口里的 Other Updates 次数（第一段录制，概览取自第二段）：MCP 约 4.6 万（冷）、服务 3.1 万、调用记录 2.7 万、概览 1.3 万、设置 1.0 万。

**View Body Updates 前 10**

| 视图 [模块] | 次数 | 累计 ms | 单次最长 ms |
|---|---:|---:|---:|
| `GroupedFormRoot` [SwiftUI] | 11 | 14.1 | 7.9 |
| `MacToolbarButton` [DesignLibrary] | 295 | 8.9 | 0.4 |
| `MacSegmentedControlItem` [DesignLibrary] | 182 | 6.9 | 1.9 |
| `Toggle` [SwiftUI] | 337 | 6.3 | 0.2 |
| `Button` [SwiftUI] | 425 | 5.8 | 0.5 |
| `TableCellModifier` [SwiftUI] | 515 | 5.1 | 0.1 |
| `StyledTextContentView` [SwiftUI] | 204 | 3.9 | 1.2 |
| `SegmentedControl` [DesignLibrary] | 49 | 3.8 | 0.6 |
| `GlassMCPPage` [MCPMac] | 1 | 3.7 | 3.7 |
| `FormCell` [SwiftUI] | 175 | 3.6 | 0.4 |

App 自己的视图只有 `GlassMCPPage`（3.7ms，1 次）进了前 10。第一段录制里其余 App 视图单次都在 1.1ms 以内（`GlassSidebar` 1.05、`GlassSettingsPage` 0.78、`GlassServiceMembers` 0.76、`GlassCallsPage` 0.72），被探针标成 High 或 Moderate 的 body 更新每个窗口只有 2～9 个。

**Representable Updates 前 10**（AppKit 桥接控件）

| 视图 [模块] | 次数 | 累计 ms | 单次最长 ms |
|---|---:|---:|---:|
| `SystemSegmentedControl` [SwiftUI]，工具栏分段 Picker | 22 | 32.0 | 16.4 |
| `AppKitOutlineTableRepresentable` [SwiftUI]，Table | 4 | 19.1 | 7.0 |
| `_ShapeView` [SwiftUI] | 2 | 15.5 | 12.5 |
| `SelectionOverlay` [SwiftUI] | 83 | 12.4 | 0.8 |
| `OpacityRendererEffect` [SwiftUI] | 5 | 12.3 | 6.6 |
| `_OpacityEffect` [SwiftUI] | 2 | 6.7 | 5.6 |
| `Switch` [SwiftUI]，Toggle 开关 | 33 | 5.9 | 0.8 |
| `Root View for Text` [SwiftUI] | 6 | 5.4 | 3.8 |
| `SearchFieldAccessoryButtonRepresentable` [AppKit]，搜索框 | 35 | 4.6 | 0.5 |
| `ModifiedContent?` [libswiftCore] | 8 | 3.9 | 1.0 |

**Other Updates 前 10**（按探针给的描述）

| 属性 | 次数 | 累计 ms | 单次最长 ms |
|---|---:|---:|---:|
| `DynamicContainerInfo<DynamicLayoutViewAdaptor>` | 1,607 | 383.8 | 7.1 |
| `Action Callback` | 4,408 | 347.5 | 27.5 |
| `Text Content` | 2,983 | 179.8 | 8.5 |
| `Platform Item list (menus, etc.)` | 2,181 | 125.5 | 56.8 |
| `PlaceholderInfo` | 293 | 91.0 | 22.8 |
| `Layout: DynamicLayoutComputer<_VStackLayout>` | 515 | 69.9 | 17.0 |
| `Image Content` | 492 | 61.8 | 4.1 |
| `External Environment` | 11,306 | 44.2 | 3.4 |
| `ShapeStyleResolver<AnyShapeStyle>` | 3,109 | 26.8 | 13.5 |
| `AnimatableFrameAttribute` | 7,414 | 24.6 | 7.0 |

`Platform Item list` 是菜单和工具栏项的偏好值传递，单次最长 56.8ms 出现在切到 MCP 页时。

每个窗口各自的前 10 在 `docs/perf/raw/swiftui-glass-rec1-top.md` 和 `swiftui-glass-rec2-top.md`。

## 5. 空闲 CPU

每页停留：启动后 8 秒预热，再用 `top -l 21 -s 1` 每秒采一次，取后 20 个。单位 %。

**窗口激活到前台、在屏可见**（用户实际看到的状态）

| 页面 | glass 平均 | glass 峰值 | bento 平均 | bento 峰值 |
|---|---:|---:|---:|---:|
| 概览 | 4.5 | 8.6 | 2.2 | 5.1 |
| MCP | 1.8 | 5.5 | 1.9 | 6.8 |
| 服务 | 1.1 | 4.8 | 0.5 | 1.9 |
| 调用记录 | 3.5 | 8.2 | 2.3 | 7.1 |
| 设置 | 0.5 | 2.0 | 0.7 | 2.4 |

- 用户在测量期间把窗口切走过几次。bento 概览第一次采样因此作废（切走那一秒冲到 24.6%），表里是重测值。bento 调用记录两次都在采样末尾被切走：表里用的是第一次（切走发生在最后一拍，没有尖峰）；第二次平均 3.1%、峰值 26.4%，尖峰同样落在窗口被切走的那一秒。
- 也就是说：**窗口失去前台的那一瞬间有一次 25% 左右的单秒尖峰**，两次都复现了。这不算空闲，但值得知道。

**不激活、留在后台**

| 页面 | glass 平均 | glass 峰值 | bento 平均 | bento 峰值 |
|---|---:|---:|---:|---:|
| 概览 | 3.4 | 7.2 | 3.3 | 18.0 |
| MCP | 1.7 | 5.4 | 1.7 | 5.3 |
| 服务 | 1.0 | 4.3 | 0.7 | 2.7 |
| 调用记录 | 3.3 | 7.1 | 1.7 | 5.7 |
| 设置 | 0.6 | 2.2 | 0.5 | 2.5 |

- 这一组 App 始终不是前台应用；窗口是否在当前屏幕上随用户切换桌面而变（每页采样前后各查一次，10 页里有的在屏、有的不在）。
- 数值和前台可见时基本一样。bento 概览的 18.0% 是第 3 秒的单拍尖峰，原因没查，其余 19 拍在 0.5%～7.5%。
- 两种状态都落在 team-lead 测的 0%～6% 附近；概览页和调用记录页（有每秒变化的数字和列表）平均比其他页高 2～3 个百分点。

## 没做成的事

| 事项 | 卡在哪 |
|---|---|
| Hitches 泳道的每次切页掉帧时长 | 4 个 trace 的 `hitches` 表合计只有 1 行（启动阶段 650ms，"Potentially expensive app update(s)"），切页期间 0 行。`hitches-frame-lifetimes` 有数据，但只记录了实际上屏的帧，推不出掉了几帧。所以绝对值只能给 Hangs 和忙区间 |
| 全程 bench 的 SwiftUI 泳道 | 超过约 10 秒的录制丢 SwiftUI 数据，见第 4 节。Apple 论坛上有同样报告（[thread 810782](https://developer.apple.com/forums/thread/810782)、[thread 826377](https://developer.apple.com/forums/thread/826377)），没有官方修复 |
| 不带强制同步布局的自然切页 | 没有辅助功能权限（`AXIsProcessTrusted()` 为 false），不能点菜单。没有用模拟按键 ⌘1～⌘5，因为用户正在用这台机器，焦点一旦被切走，按键会打到别的 App 上 |
| 软件光栅化来自哪个视图 | 命令行导出的调用栈里没有图层归属信息 |

## 建议 team-lead 优先改什么

按预期收益排序，数字是 glass 每次切页的毫秒。

1. **工具栏和搜索框固定在窗口层级**（MCP 136、服务 131、调用记录 73）。单项最大，也和你的对照实验一致。分段 Picker 是其中最贵的一个桥接控件（单次更新最长 16ms）。只把导航换成 TabView 而各页仍声明不同的工具栏，这一项不会消失。
2. **页面保活，不再整页重建**（剩下的大头：Table 32～110，SwiftUI 求值与布局 35～76，销毁加挂载 9～42）。首次进入每页的成本不会变，改完请用同样方法复测"再次进入"。
3. **查 Table 的自动行高**（MCP 61、调用记录 92、概览 68）。SwiftUI 内部符号里有 `SwiftUITableHostCell.init(rootView:useUniformHeight:)`，说明存在统一行高的路径，但什么条件会走到它我没有查证，需要你试。
4. **定位 MCP 页和服务页那 60～82ms 的软件光栅化。** 建议逐项做对照：去掉 `.alternatingRowBackgrounds()`、去掉右侧 380 宽的详情栏、去掉 `Divider()`、去掉服务页表格的 `safeAreaInset`。注意它在 bench 计时之外，bench 数字不会变，要看忙区间。
5. **空闲 CPU 不用动。**

### 希望 bench 加的东西（下一轮测量会准很多）

- 每次切页包一对 `os_signpost` 区间，Instruments 里能直接对上是哪一页。
- 加一个不调用 `layoutSubtreeIfNeeded()` / `displayIfNeeded()` 的模式，只设 `nav.route`，用来量自然切页。
- 计时改成"到主线程下一次空闲"，或者至少在 CA 提交之后再停表，否则漏掉 26～176ms。
- 找不到可见窗口时报错退出，不要静默打印 0。
- 加一个切页次数的环境变量。SwiftUI 泳道只能录 10 秒以内，现在固定 4 秒等待加 16 次切换装不下。

## 文件

| 路径 | 内容 |
|---|---|
| `scripts/perf/switch-bench.sh` | 两套主题各跑 N 轮 bench |
| `scripts/perf/idle-cpu.sh` | 空闲 CPU，可选激活到前台 |
| `scripts/perf/winstate.js` | 查看或激活某个 pid 的窗口（JXA，不需要辅助功能权限） |
| `scripts/perf/xctrace_rows.py` | xctrace 导出的 XML 转 TSV |
| `scripts/perf/tp_dump.py` | Time Profiler 采样展开成"时间 + 调用栈" |
| `scripts/perf/busy_windows.py` | 从 runloop 事件算主线程忙区间 |
| `scripts/perf/switch_profile.py` | 切页窗口内的调用栈归因（第 3 节的表） |
| `scripts/perf/swiftui_top.py` | SwiftUI 泳道每个窗口的前 N |
| `scripts/perf/tp_explore.py`、`tp_unattributed.py` | 探索用，看某个窗口或某个桶里的符号排行 |
| `docs/perf/raw/` | bench 原始输出、空闲 CPU 逐秒采样、归因和泳道汇总 |
| Mac 上 `/tmp/mcpmac-perf/*.trace` | 原始 trace，可用 Instruments 打开：`tp-glass`、`tp-bento`（Time Profiler），`gs-9`、`gs2`（SwiftUI 两段），`glass-bench`（全程，无 SwiftUI 数据） |

复现命令（在 Mac 上）：

```sh
cd ~/Code/iHealth/mcp-mac
scripts/perf/switch-bench.sh 3
scripts/perf/idle-cpu.sh 20 6 activate

BIN="$PWD/build/MCP Mac.app/Contents/MacOS/MCPMac"
xcrun xctrace record --template 'Time Profiler' --output /tmp/tp.trace \
  --env MCPMAC_SWITCH_BENCH=1 --launch -- "$BIN" -appearance.theme glass
xcrun xctrace export --input /tmp/tp.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="runloop-events"]' > /tmp/rl.xml
xcrun xctrace export --input /tmp/tp.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > /tmp/tp.xml
python3 scripts/perf/xctrace_rows.py /tmp/rl.xml /tmp/rl.tsv
python3 scripts/perf/tp_dump.py /tmp/tp.xml /tmp/samples.tsv
python3 scripts/perf/switch_profile.py /tmp/samples.tsv /tmp/rl.tsv
```

STATUS: DONE
