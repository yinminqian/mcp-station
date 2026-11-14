#!/usr/bin/env python3
"""背靠背汇总:读 ab-record.sh 产出的 tp-<variant>-<i>.{runloop,samples}.tsv,输出
1) 每页忙区间(首次/再次分开) 2) 独占归类对比 3) 指定符号的 inclusive 毫秒。
用法:ab_summary.py <目录> [轮次列表=1,2,3] [variants=baseline,step1] [all|first|again]\n文件名约定 tp-<variant>-<轮>.{runloop,samples}.tsv;variant 可带主题后缀(如 step1-glass)。
切页顺序两边相同:mcps,services,calls,settings,overview 循环;只取前 15 个窗口(step1 多出的第 16 次不计)。
"""
import csv, re, sys, os
from collections import defaultdict
from statistics import median
sys.path.insert(0, os.path.dirname(__file__))
from busy_windows import busy, is_switch_sample
from switch_profile import classify
csv.field_size_limit(10**9)
ROUTES = "mcps,services,calls,settings,overview".split(",")
SYMS = [
    ("ToolbarBridge.preferencesDidChange", r"ToolbarBridge\.preferencesDidChange"),
    ("ToolbarBridge.makeStorage", r"ToolbarBridge\.makeStorage"),
    ("ToolbarBridge.updateStorage", r"ToolbarBridge\.updateStorage"),
    ("AppKitToolbarStrategy.makeContent", r"AppKitToolbarStrategy\.makeContent"),
    ("-[NSToolbarView layout]", r"-\[NSToolbarView layout\]"),
    ("NSToolbarItemViewer(任意方法)", r"NSToolbarItemViewer"),
    ("AppKitToolbarItem.hostingViewDidRequestUpdate", r"AppKitToolbarItem\.hostingViewDidRequestUpdate"),
    ("工具栏(任意帧)", r"NSToolbar|ToolbarBridge|AppKitToolbar|ToolbarItem|ToolbarStrategy|AppKitSearch|NSSearch|NSTitlebar|updateToolbar"),
    ("分段控件(SystemSegmentedControl/NSSegmented*)", r"SystemSegmentedControl|NSSegment"),
    ("搜索框(AppKitSearch*/NSSearch*)", r"AppKitSearch|NSSearch|SearchField|SearchPlacement"),
    ("窗口标题/副标题(title 相关)", r"[sS]etTitle|[sS]etSubtitle|NavigationTitle|updateTitle|NSTitlebar|WindowTitle"),
    ("Table 自动行高", r"utomaticRowHeight|noteHeightOfRows|didUpdateIdealHeight"),
    ("CA 提交(CA::Transaction::commit)", r"CA::Transaction::commit"),
    ("图层绘制(CA display / CG)", r"CA::Layer::display_|CABackingStore|CGDisplayList|drawRect|ripc_"),
    ("属性图求值(AG::Graph::UpdateStack::update)", r"AG::Graph::UpdateStack::update"),
    ("NSHostingView.layout", r"NSHostingView\.layout"),
    ("sizeThatFits(任意)", r"sizeThatFits"),
    ("DisplayList.ViewUpdater(把显示列表同步到 AppKit 视图)", r"DisplayList\.ViewUpdater"),
    ("透明度/RendererEffect", r"OpacityRendererEffect|_OpacityEffect|RendererEffect|setAlphaValue|setOpacity"),
    ("环境值下发(updateEnvironment/adoptEnvironment)", r"updateEnvironment|coreUpdateEnvironment|adoptEnvironment|EnvironmentBox"),
    ("偏好值(updatePreferences/preferencesDidChange)", r"updatePreferences|preferencesDidChange|didChangePreferences"),
    ("子视图增删/重排(addSubview/_setSuperview/sortSubviews)", r"_AppKitAddSubview|swiftui_addManagedSubview|_setSuperview|addSubview|sortSubviews|removeFromSuperview|viewDidMoveTo"),
    ("侧边栏列表(OutlineListCoordinator/SwiftUIOutlineListView)", r"OutlineListCoordinator|SwiftUIOutlineListView"),
    ("辅助功能(Accessibility*)", r"Accessibility|accessibility"),
    ("NSTableView(任意帧)", r"NSTableView|NSTableRow|NSOutlineView|AppKitOutlineTable|SwiftUITable|TableCellHosting"),
    ("Toggle/NSSwitch(任意帧)", r"NSSwitch|AppKitToggle"),
    ("文字(CoreText/Text.resolve/NSTextField)", r"@CoreText$|NSCoreTypesetter|CTLine|Text\.resolve|ResolvedText|NSTextField"),
    ("销毁(dealloc/autoreleasePoolPop)", r"dealloc|__deallocating_deinit|objc_autoreleasePoolPop"),
    ("keyViewLoop", r"KeyViewLoop"),
]
SYMS = [(n, re.compile(p)) for n, p in SYMS]
_symcache = {}

def symhits(stack):
    if stack not in _symcache:
        fr = stack.split("|")
        _symcache[stack] = [n for n, rx in SYMS if any(rx.search(f) for f in fr)]
    return _symcache[stack]

