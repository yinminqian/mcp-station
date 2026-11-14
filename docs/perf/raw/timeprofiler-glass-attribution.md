# 切页窗口 15 个(主线程忙区间 ≥50ms,4.5s 之后)
   1 mcps      start=  6.027s  busy=  544ms
   2 services  start=  6.930s  busy=  493ms
   3 calls     start=  7.755s  busy=  266ms
   4 settings  start=  8.484s  busy=  161ms
   5 overview  start=  9.114s  busy=  184ms
   6 mcps      start=  9.778s  busy=  460ms
   7 services  start= 10.617s  busy=  402ms
   8 calls     start= 11.393s  busy=  365ms
   9 settings  start= 12.207s  busy=  150ms
  10 overview  start= 12.841s  busy=  219ms
  11 mcps      start= 13.595s  busy=  430ms
  12 services  start= 14.416s  busy=  395ms
  13 calls     start= 15.210s  busy=  300ms
  14 settings  start= 15.945s  busy=  149ms
  15 overview  start= 16.570s  busy=  216ms

## mcps:3 次,忙区间 544 460 430 ms,中位数 460 ms;采样 467 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| 工具栏+搜索框(NSToolbar) | 136 | 29% |
| Table/List(NSTableView) | 92 | 20% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 76 | 16% |
| CG 软件光栅化/图层绘制(未归到控件) | 60 | 13% |
| ScrollView(含 Form 的滚动容器) | 31 | 7% |
| 销毁旧页面(dealloc/autorelease) | 22 | 5% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 20 | 4% |
| CA 提交其余 | 15 | 3% |
| Form(.grouped) | 8 | 2% |
| Toggle(NSSwitch) | 3 | 1% |
| AppKit 布局/约束其余 | 2 | 0% |
| 其他 | 1 | 0% |
| 分栏/侧边栏 | 1 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 320 | 68% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 98 | 21% |
| 工具栏(任意帧) | 136 | 29% |
| 其中 搜索框 | 11 | 2% |
| 其中 工具栏里的分段 Picker | 25 | 5% |
| Table/List(任意帧) | 92 | 20% |
| 其中 自动行高测量 | 61 | 13% |
| 其中 建行/建单元格 | 16 | 3% |
| Toggle/NSSwitch(任意帧) | 13 | 3% |
| 分段/弹出按钮(任意帧) | 25 | 5% |
| Form(.grouped) 布局(任意帧) | 10 | 2% |
| ScrollView(任意帧) | 59 | 13% |
| 文字排版 CoreText(任意帧) | 18 | 4% |
| SF Symbol 图像(任意帧) | 16 | 3% |
| 毛玻璃/VisualEffect(任意帧) | 11 | 2% |
| 绘制(CG/CA display,任意帧) | 61 | 13% |
| 销毁旧页面(任意帧) | 58 | 12% |

## services:3 次,忙区间 493 402 395 ms,中位数 402 ms;采样 406 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| 工具栏+搜索框(NSToolbar) | 131 | 32% |
| CG 软件光栅化/图层绘制(未归到控件) | 82 | 20% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 59 | 15% |
| ScrollView(含 Form 的滚动容器) | 49 | 12% |
| Table/List(NSTableView) | 32 | 8% |
| 销毁旧页面(dealloc/autorelease) | 29 | 7% |
| CA 提交其余 | 8 | 2% |
| Form(.grouped) | 6 | 2% |
| 其他 | 3 | 1% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 2 | 1% |
| AppKit 布局/约束其余 | 2 | 1% |
| Picker/分段(NSSegmented/NSPopUp) | 2 | 0% |
| 分栏/侧边栏 | 1 | 0% |
| Toggle(NSSwitch) | 0 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 220 | 54% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 102 | 25% |
| 工具栏(任意帧) | 131 | 32% |
| 其中 搜索框 | 0 | 0% |
| 其中 工具栏里的分段 Picker | 21 | 5% |
| Table/List(任意帧) | 32 | 8% |
| 其中 自动行高测量 | 9 | 2% |
| 其中 建行/建单元格 | 3 | 1% |
| Toggle/NSSwitch(任意帧) | 0 | 0% |
| 分段/弹出按钮(任意帧) | 22 | 6% |
| Form(.grouped) 布局(任意帧) | 9 | 2% |
| ScrollView(任意帧) | 70 | 17% |
| 文字排版 CoreText(任意帧) | 16 | 4% |
| SF Symbol 图像(任意帧) | 24 | 6% |
| 毛玻璃/VisualEffect(任意帧) | 9 | 2% |
| 绘制(CG/CA display,任意帧) | 83 | 20% |
| 销毁旧页面(任意帧) | 64 | 16% |

