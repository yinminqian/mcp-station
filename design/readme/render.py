#!/usr/bin/env python3
"""Renders the README illustrations — four pages of the Pastel Bento window and
the architecture diagram, in English and in Chinese, from one template and
made-up MCPs, never from a real screen. Then the two hero banners, built from
three of those shots.

    python3 design/readme/render.py              # everything
    python3 design/readme/render.py en-overview  # one image

Needs Google Chrome; fonts are the system's (SF, PingFang), so run on a Mac.
"""
import html
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BUILD = os.path.join(HERE, "build")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1600, 1000          # the mock screen, in CSS px
PAGES = ["overview", "mcps", "services", "calls"]

def esc(s):
    return html.escape(str(s))

# ---------------------------------------------------------------- content

# Pastel Bento tones: fill, ink (app/Sources/MCPStation/ThemeBento/BentoTokens.swift)
TONE = {
    "lavender": ("#D9D2F9", "#40348F"),
    "sky":      ("#CDE4F6", "#1F4E74"),
    "mint":     ("#C2ECD8", "#1A5C42"),
    "peach":    ("#F9DDBD", "#7C4A12"),
    "stone":    ("#D3CBBF", "#564E44"),
}
STATUS = {"ok": "#37B877", "retry": "#EE9B3F", "error": "#E2596D", "idle": "#C6C1BA"}

# name, transport, tools, services, state, memory MB
MCPS = [
    ("chrome-devtools", "npx",  29, ["default"],          "ok",    182),
    ("github",          "HTTP", 41, ["default"],          "ok",    0),
    ("sentry",          "HTTP", 22, ["default"],          "retry", 0),
    ("filesystem",      "npx",  14, ["default"],          "ok",    64),
    ("memory",          "npx",   9, ["default"],          "ok",    38),
    ("postgres",        "uvx",   9, ["default", "data"],  "ok",    51),
    ("figma",           "HTTP", 13, ["design"],           "ok",    0),
    ("playwright",      "npx",  21, [],                   "idle",  0),
]
# name, path, tone, members, tools, sessions
SERVICES = [
    ("default", "/mcp",            "lavender", 6, 124, 3),
    ("data",    "/s/data/mcp",     "sky",      2, 23,  1),
    ("design",  "/s/design/mcp",   "mint",     2, 34,  2),
]
# time, mcp, tool, service, client, ms, ok
CALLS = [
    ("14:08:51", "chrome-devtools", "take_screenshot",   "default", "claude-code", 412,  True),
    ("14:08:47", "github",          "search_issues",     "default", "codex",       688,  True),
    ("14:08:40", "postgres",        "query",             "data",    "claude-code", 37,   True),
    ("14:08:33", "filesystem",      "read_text_file",    "default", "claude-code", 4,    True),
    ("14:08:29", "figma",           "get_screenshot",    "design",  "cursor",      1240, True),
    ("14:08:12", "sentry",          "search_issues",     "default", "codex",       30002, False),
    ("14:07:58", "memory",          "search_nodes",      "default", "claude-code", 6,    True),
    ("14:07:41", "chrome-devtools", "navigate_page",     "default", "claude-code", 931,  True),
    ("14:07:30", "postgres",        "list_tables",       "data",    "codex",       52,   True),
    ("14:07:22", "github",          "get_pull_request",  "default", "claude-code", 544,  True),
    ("14:07:05", "figma",           "get_design_context","design",  "cursor",      2104, True),
    ("14:06:49", "filesystem",      "list_directory",    "default", "codex",       3,    True),
    ("14:06:31", "chrome-devtools", "list_pages",        "default", "claude-code", 18,   True),
    ("14:06:12", "memory",          "create_entities",   "default", "claude-code", 9,    True),
    ("14:05:58", "github",          "list_commits",      "default", "codex",       702,  True),
    ("14:05:40", "postgres",        "query",             "data",    "claude-code", 129,  True),
]
# calls per hour, stacked by service (default, data, design)
HOURS = [("07", 18, 4, 0), ("08", 64, 12, 8), ("09", 142, 30, 21), ("10", 188, 41, 37),
         ("11", 121, 22, 30), ("12", 46, 8, 3), ("13", 160, 36, 44), ("14", 211, 52, 38)]

