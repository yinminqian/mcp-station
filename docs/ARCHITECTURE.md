# MCP Mac：架构设计（草案 v2，待确认）

本机 MCP 网关，替代 `~/mcp` 下的 mcp-proxy(8090)。形态参照 Clash：原生菜单栏 App 负责配置和查看状态，独立的 core 进程负责干活。

## 0. 要解决的问题（全部来自现网）

| 现象 | 根因 | 新架构里怎么消失 |
|---|---|---|
| 换网络后容器里的 MCP 全部 421 / 连不上 | claude2 用局域网 IP 访问；0.14 版的 Host 白名单只能写死 IP；ip-sync 遇到新 IP 就重启整个 proxy | 只监听 127.0.0.1；容器统一走 `host.docker.internal`（OrbStack 已实测能访问只监听回环地址的端口）；白名单写死三个**主机名**，不含任何 IP |
| 一个后端坏了，8090 全挂 | 所有后端共用一个 AsyncExitStack，一个失败全部失败 | 每个上游有独立的 supervisor，挂了按指数退避重启，只影响它自己 |
| 启动时没起来的后端（比如 obsidian），要等整体重启才能回来 | 启动预检直接把它剔掉了 | 不做预检；起不来就一直按退避重试，界面上显示原因 |
| 改一个配置要重启整个服务 | 进程模型决定的 | 按定义指纹比对，只重启改过的那一个 |
| 静默升级把服务弄坏 | 用 uvx 拉 proxy，版本不固定 | core 是自己编译的二进制 |
| Clash 的代理环境变量把子进程拖死 | 子进程原样继承了全部环境 | 子进程默认只拿白名单里的环境变量，**代理变量默认不传** |
| 出了问题看不到，很被动 | 没有界面 | 菜单栏实时状态、stderr 尾部、调用记录、单独重启 |
| 每加一个 MCP 都要去 CC Switch 和容器里各配一遍 | 客户端是一个 MCP 配一条 | **服务聚合**：客户端只配一条地址，背后有哪些 MCP 在 App 里开关决定（见第 1 节） |

## 1. 核心模型：MCP、开关、服务

### 实测：14 个 MCP 实际用到的能力（2026-11-13，通过 8090 探测）

| MCP | 工具 | instructions 长度 | resources | prompts |
|---|---:|---:|---:|---:|
| desktop | 25 | 786 | 2 | 0 |
| mobile | 23 | – | – | – |
| iterm | 3 | – | – | – |
| chrome-devtools | 33 | – | – | – |
| mongodb-log | 20 | – | 2 + 1 个模板 | – |
| XcodeBuildMCP | 24 | 2254 | 4 | – |
| clickhouse | 3 | 278 | 0 | 0 |
| oss-mcp | 2 | – | 0 | 0 |
| obsidian | 16 | – | 1 | – |
| genimg | 2 | – | – | – |
| peekaboo | 24 | – | 0 | 0 |
| metro | 88 | 331 | 17 | 10 |
| wordcraft | 16 | 674 | 2 | – |
| pencil | 6 | 384 | – | – |
| **合计（14 个）** | **285** | 6 个在用 | 6 个在用 | 1 个在用 |

（`claude` 容器配置里的 `open-design` 在 8090 上返回 404，属于残留配置。Claude Code 自己的 pencil 配置指向的 `/Applications/Pencil.app` 不存在，实际路径是 `/Applications/Pen.app`，所以本会话里的 Pen MCP 连不上。）

**结论：聚合不能只聚合工具。** 现有 mcp-rust 的路由只聚合工具：它自己回答 `initialize`（不带上游的 instructions），prompts/resources 直接报错，上游发来的通知只处理 `tools/list_changed`。照搬的话，XcodeBuildMCP 那 2254 字的使用说明、metro 的 17 个 resources 和 10 个 prompts 都会丢。

### 三个概念