## calls:3 次,忙区间 266 365 300 ms,中位数 300 ms;采样 281 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| Table/List(NSTableView) | 110 | 39% |
| 工具栏+搜索框(NSToolbar) | 73 | 26% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 51 | 18% |
| CA 提交其余 | 11 | 4% |
| 销毁旧页面(dealloc/autorelease) | 11 | 4% |
| CG 软件光栅化/图层绘制(未归到控件) | 11 | 4% |
| ScrollView(含 Form 的滚动容器) | 5 | 2% |
| AppKit 布局/约束其余 | 3 | 1% |
| Picker/分段(NSSegmented/NSPopUp) | 2 | 1% |
| Charts | 2 | 1% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 1 | 0% |
| 其他 | 1 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 225 | 80% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 33 | 12% |
| 工具栏(任意帧) | 73 | 26% |
| 其中 搜索框 | 9 | 3% |
| 其中 工具栏里的分段 Picker | 18 | 6% |
| Table/List(任意帧) | 110 | 39% |
| 其中 自动行高测量 | 92 | 33% |
| 其中 建行/建单元格 | 38 | 13% |
| 分段/弹出按钮(任意帧) | 20 | 7% |
| Form(.grouped) 布局(任意帧) | 7 | 2% |
| Charts(任意帧) | 2 | 1% |
| ScrollView(任意帧) | 9 | 3% |
| 文字排版 CoreText(任意帧) | 16 | 6% |
| SF Symbol 图像(任意帧) | 1 | 0% |
| 毛玻璃/VisualEffect(任意帧) | 4 | 2% |
| 绘制(CG/CA display,任意帧) | 12 | 4% |
| 销毁旧页面(任意帧) | 28 | 10% |

## settings:3 次,忙区间 161 150 149 ms,中位数 150 ms;采样 152 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 35 | 23% |
| Table/List(NSTableView) | 33 | 22% |
| ScrollView(含 Form 的滚动容器) | 31 | 21% |
| 销毁旧页面(dealloc/autorelease) | 18 | 12% |
| 工具栏+搜索框(NSToolbar) | 12 | 8% |
| Form(.grouped) | 8 | 5% |
| CG 软件光栅化/图层绘制(未归到控件) | 4 | 3% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 4 | 2% |
| CA 提交其余 | 3 | 2% |
| AppKit 布局/约束其余 | 2 | 1% |
| 其他 | 1 | 0% |
| Picker/分段(NSSegmented/NSPopUp) | 1 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 105 | 69% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 8 | 5% |
| 工具栏(任意帧) | 12 | 8% |
| Table/List(任意帧) | 33 | 22% |
| Toggle/NSSwitch(任意帧) | 1 | 0% |
| 分段/弹出按钮(任意帧) | 1 | 0% |
| Form(.grouped) 布局(任意帧) | 8 | 5% |
| ScrollView(任意帧) | 64 | 42% |
| 文字排版 CoreText(任意帧) | 5 | 4% |
| SF Symbol 图像(任意帧) | 1 | 0% |
| 毛玻璃/VisualEffect(任意帧) | 4 | 3% |
| 绘制(CG/CA display,任意帧) | 4 | 3% |
| 销毁旧页面(任意帧) | 67 | 44% |

## overview:3 次,忙区间 184 219 216 ms,中位数 216 ms;采样 200 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| Table/List(NSTableView) | 78 | 39% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 50 | 25% |
| 工具栏+搜索框(NSToolbar) | 21 | 10% |
| ScrollView(含 Form 的滚动容器) | 14 | 7% |
| CA 提交其余 | 10 | 5% |
| CG 软件光栅化/图层绘制(未归到控件) | 9 | 4% |
| 销毁旧页面(dealloc/autorelease) | 7 | 4% |
| AppKit 布局/约束其余 | 3 | 2% |
| Charts | 3 | 2% |
| Form(.grouped) | 3 | 1% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 2 | 1% |
| 分栏/侧边栏 | 0 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 165 | 82% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 23 | 12% |
| 工具栏(任意帧) | 21 | 10% |
| Table/List(任意帧) | 78 | 39% |
| 其中 自动行高测量 | 68 | 34% |
| 其中 建行/建单元格 | 28 | 14% |
| Form(.grouped) 布局(任意帧) | 7 | 3% |
| Charts(任意帧) | 3 | 2% |
| ScrollView(任意帧) | 21 | 11% |
| 文字排版 CoreText(任意帧) | 21 | 10% |
| SF Symbol 图像(任意帧) | 1 | 1% |
| 毛玻璃/VisualEffect(任意帧) | 3 | 2% |
| 绘制(CG/CA display,任意帧) | 10 | 5% |
| 销毁旧页面(任意帧) | 9 | 5% |
