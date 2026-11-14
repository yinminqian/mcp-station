#!/usr/bin/env python3
"""把 xctrace 导出的 time-profile 表 XML 展开成 TSV:time_ns, thread, weight_ns, stack
stack 用 '|' 分隔,叶子帧在前,每帧写成 symbol@binary。
用法:tp_dump.py <time-profile.xml> <out.tsv>
"""
import re, sys
import xml.etree.ElementTree as ET

def main():
    src, dst = sys.argv[1], sys.argv[2]
    text = {}     # id -> 文本(time/weight/thread)
    binaries = {} # id -> name
    frames = {}   # id -> "sym@bin"
    stacks = {}   # id -> "f|f|f"
    def scalar(el, raw):
        ref = el.get("ref")
        if ref is not None:
            return text.get(ref, "")
        v = (el.text or "") if raw else (el.get("fmt") or "")
        if el.get("id"):
            text[el.get("id")] = v
        return v
    def frame(el):
        ref = el.get("ref")
        if ref is not None:
            return frames.get(ref, "?")
        b = el.find("binary")
        bn = ""
        if b is not None:
            if b.get("ref") is not None:
                bn = binaries.get(b.get("ref"), "")
            else:
                bn = b.get("name") or ""
                binaries[b.get("id")] = bn
        v = f"{el.get('name') or el.get('addr')}@{bn}"
        frames[el.get("id")] = v
        return v
    def stack(el):
        ref = el.get("ref")
        if ref is not None:
            return stacks.get(ref, "")
        v = "|".join(frame(f) for f in el.findall("frame"))
        stacks[el.get("id")] = v
        return v
    with open(src, encoding="utf-8", errors="replace") as f, open(dst, "w", encoding="utf-8") as out:
        out.write("time\tthread\tweight\tstack\n")
        for line in f:
            for m in re.finditer(r"<row>.*?</row>", line):
                row = ET.fromstring(m.group(0))
                t = th = w = st = ""
                for c in row:
                    if c.tag == "sample-time": t = scalar(c, True)
                    elif c.tag == "thread": th = scalar(c, False)
                    elif c.tag == "weight": w = scalar(c, True)
                    elif c.tag in ("tagged-backtrace", "backtrace"): st = stack(c)
                    else:
                        if c.get("id"): text[c.get("id")] = c.get("fmt") or ""
                        for sub in c.iter():
                            if sub is not c and sub.tag == "process" and sub.get("id"): pass
                out.write(f"{t}\t{th}\t{w}\t{st}\n")

if __name__ == "__main__":
    main()
