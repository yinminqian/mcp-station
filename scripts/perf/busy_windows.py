#!/usr/bin/env python3
"""从 runloop-events 的 TSV 算主线程"忙"区间:waiting_for_events END → 下一次 waiting_for_events START。
用法:busy_windows.py <runloop.tsv> [最小毫秒=30] [起始秒=4.5]
输出:start_s  dur_ms  (供人看,也供其他脚本 import)
"""
import csv, sys

def busy(path, min_ms=30.0, after_s=4.5):
    out, t_end = [], None
    for r in csv.DictReader(open(path, encoding="utf-8"), delimiter="\t"):
        if r["is-main"] != "Yes" or r["interval-type"] != "waiting_for_events":
            continue
        t = int(r["timestamp"])
        if r["event-type"] == "END":
            t_end = t
        elif t_end is not None:
            d = (t - t_end) / 1e6
            if d >= min_ms and t_end / 1e9 >= after_s:
                out.append((t_end, t))
            t_end = None
    return out

def is_switch_sample(stack):
    """这个采样是不是落在 bench 的"切页"动作里(forced 模式):栈上既有 bench 帧,又有强制布局/绘制或设置 route 的帧。
    只看 bench 帧不够:第 2 步的 bench 在开头有激活窗口、结尾有打印和退出,它们不是切页。"""
    return ("runSwitchBench" in stack or "Snapshotter" in stack) and (
        "layoutSubtreeIfNeeded" in stack or "displayIfNeeded" in stack or "route.setter" in stack)

if __name__ == "__main__":
    mn = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
    af = float(sys.argv[3]) if len(sys.argv) > 3 else 4.5
    for s, e in busy(sys.argv[1], mn, af):
        print(f"{s/1e9:.3f}\t{(e-s)/1e6:.0f}")