STR = {
    "en": {
        "tagline": "Local MCP gateway", "overview": "Overview", "mcps": "MCPs", "services": "Services",
        "calls": "Calls", "settings": "Settings",
        "calls_title": "Calls · last 8 hours", "times": "{n} calls", "failed": "{n} failed",
        "mem_title": "Memory · total", "core": "mcp-core",
        "recent": "Recent calls", "time": "Time", "mcp": "MCP", "tool": "Tool", "service": "Service",
        "client": "Client", "dur": "Duration", "result": "Result", "ok": "Succeeded", "fail": "Failed",
        "running": "Background service running", "pid": "pid 4242 · up 3 h 12 min",
        "mcp_ok": "{a} / {b} OK", "attention": "Needs attention",
        "retry_in": "Waiting to retry {s}s", "retry_note": "Can't reach its upstream; retries on its own.",
        "my_services": "My services", "svc_meta": "{m} MCPs · {t} tools", "sessions": "{n} sessions",
        "count": "{n}", "add": "Add MCP", "search": "Search MCPs", "all": "All",
        "tools_n": "{n} tools", "no_service": "No service uses it", "default": "default",
        "waiting": "Waiting to retry", "retry_now": "Retry Now",
        "tab_overview": "Overview", "tab_tools": "Tools · {n}", "tab_logs": "Logs", "tab_calls": "Calls",
        "retry_head": "Can't reach the upstream — retrying in 40 seconds (7 attempts so far)",
        "retry_body": "connect https://mcp.sentry.dev/mcp: connection timed out.",
        "retry_foot": "The other 7 MCPs are unaffected",
        "definition": "Definition", "type": "Type", "url": "URL", "used_by": "Used by services",
        "own": "Own address", "logs": "Recent logs (stderr)",
        "svc_page": "Services", "new_service": "New service",
        "default_name": "Default", "all_on": "= every MCP that is switched on",
        "members": "Members", "agg": "Aggregated tools", "merged": "Merged instructions",
        "included": "Included MCPs", "client_cfg": "Client config", "local": "Local terminal",
        "container": "Container", "json": "JSON", "copy": "Copy config",
        "hint": "Run once in a terminal; the gateway listens on 127.0.0.1 only",
        "checks": "Checks", "tool_names": "Tool names", "longest": "Longest is 41 characters (limit 64)",
        "conflicts": "Name conflicts", "none": "None — every tool is prefixed with its MCP",
        "status": "MCP status", "one_retry": "1 waiting to retry",
        "calls_page": "Calls", "failures": "Failures",
        "arch_clients": "Clients", "arch_gateway": "MCP Station gateway", "arch_mcps": "MCPs — one copy each",
        "arch_core": "mcp-core background service · starts at login · restarted if it crashes",
        "c1": ("Claude Code", "terminal"), "c2": ("Codex", "terminal"), "c3": ("Cursor and others", "mcpServers config"),
        "c4": ("Agents in containers", "host.docker.internal"),
        "r1": "Default service: every MCP switched on", "r2": "A service you put together",
        "r3": "One MCP, tool names unchanged",
        "feat": ["Aggregates tools", "Merges instructions", "Forwards progress & cancel", "Records every call"],
        "m4": ("your own command", "uvx / any executable"), "remote": "remote HTTP",
    },
    "zh": {
        "tagline": "本机 MCP 网关", "overview": "概览", "mcps": "MCP", "services": "服务",
        "calls": "调用", "settings": "设置",
        "calls_title": "调用 · 近 8 小时", "times": "{n} 次", "failed": "{n} 次失败",
        "mem_title": "内存 · 合计", "core": "mcp-core",
        "recent": "最近的调用", "time": "时间", "mcp": "MCP", "tool": "工具", "service": "服务",
        "client": "客户端", "dur": "耗时", "result": "结果", "ok": "成功", "fail": "失败",
        "running": "后台服务运行中", "pid": "pid 4242 · 已运行 3 小时 12 分",
        "mcp_ok": "{a} / {b} 正常", "attention": "需要处理",
        "retry_in": "等待重试 {s}s", "retry_note": "连不上上游，会自己重试。",
        "my_services": "我的服务", "svc_meta": "{m} 个 MCP · {t} 工具", "sessions": "{n} 个会话",
        "count": "{n} 个", "add": "添加 MCP", "search": "搜索 MCP", "all": "全部",
        "tools_n": "{n} 工具", "no_service": "没有服务用到", "default": "默认",
        "waiting": "等待重试", "retry_now": "立即重试",
        "tab_overview": "概况", "tab_tools": "工具 · {n}", "tab_logs": "日志", "tab_calls": "调用",
        "retry_head": "连不上上游，40 秒后自动重试（已重试 7 次）",
        "retry_body": "connect https://mcp.sentry.dev/mcp：连接超时。",
        "retry_foot": "其他 7 个 MCP 不受影响",
        "definition": "定义", "type": "类型", "url": "地址", "used_by": "用到它的服务",
        "own": "单独地址", "logs": "最近日志（stderr）",
        "svc_page": "服务", "new_service": "新建服务",
        "default_name": "默认", "all_on": "= 所有开关打开的 MCP",
        "members": "组成", "agg": "聚合后的工具", "merged": "合并后的说明",
        "included": "包含的 MCP", "client_cfg": "客户端配置", "local": "本机终端",
        "container": "容器", "json": "JSON", "copy": "复制配置",
        "hint": "在本机终端里运行一次即可；网关只监听 127.0.0.1",
        "checks": "检查", "tool_names": "工具名", "longest": "最长 41 字符（上限 64）",
        "conflicts": "名字冲突", "none": "无（工具名都带 MCP 名前缀）",
        "status": "MCP 状态", "one_retry": "1 个等待重试",
        "calls_page": "调用", "failures": "失败",
        "arch_clients": "客户端", "arch_gateway": "MCP Station 网关", "arch_mcps": "MCP（每个只跑一份）",
        "arch_core": "mcp-core 后台服务 · 开机自启 · 崩溃自动拉起",
        "c1": ("Claude Code", "本机终端"), "c2": ("Codex", "本机终端"), "c3": ("Cursor 等", "mcpServers 配置"),
        "c4": ("容器里的 Agent", "host.docker.internal"),
        "r1": "默认服务：所有开着的 MCP", "r2": "自己挑几个 MCP 组成的服务", "r3": "单个 MCP，工具名不变",
        "feat": ["聚合工具", "合并说明", "转发进度与取消", "记录每次调用"],
        "m4": ("你自己的命令", "uvx / 本地可执行文件"), "remote": "远程 HTTP",
    },
}

def svc_name(name, lang):
    return STR[lang]["default_name"] if name == "default" else name

def svc_tone(name):
    return {s[0]: s[2] for s in SERVICES}.get(name, "stone")

# ---------------------------------------------------------------- icons