- **MCP**：一个上游定义，包括命令或 URL、env 等。
- **开关**：每个 MCP 一个，表示**是否加入默认服务**。新加的 MCP 默认打开。
- **服务**：对外暴露的一个地址，背后是若干个 MCP。

| 服务 | 地址 | 背后有哪些 MCP |
|---|---|---|
| 默认服务 | `/mcp` | 所有开关打开的 MCP |
| 命名服务（如 `ios`、`data`） | `/s/<服务名>/mcp` | 在 App 里勾选的 MCP，**不受开关影响** |
| 单个 MCP | `/servers/<名字>/mcp` | 只有它自己的服务，工具名**不加前缀**，兼容现在的地址 |

三种地址**走同一个 router、同一套聚合逻辑**，单个 MCP 只是"只含一个 MCP、不加前缀"的服务。共享子进程只在启动时握手一次，所以 `initialize` 的回答本来就是用握手结果拼出来的，没法原样转发；只留一条路径，拿单个 MCP 的地址和 8090 对比时，验证的就是聚合用的同一套代码。

**进程什么时候运行（只有一条规则）：** 被默认服务或任一命名服务用到，就常驻运行；否则停掉。v1 不做"访问时按需启动"，因为第一次调用要冷启动 npx，容易超时。

**开关的效果：**
- **新开的 Claude 窗口**：连上时拿到的就是当前开关的状态。开了就有，关了就没有。
- **已经打开的窗口**：core 会向连在受影响服务上的会话推送 `notifications/tools/list_changed`。客户端支持的话（Claude Code 是否支持需要验证），已打开的窗口也会刷新。

**聚合时各项内容怎么合并：**

| 内容 | 怎么合并 |
|---|---|
| 工具 | 名字前缀 `<MCP 名>__<工具>`，现有逻辑 |
| instructions | 每个 MCP 的 instructions 前面加上 `## <MCP 名>` 小标题，拼在一起，在 `initialize` 时返回 |
| prompts | 名字前缀 `<MCP 名>__`，调用时按前缀路由回对应上游 |
| resources | URI 保持原样。按 `resources/list` 拿到的**精确 URI** 建"URI → 上游"表，再加上模板匹配；两个 MCP 的 URI 撞车时，在界面上报冲突 |
| 通知 | `progress` 按 `progressToken` 路由。不同会话的 token 可能重复，所以要像请求 id 一样重写；`logging` 加上来源前缀后转发 |
| sampling / elicitation | v1 不声明（和现在一样） |

**需要注意的地方：**
- **聚合后工具名全部变化。** 原来的 `mcp__desktop__x` 会变成 `mcp__mac__desktop__x`。权限设置、hooks、skills、agents、CLAUDE.md 里写死旧名字的地方都会失效，迁移时要全盘 grep 一次 `mcp__`。走单个 MCP 地址的客户端不受影响。
- **工具名长度。** 已实测：客户端里服务名叫 `mac` 时，279 个工具拼接后最长 60 个字符（`mcp__mac__mobile__mobile_long_press_on_screen_at_coordinates`），一般认为上限是 64，目前不超。每个 MCP 可以设一个短别名作为前缀；出现超长名字时，界面标红提示。
- **工具太多。** 默认服务把 279 个工具全部打开会占不少上下文（Claude Code 在工具很多时会延迟加载）。这正是开关和命名服务要解决的事。
- **instructions 合并后可能被截断。** 如果客户端对 instructions 有长度上限，合并后的内容会被截掉（XcodeBuildMCP 一个就有 2254 字）。需要验证（S5）。

## 2. 进程与文件布局

```
/Applications/MCP Mac.app            只是界面，可以随便重新编译、退出
  └─ Contents/Resources/mcp-core     安装包里带的 core，安装或升级时复制到下面

~/Library/Application Support/MCP Mac/
  bin/mcp-core          实际运行的 core（放在 App 外面，重新编译 App 不影响它）
  config.json           0600，唯一的配置来源，只由 core 读写
  runtime.json          0600，core 启动时写入：端口、pid、控制令牌、启动时间
  children.json         子进程的 pgid 列表，core 重启时用来清理残留进程
  snapshot.json         工具、prompts、resources 快照
  logs/core.log         滚动日志，有大小上限

~/Library/LaunchAgents/com.example.mcp-mac.core.plist   由 App 写入并用 launchctl 加载
```

