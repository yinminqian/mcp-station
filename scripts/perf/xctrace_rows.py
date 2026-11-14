#!/usr/bin/env python3
"""把 `xctrace export --xpath ...table[@schema=X]` 的 XML 转成 TSV(解开 id/ref 去重)。
用法:xctrace_rows.py <in.xml> <out.tsv> [col1,col2,...]   列名用 schema 里的 mnemonic;不给则全列。
数值列(start-time/duration 等)输出原始值(纳秒),其余输出 fmt 文本。
"""
import re, sys
import xml.etree.ElementTree as ET

RAW = {"start-time", "duration", "event-time", "uint32", "uint64", "event-count", "sample-time", "weight"}

def main():
    src, dst = sys.argv[1], sys.argv[2]
    want = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    ids = {}
    cols = None
    def val(el):
        ref = el.get("ref")
        if ref is not None:
            return ids.get(ref, "")
        if el.tag == "sentinel":
            return ""
        v = (el.text or "") if el.tag in RAW else (el.get("fmt") or el.text or "")
        v = v.replace("\t", " ").replace("\n", " ")
        i = el.get("id")
        if i is not None:
            ids[i] = v
        for sub in el:  # 登记嵌套定义的 id
            val(sub)
        return v
    with open(src, encoding="utf-8", errors="replace") as f, open(dst, "w", encoding="utf-8") as out:
        for line in f:
            if cols is None:
                m = re.search(r"<schema.*?</schema>", line)
                if not m:
                    continue
                cols = [c.findtext("mnemonic") for c in ET.fromstring(m.group(0)).findall("col")]
                idx = [cols.index(w) for w in want] if want else list(range(len(cols)))
                out.write("\t".join(cols[i] for i in idx) + "\n")
                line = line[m.end():]
            for m in re.finditer(r"<row>.*?</row>", line):
                row = ET.fromstring(m.group(0))
                vals = [val(c) for c in row]
                out.write("\t".join(vals[i] if i < len(vals) else "" for i in idx) + "\n")

if __name__ == "__main__":
    main()