def icon(name, size=18, color="currentColor", sw=1.8):
    paths = {
        "home":    '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>',
        "plug":    '<path d="M9 2v6M15 2v6M6 8h12v3a6 6 0 0 1-12 0zM12 17v5"/>',
        "layers":  '<path d="m12 3 9 5-9 5-9-5zM3 13l9 5 9-5M3 17.5 12 22.5 21 17.5"/>',
        "wave":    '<path d="M3 12h4l3-7 4 14 3-7h4"/>',
        "sliders": '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
        "server":  '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>',
        "search":  '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
        "plus":    '<path d="M12 5v14M5 12h14"/>',
        "chev":    '<path d="m9 6 6 6-6 6"/>',
        "refresh": '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
        "copy":    '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
        "warn":    '<path d="M12 3 2 20h20zM12 10v4M12 17h.01"/>',
        "term":    '<path d="m5 7 5 5-5 5M12 18h7"/>',
        "globe":   '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
        "box":     '<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12 4 7.5"/>',
        "check":   '<path d="m5 12 5 5 9-10"/>',
    }
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{paths[name]}</svg>')

BRAND = ('<svg width="36" height="36" viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#111"/>'
         '<circle cx="18" cy="18" r="6.5" fill="none" stroke="#fff" stroke-width="3.2"/></svg>')

def dot(state, size=8):
    return f'<i class="dot" style="width:{size}px;height:{size}px;background:{STATUS[state]}"></i>'

def toggle(on):
    return f'<span class="tg{" on" if on else ""}"><b></b></span>'

