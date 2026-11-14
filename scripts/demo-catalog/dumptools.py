"""从本机 mcp-proxy(8090) 拉取各 MCP 的工具清单：python3 -I dumptools.py <name>...（只读，不调用工具）"""
import json, sys, importlib.util
import os
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "probe_caps.py")).read().split("for n in NAMES")[0]
ns = {}; exec(src, ns); post, BASE = ns["post"], ns["BASE"]
out = {}
for n in sys.argv[1:]:
    url = BASE.format(n)
    init, sid = post(url, {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}})
    res = init["result"]; caps = res.get("capabilities", {})
    post(url, {"jsonrpc":"2.0","method":"notifications/initialized"}, sid)
    r, _ = post(url, {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}, sid)
    tools = []
    for t in r["result"]["tools"]:
        d = (t.get("description") or "").strip().split("\n")[0]
        if len(d) > 90: d = d[:88] + "…"
        tools.append([t["name"], d])
    def cnt(m, k):
        if m.split("/")[0] not in caps: return 0
        rr, _ = post(url, {"jsonrpc":"2.0","id":3,"method":m,"params":{}}, sid)
        return len((rr or {}).get("result", {}).get(k, []))
    out[n] = {"tools": tools, "resources": cnt("resources/list","resources"), "prompts": cnt("prompts/list","prompts"), "instr": len(res.get("instructions") or ""), "server": res.get("serverInfo", {})}
    print(n, len(tools), file=sys.stderr)
json.dump(out, open(os.path.join(HERE, "demo-tools.json"),"w"), ensure_ascii=False, indent=1)