- **后台服务用普通 LaunchAgent plist，不用 SMAppService。** 这台机器上已经有三个这样的 agent 在跑，证明可行；而且不依赖签名。v1 不签名，以后签名用用户本人的账号。
- **系统授权（录屏、辅助功能、自动化）。** 授权对象是 `bin/mcp-core` 及其子进程。core 放在 App 外面，只有 core 更新时才可能需要重新授权，重新编译 App 不会。
- **残留子进程。** core 被 `kill -9` 或者被 launchd 重启时，子进程因为在独立进程组里，不会被带走。所以 core 启动时先读 `children.json`，把还活着的旧进程组杀掉，再启动新的。`children.json` 里同时记录 pgid、进程启动时间和命令；杀之前逐项核对，防止 pid 被复用后误杀无关进程。
- **App 的"开机启动"开关**只控制登录后是否自动打开菜单栏 App，可以用 `SMAppService.mainApp`；失败也不影响 MCP。core 由 LaunchAgent 常驻，和 App 是否运行无关。

## 3. core（从 mcp-rust 复制后改造）

**保留：** `upstream/`（stdio、http、resolve）、`registry`、`router`（扩展，见下）、`northbound/`、`jsonrpc`、`audit`（只保留内存）、`catalog` 的 reload 语义。

**删除：** `db`、`auth/`、令牌、用户组、`audit_ch`，以及 sqlx、jsonwebtoken、clickhouse 依赖。

**新增或改动：**
1. **router 补齐聚合能力：** instructions 合并、prompts 和 resources 聚合、progress 和 logging 通知转发（见第 1 节）。
2. **单个 MCP 地址** `/servers/<名字>/mcp`：只含一个 MCP、不加前缀的服务，和聚合走同一个 router。
3. **按引用决定生命周期：** 上游是否运行，由"是否被任何服务引用"决定。
4. **存储换成 `config.json`：** 先写临时文件再 rename，保证原子替换；带 `version` 字段。配置有问题时 core **照常启动**，只把出问题的那一项标成"配置错误"。整个文件解析失败时，用上一份能用的备份运行，并在状态里报错。
5. **HTTP 上游支持 `ca_cert`。** obsidian 的证书带了 `IP:127.0.0.1`，已核实 rustls 能接受。
6. **环境变量分两层。** 全局的 PATH 和共享变量（首次启动时从登录 shell 读一次 PATH）加上每个 MCP 自己的 env；每个 MCP 的 env 可以用 `${全局变量}` 引用全局变量。基础白名单里去掉代理变量。
7. **安全（免登录的前提）：** 只监听 127.0.0.1；MCP 入口校验 Host 头（只认 `localhost`、`127.0.0.1`、`host.docker.internal`），带浏览器 `Origin` 头的请求一律拒绝；`/control/*` 必须带 `runtime.json` 里的令牌。
8. **需要核实并调整的上限：** 单行消息的大小上限（大截图有几 MB）、调用超时（Xcode 构建可能要好几分钟）、单个上游的并发数、MCP 名字的字符规则（要允许 `XcodeBuildMCP` 这种大小写混合）。
9. **会话失效：** core 重启后，旧会话会收到 404 和"请重新 initialize"的提示。这是规范要求的行为。Claude Code 收到后能不能自己恢复，需要验证。

## 4. config.json 格式（Swift 和 Rust 之间的约定）