# ---------------------------------------------------------------- frame

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:__W__px;height:__H__px;overflow:hidden}
body{font-family:-apple-system,system-ui,"SF Pro Text","PingFang SC",sans-serif;color:#1D1C1A;font-size:14px;position:relative;
  -webkit-font-smoothing:antialiased;
  background:radial-gradient(900px 700px at 0% 0%,#E4DDFB 0%,transparent 70%),
    radial-gradient(800px 600px at 100% 100%,#FBE3C8 0%,transparent 70%),
    radial-gradient(700px 600px at 80% 0%,#D6E9F8 0%,transparent 70%),
    radial-gradient(700px 600px at 10% 100%,#D3F1E2 0%,transparent 70%),#F3EFEA}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace}
.menubar{position:absolute;left:0;top:0;right:0;height:28px;background:#ffffff8c;backdrop-filter:blur(20px);
  display:flex;align-items:center;gap:20px;padding:0 18px;font-size:13.5px;font-weight:500}
.menubar .r{margin-left:auto;display:flex;gap:16px;align-items:center;font-weight:400}
.win{position:absolute;left:56px;top:64px;width:1488px;height:900px;border-radius:18px;background:#FBF9F6;
  box-shadow:0 40px 80px -20px #3a2a1a40,0 0 0 1px #00000014;overflow:hidden;display:flex}
.lights{position:absolute;left:18px;top:18px;display:flex;gap:8px;z-index:3}
.lights i{width:12px;height:12px;border-radius:50%}
.rail{width:212px;padding:56px 14px 16px;display:flex;flex-direction:column;gap:4px}
.brand{display:flex;align-items:center;gap:10px;padding:0 6px 22px}
.brand b{display:block;font-size:15px;font-weight:650}.brand span{font-size:12px;color:#6E6963}
.nav{display:flex;align-items:center;gap:10px;height:40px;padding:0 10px;border-radius:12px;color:#1D1C1A;font-size:14.5px;font-weight:500}
.nav.sel{background:#EAE6E0}
.nav .ic{width:30px;height:30px;border-radius:50%;display:grid;place-items:center;background:#fff;box-shadow:0 0 0 1px #0000000d}
.nav.sel .ic{background:#111;color:#fff;box-shadow:none}
.rail .grow{flex:1}
.rail .st{display:flex;align-items:center;gap:8px;font-size:12px;color:#6E6963;padding:8px 10px}
.main{flex:1;padding:20px 20px 20px 4px;display:flex;gap:16px;min-width:0}
.card{background:#fff;border-radius:22px;padding:18px 20px;box-shadow:0 0 0 1px #0000000a}
.label{font-size:12.5px;color:#6E6963;font-weight:500}
.big{font-size:34px;font-weight:600;letter-spacing:-.5px;font-variant-numeric:tabular-nums}
.pill{display:inline-flex;align-items:center;gap:6px;height:24px;padding:0 10px;border-radius:99px;font-size:12px;font-weight:500;background:#F2EFEA;color:#6E6963;white-space:nowrap}
.dot{display:inline-block;border-radius:50%;flex:none}
.tg{width:38px;height:22px;border-radius:99px;background:#DCD7D0;position:relative;flex:none}
.tg b{position:absolute;left:2px;top:2px;width:18px;height:18px;border-radius:50%;background:#fff;box-shadow:0 1px 2px #0003}
.tg.on{background:#111}.tg.on b{left:18px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{font-size:12px;color:#A5A099;font-weight:500;text-align:left;padding:0 8px 8px}
td{padding:0 8px;height:34px;border-top:1px solid #F0EDE8;white-space:nowrap;font-variant-numeric:tabular-nums}
td.n{text-align:right}th.n{text-align:right}
.tag{display:inline-flex;align-items:center;height:20px;padding:0 8px;border-radius:99px;font-size:11.5px;font-weight:500}
.ph{display:flex;align-items:center;gap:12px;margin-bottom:14px}
.ph h1{font-size:30px;font-weight:600;letter-spacing:-.4px}
.btn{display:inline-flex;align-items:center;gap:6px;height:34px;padding:0 14px;border-radius:99px;font-size:13px;font-weight:600;background:#fff;box-shadow:0 0 0 1px #0000000f}
.btn.ink{background:#111;color:#fff;box-shadow:none}
.tabs{display:inline-flex;gap:2px;padding:4px;border-radius:99px;background:#fff;box-shadow:0 0 0 1px #0000000a}
.tabs span{height:32px;padding:0 16px;border-radius:99px;display:flex;align-items:center;font-size:13.5px;font-weight:500;color:#6E6963}
.tabs span.on{background:#111;color:#fff}
.kv{display:grid;grid-template-columns:150px 1fr;row-gap:14px;font-size:13.5px}
.kv dt{color:#6E6963}
.log{background:#1E1D1B;color:#E9E6E1;border-radius:22px;padding:18px 22px;font-size:12.5px;line-height:1.85}
.log .t{color:#9C978F}.log .e{color:#FF9A93}.log .w{color:#F5C875}
"""

def window(lang, page, content):
    s = STR[lang]
    items = [("overview", "home"), ("mcps", "plug"), ("services", "layers"), ("calls", "wave")]
    nav = "".join(f'<div class="nav{" sel" if k == page else ""}"><span class="ic">{icon(i, 16)}</span>{s[k]}</div>'
                  for k, i in items)
    rail = (f'<div class="rail"><div class="brand">{BRAND}<div><b>MCP Station</b><span>{s["tagline"]}</span></div></div>'
            f'{nav}<div class="grow"></div>'
            f'<div class="nav"><span class="ic">{icon("sliders", 16)}</span>{s["settings"]}</div>'
            f'<div class="st">{dot("ok", 7)}<span class="mono">127.0.0.1:8090</span></div></div>')
    lights = '<div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>'
    menubar = ('<div class="menubar"><span style="font-size:16px"></span><b>MCP Station</b><span>File</span><span>Edit</span>'
               '<span>View</span><span>Window</span><span class="r"><span>Fri 14 Nov  14:09</span></span></div>')
    return menubar + f'<div class="win">{lights}{rail}<div class="main">{content}</div></div>'

# ---------------------------------------------------------------- pages

def calls_table(lang, rows, cols=("time", "mcp", "tool", "service", "client", "dur", "result")):
    s = STR[lang]
    head = "".join(f'<th class="{"n" if c == "dur" else ""}">{s[c]}</th>' for c in cols)
    body = ""
    for t, m, tool, svc, client, ms, ok in rows:
        cells = {
            "time": f'<td class="mono" style="color:#6E6963">{t}</td>',
            "mcp": f"<td>{m}</td>",
            "tool": f'<td class="mono">{tool}</td>',
            "service": f'<td><span class="tag" style="background:{TONE[svc_tone(svc)][0]};color:{TONE[svc_tone(svc)][1]}">{svc_name(svc, lang)}</span></td>',
            "client": f'<td style="color:#6E6963">{client}</td>',
            "dur": f'<td class="n mono">{(str(ms) + " ms") if ms < 1000 else f"{ms/1000:.1f} s"}</td>',
            "result": f'<td>{dot("ok" if ok else "error", 7)} <span style="color:{"#6E6963" if ok else "#E2596D"}">{s["ok"] if ok else s["fail"]}</span></td>',
        }
        body += "<tr>" + "".join(cells[c] for c in cols) + "</tr>"
    return f"<table><tr>{head}</tr>{body}</table>"

def bars(height=190):
    peak = max(a + b + c for _, a, b, c in HOURS)
    out = ""
    for i, (h, a, b, c) in enumerate(HOURS):
        cur = i == len(HOURS) - 1
        segs = ""
        for v, tone in ((c, "mint"), (b, "sky"), (a, "lavender")):
            if v:
                segs += f'<i style="height:{max(4, v / peak * height)}px;background:{TONE[tone][0]}"></i>'
        out += (f'<div class="bar{" cur" if cur else ""}"><div class="stack">{segs}</div>'
                f'<span class="{"hcur" if cur else ""}">{h}</span></div>')
    return out

def page_overview(lang):
    s = STR[lang]
    css = """
.ov{flex:1;display:flex;flex-direction:column;gap:12px;min-width:0}
.row2{display:flex;gap:12px}.row2 .card{flex:1}
.chart{display:flex;align-items:flex-end;gap:12px;height:230px;margin-top:10px}
.bar{flex:1;display:flex;flex-direction:column;align-items:center;gap:8px}
.stack{width:100%;display:flex;flex-direction:column;gap:3px;justify-content:flex-end;border-radius:12px;padding:3px}
.stack i{display:block;border-radius:9px}
.bar.cur .stack{background:#F2EFEA;box-shadow:0 0 0 4px #F2EFEA}
.bar span{font-size:12px;color:#A5A099;height:22px;display:flex;align-items:center;padding:0 8px;border-radius:99px}
.bar span.hcur{background:#111;color:#fff}
.legend{display:flex;gap:16px;font-size:12px;color:#6E6963;margin-top:10px}
.legend i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}
.mem{display:flex;flex-direction:column;gap:13px;margin-top:16px}
.mem div{display:grid;grid-template-columns:130px 1fr 64px;align-items:center;gap:12px;font-size:13px}
.mem u{display:block;height:8px;border-radius:99px;background:#D9D2F9;text-decoration:none}
.mem em{font-style:normal;text-align:right;color:#6E6963;font-variant-numeric:tabular-nums}
.side{width:340px;flex:none;background:#F2EFEA;border-radius:26px;padding:16px;display:flex;flex-direction:column;gap:12px}
.coreb{display:flex;flex-direction:column;align-items:center;gap:6px;padding:10px 0 4px}
.coreb .c{width:58px;height:58px;border-radius:50%;background:#111;color:#fff;display:grid;place-items:center;margin-bottom:6px}
.coreb b{font-size:16px;font-weight:600;display:flex;align-items:center;gap:8px}
.coreb span{font-size:12.5px;color:#6E6963}
.srow{background:#fff;border-radius:16px;height:48px;display:flex;align-items:center;gap:10px;padding:0 14px;font-size:14px;font-weight:500}
.srow .r{margin-left:auto;display:flex;align-items:center;gap:6px;color:#6E6963;font-weight:400;font-size:13px}
.svc{border-radius:18px;padding:14px 16px;display:flex;align-items:center;gap:12px}
.svc .ic{width:34px;height:34px;border-radius:50%;background:#ffffffb3;display:grid;place-items:center}
.svc b{display:block;font-size:14.5px;font-weight:600}.svc code{font-size:12.5px}
.svc .r{margin-left:auto}
"""
    top = sum(a + b + c for _, a, b, c in HOURS)
    chart = (f'<div class="card"><div class="label">{s["calls_title"]}</div>'
             f'<div style="display:flex;align-items:center;gap:10px;margin-top:6px"><span class="big">{s["times"].format(n=f"{top:,}")}</span>'
             f'<span class="pill" style="background:#F7CDD1;color:#84283A">{s["failed"].format(n=3)}</span></div>'
             f'<div class="chart">{bars()}</div>'
             f'<div class="legend"><span><i style="background:#D9D2F9"></i>{svc_name("default", lang)}</span>'
             f'<span><i style="background:#CDE4F6"></i>data</span><span><i style="background:#C2ECD8"></i>design</span></div></div>')
    mems = [(m[0], m[5]) for m in MCPS if m[5]] + [(s["core"], 9)]
    mems.sort(key=lambda x: -x[1])
    peak = mems[0][1]
    memrows = "".join(f'<div><span>{n}</span><u style="width:{v / peak * 100:.0f}%"></u><em>{v} MB</em></div>' for n, v in mems)
    mem = (f'<div class="card" style="max-width:430px"><div class="label">{s["mem_title"]}</div>'
           f'<div class="big" style="margin-top:6px">{sum(v for _, v in mems)} MB</div><div class="mem">{memrows}</div></div>')
    table = f'<div class="card" style="flex:1;overflow:hidden"><div class="label" style="margin-bottom:12px">{s["recent"]}</div>{calls_table(lang, CALLS[:9])}</div>'
    svcs = ""
    for name, path, tone, m, t, _ in SERVICES:
        f, ink = TONE[tone]
        svcs += (f'<div class="svc" style="background:{f};color:{ink}"><span class="ic">{icon("layers", 16, ink)}</span>'
                 f'<div><b>{svc_name(name, lang)}</b><code class="mono">{path}</code></div>'
                 f'<span class="r pill" style="background:#ffffffb3;color:{ink}">{s["svc_meta"].format(m=m, t=t)}</span></div>')
    pf, pi = TONE["peach"]
    side = (f'<div class="side"><div class="coreb"><span class="c">{icon("server", 26, "#fff")}</span>'
            f'<b>{dot("ok", 8)}{s["running"]}</b><span>{s["pid"]}</span><span class="mono">127.0.0.1:8090</span></div>'
            f'<div class="srow">{icon("plug", 18)}MCP<span class="r">{dot("ok", 7)}{s["mcp_ok"].format(a=7, b=8)}{icon("chev", 14)}</span></div>'
            f'<div class="label" style="padding:4px 4px 0">{s["attention"]}</div>'
            f'<div class="svc" style="background:{pf};color:{pi}"><span class="ic">{icon("globe", 16, pi)}</span>'
            f'<div><b>sentry</b><span style="font-size:12.5px">{s["retry_note"]}</span></div>'
            f'<span class="r pill" style="background:#ffffffb3;color:{pi}">{s["retry_in"].format(s=40)}</span></div>'
            f'<div class="label" style="padding:4px 4px 0">{s["my_services"]}</div>{svcs}</div>')
    body = f'<div class="ov"><div class="row2">{chart}{mem}</div>{table}</div>{side}'
    return css, body

def page_mcps(lang):
    s = STR[lang]
    css = """
.list{width:380px;flex:none;display:flex;flex-direction:column;gap:8px}
.search{height:40px;border-radius:99px;background:#fff;box-shadow:0 0 0 1px #0000000a;display:flex;align-items:center;gap:8px;padding:0 14px;color:#A5A099;font-size:13.5px;flex:1}
.mrow{background:#fff;border-radius:16px;padding:12px 16px;display:flex;align-items:center;gap:12px;box-shadow:0 0 0 1px #0000000a}
.mrow.sel{box-shadow:0 0 0 2px #111}
.mrow b{display:block;font-size:14.5px;font-weight:500}.mrow span{font-size:12.5px;color:#6E6963}
.mrow .tg{margin-left:auto}
.detail{flex:1;background:#F2EFEA;border-radius:26px;padding:22px 24px;display:flex;flex-direction:column;gap:14px;min-width:0}
.alert{background:#F9DDBD;color:#7C4A12;border-radius:22px;padding:20px 22px}
.alert h3{font-size:16px;font-weight:600;display:flex;align-items:center;gap:10px;margin-bottom:10px}
.alert p{font-size:13px;line-height:1.7}
"""
    rows = ""
    for name, tr, tools, svcs, state, _ in MCPS:
        parts = [tr]
        parts.append(s["retry_in"].format(s=40) if state == "retry" else s["tools_n"].format(n=tools))
        parts.append("、".join(svc_name(x, lang) for x in svcs) if svcs else s["no_service"])
        if lang == "en":
            parts[-1] = ", ".join(svc_name(x, lang).lower() if x == "default" else x for x in svcs) if svcs else s["no_service"]
        on = "default" in svcs
        muted = ' style="opacity:.55"' if state == "idle" else ""
        rows += (f'<div class="mrow{" sel" if name == "sentry" else ""}"{muted}>{dot(state)}<div><b>{name}</b>'
                 f'<span>{" · ".join(parts)}</span></div>{toggle(on)}</div>')
    lst = (f'<div class="list"><div class="ph" style="margin-bottom:6px"><h1>MCP</h1><span class="pill">{s["count"].format(n=len(MCPS))}</span>'
           f'<span style="margin-left:auto" class="btn ink">{icon("plus", 14, "#fff", 2.2)}{s["add"]}</span></div>'
           f'<div style="display:flex;gap:8px"><div class="search">{icon("search", 16)}{s["search"]}</div>'
           f'<span class="btn">{s["all"]}</span></div>{rows}</div>')
    log = ('<div class="log mono"><div style="color:#9C978F;margin-bottom:6px">' + esc(s["logs"]) + '</div>'
           '<div><span class="t">14:08:12</span> connecting https://mcp.sentry.dev/mcp</div>'
           '<div><span class="t">14:08:42</span> <span class="e">error</span> request timed out after 30s</div>'
           '<div><span class="t">14:08:42</span> <span class="w">backoff</span> next attempt in 40s (attempt 7)</div>'
           '<div><span class="t">13:51:02</span> <span class="e">error</span> request timed out after 30s</div>'
           '<div><span class="t">09:21:05</span> handshake ok · 22 tools</div></div>')
    detail = (f'<div class="detail"><div class="ph" style="margin:0"><h1>sentry</h1>'
              f'<span class="pill" style="background:#F9DDBD;color:#7C4A12">{dot("retry", 7)}{s["waiting"]}</span>'
              f'<span style="margin-left:auto" class="btn ink">{icon("refresh", 14, "#fff", 2.2)}{s["retry_now"]}</span></div>'
              f'<div><span class="tabs"><span class="on">{s["tab_overview"]}</span><span>{s["tab_tools"].format(n=22)}</span>'
              f'<span>{s["tab_logs"]}</span><span>{s["tab_calls"]}</span></span></div>'
              f'<div class="alert"><h3>{icon("warn", 18, "#7C4A12", 2)}{s["retry_head"]}</h3>'
              f'<p class="mono">{esc(s["retry_body"])}</p><p style="margin-top:8px;opacity:.75">{s["retry_foot"]}</p></div>'
              f'<div class="card"><div class="label" style="margin-bottom:14px">{s["definition"]}</div><dl class="kv">'
              f'<dt>{s["type"]}</dt><dd>HTTP (Streamable)</dd>'
              f'<dt>{s["url"]}</dt><dd class="mono">https://mcp.sentry.dev/mcp</dd>'
              f'<dt>{s["used_by"]}</dt><dd>{svc_name("default", lang)}</dd>'
              f'<dt>{s["own"]}</dt><dd class="mono">http://127.0.0.1:8090/servers/sentry/mcp</dd></dl></div>'
              f'{log}</div>')
    return css, lst + detail

def page_services(lang):
    s = STR[lang]
    css = """
.slist{width:360px;flex:none;display:flex;flex-direction:column;gap:12px}
.scard{border-radius:22px;padding:18px 20px;display:flex;flex-direction:column;gap:6px}
.scard.sel{box-shadow:0 0 0 2px #111}
.scard .top{display:flex;align-items:center;justify-content:space-between;font-size:12.5px}
.scard b{font-size:22px;font-weight:600;margin-top:10px}
.scard span{font-size:13px}
.sdetail{flex:1;background:#F2EFEA;border-radius:26px;padding:22px 24px;display:flex;flex-direction:column;gap:14px;min-width:0}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:4px 24px;margin-top:12px}
.grid2 div{display:flex;align-items:center;gap:10px;height:32px;font-size:13.5px}
.cb{width:18px;height:18px;border-radius:6px;display:grid;place-items:center;background:#111;color:#fff;flex:none}
.cb.off{background:#fff;box-shadow:inset 0 0 0 1.5px #C6C1BA}
.cmd{display:flex;align-items:center;gap:12px;background:#F2EFEA;border-radius:14px;padding:12px 12px 12px 16px;font-size:12.5px;margin-top:12px}
.seg{display:inline-flex;gap:2px;padding:3px;border-radius:99px;background:#F2EFEA;margin-top:12px}
.seg span{height:28px;padding:0 14px;border-radius:99px;display:flex;align-items:center;font-size:13px;color:#6E6963}
.seg span.on{background:#111;color:#fff}
.chk{display:grid;grid-template-columns:150px 1fr;row-gap:12px;margin-top:12px;font-size:13.5px}
.chk dt{color:#6E6963}.chk dd{display:flex;align-items:center;gap:8px}
"""
    cards = ""
    for name, path, tone, m, t, sess in SERVICES:
        f, ink = TONE[tone]
        meta = s["svc_meta"].format(m=m, t=t)
        sub = f'{s["all_on"]}' if name == "default" else meta
        cards += (f'<div class="scard{" sel" if name == "default" else ""}" style="background:{f};color:{ink}">'
                  f'<div class="top"><code class="mono">{path}</code><span class="pill" style="background:#ffffffb3;color:{ink}">{(s["sessions"] if sess != 1 or lang == "zh" else "{n} session").format(n=sess)}</span></div>'
                  f'<b>{svc_name(name, lang)}</b><span>{meta if name == "default" else sub}</span>'
                  f'{"<span>" + s["all_on"] + "</span>" if name == "default" else ""}</div>')
    lst = (f'<div class="slist"><div class="ph" style="margin-bottom:0"><h1>{s["svc_page"]}</h1>'
           f'<span style="margin-left:auto" class="btn">{icon("plus", 14, "#111", 2.2)}{s["new_service"]}</span></div>{cards}</div>')
    members = ""
    for name, _, tools, svcs, state, _ in MCPS:
        on = "default" in svcs
        members += (f'<div><span class="cb{"" if on else " off"}">{icon("check", 12, "#fff", 3) if on else ""}</span>'
                    f'{dot(state, 7)}<span>{name}</span><span style="color:#A5A099">{tools}</span></div>')
    cmd = "claude mcp add --transport http station http://127.0.0.1:8090/mcp"
    pf = TONE["peach"]
    detail = (f'<div class="sdetail"><div class="ph" style="margin:0"><h1>{svc_name("default", lang)}</h1>'
              f'<span class="pill" style="background:#F9DDBD;color:#7C4A12">{dot("retry", 7)}{s["one_retry"]}</span></div>'
              f'<div><span class="tabs"><span class="on">{s["members"]}</span><span>{s["agg"]}</span><span>{s["merged"]}</span><span>{s["tab_calls"]}</span></span></div>'
              f'<div class="card"><div class="label">{s["included"]}</div><div class="grid2">{members}</div></div>'
              f'<div class="card"><div class="label">{s["client_cfg"]}</div>'
              f'<div class="seg"><span class="on">{s["local"]}</span><span>{s["container"]}</span><span>{s["json"]}</span></div>'
              f'<div class="cmd"><span class="mono" style="flex:1">{cmd}</span><span class="btn ink">{icon("copy", 14, "#fff", 2)}{s["copy"]}</span></div>'
              f'<div style="font-size:12.5px;color:#A5A099;margin-top:10px">{s["hint"]}</div></div>'
              f'<div class="card"><div class="label">{s["checks"]}</div><dl class="chk">'
              f'<dt>{s["tool_names"]}</dt><dd>{dot("ok", 7)}{s["longest"]}</dd>'
              f'<dt>{s["conflicts"]}</dt><dd>{dot("ok", 7)}{s["none"]}</dd>'
              f'<dt>{s["status"]}</dt><dd>{dot("retry", 7)}{s["one_retry"]}</dd></dl></div></div>')
    return css, lst + detail

def page_calls(lang):
    s = STR[lang]
    css = ".full{flex:1;display:flex;flex-direction:column;gap:12px;min-width:0}"
    body = (f'<div class="full"><div class="ph" style="margin:0"><h1>{s["calls_page"]}</h1>'
            f'<span class="tabs" style="margin-left:12px"><span class="on">{s["all"]}</span><span>{s["failures"]} · 3</span></span>'
            f'<span style="margin-left:auto;display:flex;gap:8px">'
            + "".join(f'<span class="pill" style="background:{TONE[t][0]};color:{TONE[t][1]};height:30px;padding:0 14px">{svc_name(n, lang)}</span>'
                      for n, _, t, *_ in SERVICES)
            + f'</span></div><div class="card" style="flex:1;overflow:hidden">{calls_table(lang, CALLS)}</div></div>')
    return css, body

RENDER = {"overview": page_overview, "mcps": page_mcps, "services": page_services, "calls": page_calls}

# ---------------------------------------------------------------- architecture

def architecture_html(lang):
    s = STR[lang]
    clients = "".join(f'<div class="box w"><b>{a}</b><span>{b}</span></div>' for a, b in (s["c1"], s["c2"], s["c3"], s["c4"]))
    routes = "".join(f'<div class="rt"><code class="mono">{p}</code><span>{d}</span></div>'
                     for p, d in (("/mcp", s["r1"]), ("/s/&lt;service&gt;/mcp" if lang == "en" else "/s/&lt;服务&gt;/mcp", s["r2"]),
                                  ("/servers/&lt;name&gt;/mcp" if lang == "en" else "/servers/&lt;名字&gt;/mcp", s["r3"])))
    feats = "".join(f"<em>{f}</em>" for f in s["feat"])
    mcps = "".join(f'<div class="box" style="background:{TONE[t][0]}"><b class="mono">{n}</b><span>{d}</span></div>'
                   for n, d, t in (("chrome-devtools", "npx", "lavender"), ("postgres", "uvx", "mint"),
                                   ("github", s["remote"], "sky"), (s["m4"][0], s["m4"][1], "peach")))
    arrow = '<svg width="80" height="24" viewBox="0 0 80 24"><path d="M8 12h58M56 4l12 8-12 8" fill="none" stroke="#B5AEA4" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0}}
html,body{{width:1600px;height:640px;overflow:hidden}}
body{{font-family:-apple-system,system-ui,"PingFang SC",sans-serif;-webkit-font-smoothing:antialiased;background:#FBF9F6;color:#1D1C1A;
  display:flex;align-items:center;justify-content:center;gap:8px}}
.mono{{font-family:ui-monospace,"SF Mono",Menlo,monospace}}
.col{{display:flex;flex-direction:column;gap:12px}}
.lab{{font-size:15px;color:#8A847B;font-weight:500;margin-bottom:2px}}
.box{{width:290px;border-radius:18px;padding:15px 22px;display:flex;flex-direction:column;gap:2px}}
.box.w{{background:#fff;box-shadow:0 0 0 1.5px #E6E0D7}}
.box b{{font-size:19px;font-weight:600}}.box span{{font-size:14px;color:#6E6963}}
.gw{{width:470px;background:#16151A;border-radius:28px;padding:28px 32px;display:flex;flex-direction:column;gap:18px;color:#fff}}
.gw .addr{{font-size:24px;font-weight:600}}
.rt code{{display:block;font-size:19px;color:#C2ECD8}}.rt span{{font-size:15px;color:#A7A2AE}}
.fs{{display:flex;flex-wrap:wrap;gap:8px}}.fs em{{font-style:normal;font-size:13.5px;color:#DCD8E2;background:#2C2B33;border-radius:99px;padding:5px 12px}}
.note{{font-size:14px;color:#8A847B}}
</style></head><body>
<div class="col"><div class="lab">{s["arch_clients"]}</div>{clients}</div>{arrow}
<div class="col"><div class="lab">{s["arch_gateway"]}</div><div class="gw"><div class="addr mono">127.0.0.1:8090</div>{routes}<div class="fs">{feats}</div></div>
<div class="note">{s["arch_core"]}</div></div>{arrow}
<div class="col"><div class="lab">{s["arch_mcps"]}</div>{mcps}</div>
</body></html>"""

# ---------------------------------------------------------------- hero

HERO = {
    "en": {"tag": "One copy of every MCP,<br>one gateway for every client.",
           "sub": "A menu-bar app and a small Rust core for macOS 26. Starts your MCP servers once, keeps them running, and shows every call — shared by Claude Code, Codex and the agents in your containers.",
           "chips": ["Each MCP runs once", "Crashes restart themselves", "Every call on record", "Liquid Glass or Pastel Bento"]},
    "zh": {"tag": "每个 MCP 只跑一份，<br>所有客户端连同一个网关。",
           "sub": "一个 macOS 26 菜单栏应用，加一个小小的 Rust 内核。MCP 只启动一次、挂了自动拉起、每次调用都看得见——Claude Code、Codex 和容器里的 Agent 共用。",
           "chips": ["每个 MCP 只跑一份", "挂了自动拉起", "每次调用都有记录", "Liquid Glass / Pastel Bento 两套界面"]},
}

def hero_html(lang):
    t = HERO[lang]
    chips = "".join(f'<span class="chip"><b style="background:{c}"></b>{txt}</span>'
                    for c, txt in zip(["#8B7CF0", "#37B877", "#3E8FD8", "#EE9B3F"], t["chips"]))
    cmd = 'claude mcp add --transport http station http://127.0.0.1:8090/mcp'
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0}}
html,body{{width:1600px;height:860px;overflow:hidden}}
body{{font-family:-apple-system,system-ui,"Helvetica Neue","PingFang SC",sans-serif;-webkit-font-smoothing:antialiased;color:#1D1C1A;position:relative;
  background:radial-gradient(900px 600px at 0% 0%,#E4DDFB 0%,transparent 70%),
    radial-gradient(800px 600px at 100% 100%,#FBE3C8 0%,transparent 70%),
    radial-gradient(700px 500px at 75% 5%,#D6E9F8 0%,transparent 70%),
    radial-gradient(600px 500px at 20% 100%,#D3F1E2 0%,transparent 70%),#F6F2EC}}
.copy{{position:absolute;left:88px;top:92px;width:600px}}
.brand{{display:flex;align-items:center;gap:16px}}.brand img{{width:104px;height:104px;margin-left:-8px}}
.brand h1{{font-size:76px;font-weight:800;letter-spacing:-2.5px}}
h2{{margin-top:28px;font-size:40px;line-height:1.16;font-weight:700;letter-spacing:-1px}}
p{{margin-top:20px;font-size:19px;line-height:1.55;color:#5C574F}}
.cmd{{margin-top:30px;display:inline-flex;align-items:center;gap:10px;padding:12px 16px;border-radius:14px;background:#1E1D1B;color:#E9E6E1;
  font:14px ui-monospace,"SF Mono",Menlo,monospace;box-shadow:0 10px 24px -10px #0006}}
.cmd i{{font-style:normal;color:#C2ECD8}}
.chips{{margin-top:34px;display:flex;flex-wrap:wrap;gap:10px}}
.chip{{padding:8px 14px;border-radius:99px;background:#ffffffb0;border:1px solid #1D1C1A14;font-size:14.5px;font-weight:500;color:#3D3A35}}
.chip b{{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:8px;vertical-align:1px}}
.shot{{position:absolute;border-radius:16px;overflow:hidden;box-shadow:0 30px 60px -12px #3a2a1a45,0 0 0 1px #00000012}}
.shot img{{display:block;width:100%}}
.s1{{width:600px;left:930px;top:44px;transform:rotate(3deg)}}
.s0{{width:840px;left:720px;top:250px}}
</style></head><body>
<div class="copy"><div class="brand"><img src="../icon.png"><h1>MCP Station</h1></div>
<h2>{t["tag"]}</h2><p>{t["sub"]}</p>
<div class="cmd"><i>$</i>{cmd}</div>
<div class="chips">{chips}</div></div>
<div class="shot s1"><img src="../{lang}-services.png"></div>
<div class="shot s0"><img src="../{lang}-overview.png"></div>
</body></html>"""

# ---------------------------------------------------------------- run

def shoot(html_path, png_path, w, h, keep_2x=True):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", f"--window-size={w},{h}",
                    "--virtual-time-budget=4000", f"--screenshot={png_path}", f"file://{html_path}"],
                   check=True, capture_output=True)
    if not keep_2x:   # the README shows these two to a row; 1x is plenty
        subprocess.run(["sips", "-Z", str(max(w, h)), png_path], check=True, capture_output=True)

def write(name, doc):
    path = os.path.join(BUILD, name + ".html")
    with open(path, "w") as f:
        f.write(doc)
    return path

def render_page(lang, page):
    css, body = RENDER[page](lang)
    doc = f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{CSS.replace("__W__", str(W)).replace("__H__", str(H))}{css}</style></head><body>{window(lang, page, body)}</body></html>'
    shoot(write(f"{lang}-{page}", doc), os.path.join(HERE, f"{lang}-{page}.png"), W, H, keep_2x=False)

if __name__ == "__main__":
    os.makedirs(BUILD, exist_ok=True)
    shutil.copy(os.path.join(ROOT, "app/Resources/AppIcon-512.png"), os.path.join(HERE, "icon.png"))
    only = sys.argv[1:]
    for lang in ("en", "zh"):
        for page in PAGES:
            if not only or f"{lang}-{page}" in only:
                render_page(lang, page)
                print(f"{lang}-{page}.png")
        if not only or f"architecture-{lang}" in only:
            shoot(write(f"architecture-{lang}", architecture_html(lang)), os.path.join(HERE, f"architecture-{lang}.png"), 1600, 640)
            print(f"architecture-{lang}.png")
        if not only or f"hero-{lang}" in only:
            shoot(write(f"hero-{lang}", hero_html(lang)), os.path.join(HERE, f"hero-{lang}.png"), 1600, 860)
            print(f"hero-{lang}.png")