def windows(runloop, samples, variant):
    """切页窗口 = 含有 bench 帧(Snapshotter,forced 阶段)的主线程忙区间。
    这样每秒一次的数据刷新等无关忙区间不会混进来。基线的第 1 次是 overview→overview 空操作,出现时丢掉。"""
    merged = []
    for s, e in busy(runloop, 3.0, 4.0):
        if merged and s - merged[-1][1] < 5e6: merged[-1][1] = e
        else: merged.append([s, e])
    hits = [0] * len(merged)
    k = 0
    for row in csv.DictReader(open(samples, encoding="utf-8"), delimiter="\t"):
        if not row["thread"].startswith("Main Thread") or not is_switch_sample(row["stack"]): continue
        t = int(row["time"])
        while k < len(merged) and merged[k][1] < t: k += 1
        if k < len(merged) and merged[k][0] <= t: hits[k] += 1
    w = [(s, e) for (s, e), h in zip(merged, hits) if h >= 2]
    expect = 15 if variant.startswith("baseline") else 16
    note = ""
    if variant.startswith("baseline") and len(w) == 16: w = w[1:]; note = "(丢掉第 1 个空操作窗口)"
    if len(w) not in (15, 16): note += f" !!窗口数 {len(w)} 不符合预期 {expect}"
    return w, note

def main():
    d = sys.argv[1]; rounds = [int(x) for x in (sys.argv[2] if len(sys.argv) > 2 else "1,2,3").split(",")]
    variants = (sys.argv[3] if len(sys.argv) > 3 else "baseline,step1").split(",")
    only = sys.argv[4] if len(sys.argv) > 4 else "all"   # all | first | again:归因表只统计哪一类切页
    busy_ms = {v: {r: {"first": [], "again": []} for r in ROUTES} for v in variants}
    excl = {v: {r: defaultdict(float) for r in ROUTES} for v in variants}
    sym = {v: {r: defaultdict(float) for r in ROUTES} for v in variants}
    cnt = {v: defaultdict(int) for v in variants}
    for v in variants:
        for i in rounds:
            base = os.path.join(d, f"tp-{v}-{i}")
            w, note = windows(base + ".runloop.tsv", base + ".samples.tsv", v)
            print(f"<!-- {v} round {i}: {len(w)} windows{note}: {' '.join(f'{(e-s)/1e6:.0f}' for s, e in w)} -->")
            w = w[:15]
            tagged = []
            for k, (s, e) in enumerate(w):
                r = ROUTES[k % 5]
                kind = "first" if (k < 4) else "again"   # 每个进程里 mcps/services/calls/settings 的第 1 次是首次进入
                busy_ms[v][r][kind].append((e - s) / 1e6)
                if only in ("all", kind):
                    cnt[v][r] += 1
                    tagged.append((s, e, r))
            for row in csv.DictReader(open(base + ".samples.tsv", encoding="utf-8"), delimiter="\t"):
                if not row["thread"].startswith("Main Thread"): continue
                t = int(row["time"])
                for s, e, r in tagged:
                    if s <= t <= e:
                        wgt = int(row["weight"]) / 1e6
                        excl[v][r][classify(row["stack"])[0]] += wgt
                        for name in symhits(row["stack"]): sym[v][r][name] += wgt
                        break
    order = ["mcps", "services", "calls", "overview", "settings"]
    print("\n## 忙区间(ms)\n\n| 页面 | 版本 | 首次进入 | 再次进入 | 再次中位数 | 全部中位数 |\n|---|---|---|---|---:|---:|")
    for r in order:
        for v in variants:
            f, a = busy_ms[v][r]["first"], busy_ms[v][r]["again"]
            print(f"| {r} | {v} | {' '.join(f'{x:.0f}' for x in f) or '-'} | {' '.join(f'{x:.0f}' for x in a)} | {median(a):.0f} | {median(f + a):.0f} |")
    cats = sorted({c for v in variants for r in ROUTES for c in excl[v][r]}, key=lambda c: -sum(excl[v][r][c] for v in variants for r in ROUTES))
    print(f"\n## 独占归类(ms/次,所选轮次 {only} 切页平均;格式 " + " → ".join(variants) + ")\n\n| 归类 | " + " | ".join(order) + " |\n|---|" + "---|" * len(order))
    for c in cats:
        print(f"| {c} | " + " | ".join(" → ".join(f"{excl[v][r][c] / max(cnt[v][r], 1):.0f}" for v in variants) for r in order) + " |")
    print("| 采样合计 | " + " | ".join(" → ".join(f"{sum(excl[v][r].values()) / max(cnt[v][r], 1):.0f}" for v in variants) for r in order) + " |")
    print("\n## 指定符号 inclusive(ms/次,可重叠;格式 " + " → ".join(variants) + ")\n\n| 符号 | " + " | ".join(order) + " |\n|---|" + "---|" * len(order))
    for name, _ in SYMS:
        print(f"| `{name}` | " + " | ".join(" → ".join(f"{sym[v][r][name] / max(cnt[v][r], 1):.1f}" for v in variants) for r in order) + " |")

if __name__ == "__main__":
    main()
