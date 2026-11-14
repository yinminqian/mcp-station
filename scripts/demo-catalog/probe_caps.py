"""对 8090 上每个 MCP 做 initialize + 各类 list，统计它实际用到哪些能力。只读，不调用任何工具。"""
import json, sys, urllib.request

NAMES = sys.argv[1:]
BASE = "http://127.0.0.1:8090/servers/{}/mcp"
H = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def post(url, body, sid=None):
    h = dict(H)
    if sid:
        h["mcp-session-id"] = sid
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        sid = r.headers.get("mcp-session-id") or sid
        raw = r.read().decode()
    msg = None
    if raw.lstrip().startswith("{"):
        msg = json.loads(raw)
    else:
        for line in raw.splitlines():
            if line.startswith("data:"):
                d = json.loads(line[5:])
                if "id" in d:
                    msg = d
    return msg, sid


for n in NAMES:
    url = BASE.format(n)
    try:
        init, sid = post(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "probe", "version": "0"}}})
        res = init.get("result", {})
        caps = res.get("capabilities", {})
        post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
        out = {"caps": sorted(caps), "instr_len": len(res.get("instructions") or "")}
        for i, m in enumerate(["tools/list", "prompts/list", "resources/list", "resources/templates/list"], 2):
            key = m.split("/")[0] if m != "resources/templates/list" else "resourceTemplates"
            if m.split("/")[0] not in caps:
                continue
            r, _ = post(url, {"jsonrpc": "2.0", "id": i, "method": m, "params": {}}, sid)
            body = (r or {}).get("result", {})
            k = {"tools/list": "tools", "prompts/list": "prompts", "resources/list": "resources",
                 "resources/templates/list": "resourceTemplates"}[m]
            out[k] = len(body.get(k, []))
        print(n, json.dumps(out, ensure_ascii=False))
    except Exception as e:
        print(n, "ERROR", type(e).__name__, str(e)[:120])
