"""由 demo-tools.json 生成 app/Sources/MCPStation/Core/DemoCatalog.swift。凭证字段只写键名，值打码。"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(HERE, "demo-tools.json")))
S = "••••••••"
# (kind, [(key, value, secret, mono)], inDefault)
defs = {
 "obsidian": ("http", [("地址","https://127.0.0.1:27124/mcp/",0,1),("CA 证书","~/mcp/obsidian-local-rest-api.crt",0,1),("Authorization","Bearer "+S,1,1)], True),
 "XcodeBuildMCP": ("npx", [("包","xcodebuildmcp@latest",0,1),("参数","mcp",0,1)], True),
 "chrome-devtools": ("npx", [("包","chrome-devtools-mcp@latest",0,1),("参数","--autoConnect",0,1)], True),
 "desktop": ("npx", [("包","@wonderwhy-er/desktop-commander@latest",0,1)], True),
 "metro": ("npx", [("包","metro-mcp@0.15.0",0,1),("参数","--port 8081 --project-root ~/Code/iHealth/nas-app --stdio-direct",0,1)], False),
 "mobile": ("npx", [("包","@mobilenext/mobile-mcp@0.0.62",0,1)], False),
 "clickhouse": ("uvx", [("包","mcp-clickhouse",0,1),("CLICKHOUSE_HOST",S,1,1),("CLICKHOUSE_USER",S,1,1),("CLICKHOUSE_PASSWORD",S,1,1)], True),
 "iterm": ("npx", [("包","iterm-mcp",0,1)], True),
 "mongodb-log": ("npx", [("包","mongodb-mcp-server",0,1),("参数","--readOnly",0,1),("MDB_MCP_CONNECTION_STRING",S,1,1)], False),
 "oss-mcp": ("npx", [("包","oss-mcp",0,1),("参数","--oss-config="+S+" --stdio",1,1)], True),
 "genimg": ("command", [("命令","/opt/homebrew/bin/python3",0,1),("参数","~/mcp/genimg_mcp.py",0,1),("JIUAN_GW_API_KEY","${JIUAN_GW_API_KEY}",0,1)], True),
 "peekaboo": ("command", [("命令","/opt/homebrew/bin/peekaboo",0,1),("参数","mcp",0,1)], True),
 "wordcraft": ("command", [("命令","~/.local/bin/wordcraft-cli",0,1),("参数","mcp",0,1)], True),
 "pencil": ("command", [("命令","/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64",0,1),("参数","--app desktop --agent claudeCodeCLI",0,1)], False),
}
def s(x): return json.dumps(x, ensure_ascii=False)
lines = ["// 由 scripts 从本机 mcp-proxy(8090) 的 tools/list 生成：真实的 MCP 名称与工具清单。",
         "// 不含任何密钥：凭证字段只保留键名，值一律打码。",
         "", "enum DemoCatalog {",
         "    struct Entry: Sendable { let name: String; let kind: MCPKind; let inDefault: Bool; let definition: [DefinitionField]; let tools: [ToolInfo]; let resources: Int; let prompts: Int; let instructions: Int }",
         "", "    static let entries: [Entry] = ["]
for name,(kind,fields,dflt) in defs.items():
    e = d[name]
    fs = ", ".join(f"DefinitionField(key: {s(k)}, value: {s(v)}, secret: {'true' if sec else 'false'}, monospaced: {'true' if mono else 'false'})" for k,v,sec,mono in fields)
    ts = ",\n                ".join(f"ToolInfo(name: {s(n)}, summary: {s(desc)})" for n,desc in e["tools"])
    lines.append(f"        Entry(name: {s(name)}, kind: .{kind}, inDefault: {'true' if dflt else 'false'},\n              definition: [{fs}],\n              tools: [\n                {ts}\n              ],\n              resources: {e['resources']}, prompts: {e['prompts']}, instructions: {e['instr']}),")
lines += ["    ]", "}", ""]
open(os.path.join(HERE, "../../app/Sources/MCPStation/Core/DemoCatalog.swift"),"w").write("\n".join(lines))
print(len(defs), "entries;", sum(len(d[n]["tools"]) for n in defs), "tools")