```json
{
  "version": 1,
  "port": 8090,
  "env": { "PATH": "…", "JIUAN_GW_API_KEY": "…" },
  "mcps": {
    "XcodeBuildMCP": {
      "command": "npx", "args": ["-y", "xcodebuildmcp@latest", "mcp"], "env": {},
      "x": { "default": true, "alias": "xcode", "timeoutSecs": 600, "notes": "" }
    },
    "obsidian": {
      "url": "https://127.0.0.1:27124/mcp/", "headers": { "Authorization": "Bearer ${OBSIDIAN_TOKEN}" },
      "x": { "default": true, "caCert": "~/mcp/obsidian-local-rest-api.crt" }
    }
  },
  "services": {
    "ios": { "mcps": ["XcodeBuildMCP", "mobile", "metro"] }
  }
}
```

`mcps` 里每一项沿用 Claude 的 `command/args/env` 和 `url/headers` 写法，我们自己的扩展字段都放在 `x` 里。这样从 Claude 配置或 `~/mcp/servers.json` 导入导出都不会丢信息。界面上的"类型"（npx / uvx / 命令 / HTTP）是根据这些字段推出来显示的，不另外存。

## 4.1 控制接口（App ↔ core 的全部后台接口）

所有接口都在 `127.0.0.1:<端口>/control/` 下，必须带 `Authorization: Bearer <runtime.json 里的令牌>`，请求和响应都是 JSON。写操作先落盘，再走 reload，返回的是 reload 之后的实际状态。

| 方法 | 路径 | 作用 | 对应界面 |
|---|---|---|---|
| GET | `/control/status` | core 和全部 MCP、全部服务的运行状态（见下面的示例） | 菜单栏、概览 |
| GET | `/control/mcps` | MCP 定义列表（密钥打掩码） | MCP 列表 |
| GET | `/control/mcps/{name}` | 单个定义，加 `?reveal=1` 返回明文 | 编辑表单 |
| POST | `/control/mcps` | 新增 | 新增 |
| PUT | `/control/mcps/{name}` | 修改，可以改名，改名会同步更新引用它的服务 | 编辑 |
| DELETE | `/control/mcps/{name}` | 删除，同时从所有服务里移除 | 删除 |
| PUT | `/control/mcps/{name}/default` | `{"on": true}` 开关：是否在默认服务里 | 开关 |
| POST | `/control/mcps/{name}/restart` | 只重启这一个 | 重启按钮 |
| GET | `/control/mcps/{name}/catalog` | 它的 tools、prompts、resources、instructions | 详情 |
| GET | `/control/mcps/{name}/stderr?lines=200` | stderr 尾部 | 详情 → 日志 |
| POST | `/control/mcps/test` | 用一份**还没保存**的定义临时起一次，握手并列出工具后关掉，返回结果或错误和 stderr | 编辑表单里的"测试" |
| GET | `/control/services` | 服务列表（默认服务固定在第一个） | 服务页 |
| POST / PUT / DELETE | `/control/services[/{name}]` | 命名服务的增删改，内容是 `{"mcps": [...]}` | 服务页 |
| GET | `/control/services/{name}/catalog` | 聚合后的工具表、合并后的 instructions、冲突和超长名字警告 | 服务详情 |
| GET | `/control/services/{name}/client-config?client=claude-code` | 生成客户端配置（命令或 JSON；容器用的地址是 `host.docker.internal`） | 复制配置 |
| GET | `/control/settings` / PUT | 端口、全局环境变量 | 设置 |
| POST | `/control/settings/detect-path` | 从登录 shell 读出 PATH 作为建议值（不直接保存） | 设置 |
| POST | `/control/import` | `{"source": "mcp-proxy" \| "claude" \| "file", "path": …, "dryRun": true}`，先预览再导入 | 导入向导 |
| GET | `/control/audit?since=<游标>&mcp=&service=` | 调用记录，增量拉取 | 调用记录 |
| GET | `/control/audit/{id}` | 单条调用的参数和结果 | 调用记录详情 |
| POST | `/control/reload` | 重新读取 config.json | 设置 |
| GET | `/control/logs?lines=200` | core 自己的日志尾部 | 设置 → 诊断 |

