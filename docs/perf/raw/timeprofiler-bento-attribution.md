# 切页窗口 15 个(主线程忙区间 ≥50ms,6.2s 之后)
   1 mcps      start=  6.373s  busy=  167ms
   2 services  start=  7.015s  busy=  171ms
   3 calls     start=  7.631s  busy=  130ms
   4 settings  start=  8.210s  busy=  131ms
   5 overview  start=  8.810s  busy=   93ms
   6 mcps      start=  9.384s  busy=   99ms
   7 services  start=  9.954s  busy=  112ms
   8 calls     start= 10.543s  busy=  120ms
   9 settings  start= 11.145s  busy=   91ms
  10 overview  start= 11.709s  busy=  161ms
  11 mcps      start= 12.313s  busy=   87ms
  12 services  start= 12.867s  busy=  118ms
  13 calls     start= 13.507s  busy=  109ms
  14 settings  start= 14.150s  busy=   90ms
  15 overview  start= 14.794s  busy=  109ms

## mcps:3 次,忙区间 167 99 87 ms,中位数 99 ms;采样 110 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 59 | 53% |
| CG 软件光栅化/图层绘制(未归到控件) | 22 | 20% |
| ScrollView(含 Form 的滚动容器) | 19 | 18% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 3 | 3% |
| 销毁旧页面(dealloc/autorelease) | 2 | 2% |
| CA 提交其余 | 2 | 2% |
| 其他 | 1 | 1% |
| Charts | 1 | 1% |
| AppKit 布局/约束其余 | 1 | 1% |
| 分栏/侧边栏 | 0 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 70 | 63% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 33 | 30% |
| Charts(任意帧) | 1 | 1% |
| ScrollView(任意帧) | 19 | 18% |
| 文字排版 CoreText(任意帧) | 21 | 19% |
| SF Symbol 图像(任意帧) | 4 | 3% |
| 绘制(CG/CA display,任意帧) | 22 | 20% |
| 销毁旧页面(任意帧) | 3 | 3% |

## services:3 次,忙区间 171 112 118 ms,中位数 118 ms;采样 130 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 73 | 56% |
| ScrollView(含 Form 的滚动容器) | 30 | 23% |
| CG 软件光栅化/图层绘制(未归到控件) | 19 | 15% |
| 销毁旧页面(dealloc/autorelease) | 3 | 2% |
| 其他 | 3 | 2% |
| CA 提交其余 | 2 | 2% |
| Charts | 1 | 1% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 78 | 60% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 36 | 28% |
| Charts(任意帧) | 1 | 1% |
| ScrollView(任意帧) | 30 | 23% |
| 文字排版 CoreText(任意帧) | 18 | 14% |
| SF Symbol 图像(任意帧) | 3 | 3% |
| 绘制(CG/CA display,任意帧) | 19 | 15% |
| 销毁旧页面(任意帧) | 7 | 6% |

## calls:3 次,忙区间 130 120 109 ms,中位数 120 ms;采样 115 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 79 | 69% |
| CG 软件光栅化/图层绘制(未归到控件) | 15 | 13% |
| ScrollView(含 Form 的滚动容器) | 11 | 9% |
| 销毁旧页面(dealloc/autorelease) | 8 | 7% |
| CA 提交其余 | 2 | 2% |
| AppKit 布局/约束其余 | 0 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 79 | 69% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 32 | 28% |
| ScrollView(任意帧) | 11 | 9% |
| 文字排版 CoreText(任意帧) | 27 | 24% |
| 绘制(CG/CA display,任意帧) | 15 | 13% |
| 销毁旧页面(任意帧) | 9 | 8% |

## settings:3 次,忙区间 131 91 90 ms,中位数 91 ms;采样 95 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| ScrollView(含 Form 的滚动容器) | 44 | 47% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 35 | 36% |
| CG 软件光栅化/图层绘制(未归到控件) | 9 | 9% |
| 销毁旧页面(dealloc/autorelease) | 3 | 3% |
| CA 提交其余 | 2 | 2% |
| 其他 | 1 | 1% |
| 挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow) | 1 | 1% |
| AppKit 布局/约束其余 | 0 | 0% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 62 | 65% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 28 | 30% |
| ScrollView(任意帧) | 44 | 47% |
| 文字排版 CoreText(任意帧) | 27 | 28% |
| SF Symbol 图像(任意帧) | 1 | 1% |
| 绘制(CG/CA display,任意帧) | 9 | 9% |
| 销毁旧页面(任意帧) | 7 | 7% |

## overview:3 次,忙区间 93 161 109 ms,中位数 109 ms;采样 104 ms/次
| 独占归类 | ms/次 | 占比 |
|---|---:|---:|
| ScrollView(含 Form 的滚动容器) | 43 | 41% |
| SwiftUI 求值/布局(body、sizeThatFits、DisplayList) | 31 | 29% |
| CG 软件光栅化/图层绘制(未归到控件) | 14 | 13% |
| Charts | 7 | 7% |
| 销毁旧页面(dealloc/autorelease) | 4 | 4% |
| CA 提交其余 | 3 | 3% |
| 其他 | 2 | 2% |

| 包含标记(可重叠) | ms/次 | 占比 |
|---|---:|---:|
| bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded) | 57 | 55% |
| 随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内) | 35 | 34% |
| Charts(任意帧) | 7 | 7% |
| ScrollView(任意帧) | 43 | 42% |
| 文字排版 CoreText(任意帧) | 25 | 24% |
| SF Symbol 图像(任意帧) | 0 | 0% |
| 绘制(CG/CA display,任意帧) | 14 | 13% |
| 销毁旧页面(任意帧) | 8 | 8% |