core 连不上时，以上接口全部不可用。App 不依赖这些接口，直接读 `logs/core.log` 和 `launchctl print gui/<uid>/com.example.mcp-mac.core` 来显示原因。安装、启动、停止后台服务也由 App 直接调用 `launchctl`，不经过 core。

`GET /control/status` 返回示例：

```json
{
  "core": { "version": "0.1.0", "pid": 4242, "port": 8090, "startedAt": "2026-11-14T09:00:00+08:00", "configError": null },
  "mcps": [
    { "name": "XcodeBuildMCP", "default": true, "state": "ready", "pid": 5120, "uptimeSecs": 3600,
      "restarts": 0, "lastError": null, "tools": 24, "prompts": 0, "resources": 4,
      "calls1h": 12, "errors1h": 0, "resolvedCommand": "~/.npm/_npx/…/xcodebuildmcp/build/index.js",
      "usedBy": ["默认", "ios"] },
    { "name": "obsidian", "default": true, "state": "backoff", "pid": null, "restarts": 7,
      "lastError": "connect https://127.0.0.1:27124/mcp/: connection refused（Obsidian 没打开？）",
      "nextRetryInSecs": 40, "usedBy": ["默认"] }
  ],
  "services": [
    { "name": "默认", "path": "/mcp", "mcps": 13, "tools": 279, "sessions": 2, "warnings": [] },
    { "name": "ios", "path": "/s/ios/mcp", "mcps": 3, "tools": 135, "sessions": 0, "warnings": [] }
  ]
}
```

MCP 的 `state` 有六种：`starting`（启动中）、`ready`（正常）、`backoff`（失败后等待重试）、`config_error`（配置有错，不会重试）、`stopped`（没有服务用到）、`disabled`（预留）。

## 5. App（SwiftUI）——已实现演示版（2026-11-14）

普通 App（不是 LSUIElement）：有主窗口和完整菜单栏，另有 `MenuBarExtra(.window)` 菜单栏面板。退出 App 不影响 core。

```
app/Sources/MCPMac/
├── App/          入口、RootView（按主题挂载整套界面）、菜单命令
├── Core/         CoreClient 协议、数据模型、SimulatedCore（演示数据）、DemoCatalog（本机 14 个 MCP 的真实工具清单，不含密钥）
├── State/        AppStore（@Observable，乐观更新 + 失败回滚）、Navigator（页面与选中项）、AppTheme
├── Shared/       格式化、复制反馈、WindowChrome（运行时调整 NSWindow）、Debug/Snapshotter（自截图）
├── ThemeGlass/   A · Liquid Glass：NavigationSplitView + 原生 Table + 分组 Form，玻璃材质全部来自系统控件
└── ThemeBento/   C · Pastel Bento：自建 token 与组件（BentoTokens + Components/ + Pages/），浅色
```

- **主题 = 两套完整界面**，只共享 store / navigator，视图互不引用；切换主题停留在当前页、保留选中项。
- **数据是推的**：`CoreClient.updates()` 按粒度推送（core / 单个 MCP / 服务 / 一批调用），Observation 按属性追踪，调用记录刷新不会让 MCP 列表重绘。调用统计只在调用记录变化时重算一次。
- **倒计时**用 `TimelineView` 局部刷新，不靠全局定时器。
- **演示数据**：`SimulatedCore` 是 actor，开关 / 重试 / 重启 / 服务增删改都真实改变状态；设置里可切演示场景（一切正常 / obsidian 连不上 / 后台服务没运行）。Rust core 就绪后新增 `HTTPCoreClient` 替换它，界面不动。
- **构建**：`scripts/build-app.sh [--debug] [--install]`，SwiftPM 产物组装成 `.app` 后 ad-hoc 签名。
- **验证**：`swift test`（模拟 core 生命周期规则、服务名校验、调用统计、客户端配置）；`MCPMAC_SNAPSHOT_DIR=<目录>` 启动会逐页自截图后退出（cacheDisplay 渲染，系统玻璃材质可能画不出来，只用来核对布局）。
- **还没做**：MCP 新增 / 编辑表单、导入向导、开机启动注册、真实 core 连接。

## 6. 和 CC Switch 的关系

CC Switch（本机 4.0.29）管的是**客户端那一侧**：它把 MCP 条目写进 Claude Code、Codex 等工具的配置文件。它的库里现在有 15 条，其中 13 条指向 8090。它**不托管 stdio 进程，不对外提供 HTTP 地址，没有健康检查和重启功能**；它自带的 proxy 是给模型 API 用的，不是给 MCP 用的。所以它替代不了 core，两者是上下游关系。

迁移时，要在 CC Switch 里把那 13 条换成一两条服务地址（比如 `mac` 指向 `/mcp`）。宿主机上的 `~/.claude.json` 由 CC Switch 管理，直接手改**很可能**会被它写回去（这是推断，待核实），所以统一在 CC Switch 里改。

## 7. 动手前要验证的事（一次性验证，不进正式代码）

| 编号 | 验证什么 | 是否影响架构 |
|---|---|---|
| S2 | Claude Code 收到 404 加"请重新 initialize"后，能不能自己恢复会话（用几十行的假 MCP server 测） | **会。** 如果不能自己恢复，会话表要能在 core 重启后保留。最先做 |
| S5 | Claude Code 对 instructions 有没有长度上限 | 会，决定 instructions 怎么合并 |
| S4 | core 由 LaunchAgent 拉起后，peekaboo（录屏、辅助功能）和 iterm（自动化）的授权还在不在，要授权给谁 | 不会，只影响迁移步骤 |
| S1 | 已打开的窗口收到 `tools/list_changed` 后会不会刷新 | 不会。需求本来就是"新开窗口生效" |
| S3 | 工具名长度 | ✅ 已测：最长 60，不超过 64 |

## 8. 实施顺序

1. core：只做单个 MCP 的服务，逐项和 8090 对比。
2. core：多 MCP 聚合、开关、命名服务、控制接口。
3. Swift App。

## 9. 迁移

1. **第 0 步 ✅ 2026-11-13 已完成**：`claude2` 的 6 个地址改成了 `host.docker.internal:8090`（原配置备份为容器内的 `.claude.json.bak-20261113-pre-hdi`）；删除了 ip-sync 脚本里"遇到新 IP 就重启 proxy"的逻辑（原脚本备份为 `.bak-20261113-pre-no-restart`）。下次换网络时验证：`ip-sync.log` 里不再出现"已重启 proxy"。
2. 导入 14 项配置，在 8091 端口试运行。
3. **验收：**
   - 每个 MCP 直连时，`initialize`、tools、prompts、resources 的返回和 8090 一致。
   - 默认服务的工具、instructions、resources 合并正确。
   - 调一次大截图；跑一次长时间的 Xcode 构建。
   - `kill -9` 一个子进程：其他 MCP 不断，它自己恢复。
   - `kill -9` core：重启后没有残留进程，在线的 Claude 会话能恢复。
   - 切一次 Wi-Fi，合盖再唤醒一次：都正常。
4. **切换（每一步先确认）：**
   - 全盘 grep `:8090` 和 `mcp__`，列出所有引用的地方（包括工具名变化会影响的权限设置、hooks、skills）。
   - 停掉老的 proxy 和 ip-sync。
   - core 改用 8090 端口。
   - 在 CC Switch 和容器配置里改成服务地址。

## 10. v1 不做

- 不兼容 SSE。
- 不用钥匙串存密钥。
- 不监听配置文件变化。
- 不声明 sampling 和 elicitation。
- 调用记录不落盘。
## 待确认

1. 开关和服务的语义（第 1 节）是否符合你的想法。
2. 签名："先不要签名，用我自己的账号"是指现在完全不签名，还是用你个人的 Apple Development 证书签（不用公司证书）？
3. bundle id 草案：`com.example.mcp-mac`。
