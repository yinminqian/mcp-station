# MCP Station：架构

本机 MCP 网关，替代原来 `~/mcp` 下的 mcp-proxy（已于 2026-11-14 卸载）。形态参照 Clash：原生菜单栏 App 负责配置和查看状态，独立的内核进程 `mcp-core`（Rust）负责干活。

状态（2026-11-14）：内核和 App 都已实现并在用，网关监听 `127.0.0.1:8091`（端口在设置里改），d1/d2/d3 三个容器都连它。第 1 节的聚合规则已全部实现，第 8 节列出还没做的部分。

| 一层 | 语言 | 平台 | 职责 |
|---|---|---|---|
| 内核 `core/` | Rust | Mac 已实现；Windows 结构上预留（`core/src/platform/`） | 托管所有 MCP、网关、控制接口、开机自启 |
| 界面 `app/` | SwiftUI | Mac | 通过控制接口管理内核；Windows 以后另写一个界面，接同一套控制接口 |

## 0. 要解决的问题（全部来自现网）

| 现象 | 根因 | 新架构里怎么消失 |
|---|---|---|
| 换网络后容器里的 MCP 全部 421 / 连不上 | claude2 用局域网 IP 访问；0.14 版的 Host 白名单只能写死 IP；ip-sync 遇到新 IP 就重启整个 proxy | 只监听 127.0.0.1；容器统一走 `host.docker.internal`（OrbStack 已实测能访问只监听回环地址的端口）；白名单写死三个**主机名**，不含任何 IP |
| 一个后端坏了，8090 全挂 | 所有后端共用一个 AsyncExitStack，一个失败全部失败 | 每个上游有独立的 supervisor，挂了按指数退避重启，只影响它自己 |
| 启动时没起来的后端（比如 obsidian），要等整体重启才能回来 | 启动预检直接把它剔掉了 | 不做预检；起不来就一直按退避重试，界面上显示原因 |
| 改一个配置要重启整个服务 | 进程模型决定的 | 按定义指纹比对，只重启改过的那一个 |
| 静默升级把服务弄坏 | 用 uvx 拉 proxy，版本不固定 | 内核是自己编译的二进制，随 App 一起打包 |
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

（当时 `claude` 容器配置里的 `open-design` 在 8090 上返回 404，属于残留配置，切换到内核时已删掉。）

**结论：聚合不能只聚合工具。** mcp-rust 的路由只聚合工具：它自己回答 `initialize`（不带上游的 instructions），prompts/resources 直接报错，上游发来的通知只处理 `tools/list_changed`。照搬的话，XcodeBuildMCP 那 2254 字的使用说明、metro 的 17 个 resources 和 10 个 prompts 都会丢。所以内核在这一块是重写的（`core/src/router.rs`）。

### 三个概念

- **MCP**：一个上游定义，包括命令或 URL、env 等。
- **开关**：每个 MCP 一个，表示**是否加入默认服务**。新加的 MCP 默认打开。
- **服务**：对外暴露的一个地址，背后是若干个 MCP。

| 服务 | 地址 | 背后有哪些 MCP |
|---|---|---|
| 默认服务 | `/mcp` | 所有开关打开的 MCP |
| 命名服务（如 `ios`、`data`） | `/s/<服务名>/mcp` | 在 App 里勾选的 MCP，**不受开关影响** |
| 单个 MCP | `/servers/<名字>/mcp` | 只有它自己的服务，工具名**不加前缀**，兼容现在的地址 |

三种地址**走同一个 router、同一套聚合逻辑**，单个 MCP 只是"只含一个 MCP、不加前缀"的服务。共享子进程只在启动时握手一次，所以 `initialize` 的回答本来就是用握手结果拼出来的，没法原样转发：单个 MCP 的地址原样给它的 `serverInfo` 和 `instructions`，聚合地址给 `MCP Station` 和合并后的 instructions。

**进程什么时候运行（只有一条规则）：** 被默认服务或任一命名服务用到，就常驻运行；否则停掉。v1 不做"访问时按需启动"，因为第一次调用要冷启动 npx，容易超时。

注意：单个 MCP 的地址 `/servers/<名字>/mcp` **不算引用**。容器现在都连这种地址，所以一个 MCP 的开关关掉、又没有命名服务用到它时，容器里它就不可用了（调用会收到"没在运行，在 MCP Station 里打开它的开关"）。

**内核刚启动时**：客户端来要 `initialize` 或任何 `*/list`，最多等 20 秒，等成员都启动完再回答，不会给出"0 个工具"。

**开关的效果：**
- **新开的 Claude 窗口**：连上时拿到的就是当前开关的状态。开了就有，关了就没有。
- **已经打开的窗口**：不会刷新。网关不提供服务器推送流（`GET` 回 405），能力里声明 `listChanged: false`。需求本来就是"新开窗口生效"。

**聚合时各项内容怎么合并：**

| 内容 | 怎么合并 |
|---|---|
| 工具 | 名字前缀 `<MCP 名>__<工具>`，现有逻辑 |
| instructions | 每个 MCP 的 instructions 前面加上 `## <MCP 名>` 小标题，拼在一起，在 `initialize` 时返回 |
| prompts | 名字前缀 `<MCP 名>__`，调用时按前缀路由回对应上游 |
| resources | URI 保持原样。按 `resources/list` 拿到的**精确 URI** 建"URI → 上游"表，再加上模板匹配；两个 MCP 的 URI 撞车时，在界面上报冲突 |
| 上游的 `*/list_changed` | 内核重新拉这个上游的清单，界面跟着更新（不转发给客户端，见上） |
| 进度 | 请求带了 `_meta.progressToken`、客户端也接受 SSE 时，这次响应改用 SSE：先推进度，最后推结果。不同会话的 token 会撞，所以发给上游前换成网关自己的（`p-<n>`），回来再换回客户端的 |
| 取消 | 网关登记"哪个会话的哪个请求正在哪个 MCP 上、用哪个 id 跑"（发给上游的 id 是网关编的 `c-<n>`，全局唯一）。客户端发 `notifications/cancelled` 时换成上游认识的 id 转过去，并立刻结束这个请求 |
| 日志通知（还没做） | `logging` 加上来源前缀后转发——需要服务器推送流，目前不提供 |
| sampling / elicitation | v1 不声明（和现在一样） |

**需要注意的地方：**
- **聚合后工具名全部变化。** 原来的 `mcp__desktop__x` 会变成 `mcp__mac__desktop__x`。权限设置、hooks、skills、agents、CLAUDE.md 里写死旧名字的地方都会失效，改用聚合地址前要全盘 grep 一次 `mcp__`。走单个 MCP 地址的客户端不受影响（容器现在都是这样）。
- **工具名长度。** 已实测：客户端里服务名叫 `mac` 时，279 个工具拼接后最长 60 个字符（`mcp__mac__mobile__mobile_long_press_on_screen_at_coordinates`），一般认为上限是 64，目前不超。每个 MCP 可以设一个短别名作为前缀；出现超长名字时，界面标红提示。
- **工具太多。** 默认服务把 279 个工具全部打开会占不少上下文（Claude Code 在工具很多时会延迟加载）。这正是开关和命名服务要解决的事。
- **instructions 合并后可能被截断。** 如果客户端对 instructions 有长度上限，合并后的内容会被截掉（XcodeBuildMCP 一个就有 2254 字）。需要验证（S5）。

## 2. 进程与文件布局

```
/Applications/MCP Station.app            只是界面，可以随便重新编译、退出
  └─ Contents/Resources/mcp-core         App 包里带的内核；装 / 升级时由它把自己复制到下面

~/Library/Application Support/MCP Station/   （Windows：%LOCALAPPDATA%\MCP Station；开发时用 MCPSTATION_HOME 指到别处）
  bin/mcp-core          实际运行的内核（放在 App 外面，重装 App 不影响它）
  config.json           0600，唯一的配置来源，只由内核读写
  config.json.bak       每次成功读取后的备份；主文件坏了时用它运行，并拒绝一切写入
  runtime.json          0600，内核启动时写、正常退出时删：pid、网关端口、控制接口端口和令牌
  children.json         内核起的子进程（每个是自己进程组的组长），内核重启时清残留
  sessions.json         客户端会话（地址、客户端名），内核重启后仍认得
  calls.jsonl           调用记录，一行一条，只留最近 3 天
  core.lock             单实例锁
  logs/core-<日期>.log  内核日志，一天一个文件，只留最近 3 天
  logs/launchd.log      launchd 接的标准输出，只有日志初始化之前的崩溃会写进来，超过 50MB 清空

~/Library/LaunchAgents/com.example.mcp-station.core.plist   由 `mcp-core install` 写入并载入
```

- **开机自启用普通 LaunchAgent，不用 SMAppService。** SMAppService 要求 plist 和二进制都在 App 包里，而重装 App（删掉再拷）会把正在跑的内核连带断掉；它也要求正式签名。`RunAtLoad` + `KeepAlive{SuccessfulExit=false}`：开机启动，崩溃了 launchd 拉起来。
- **装 / 升级 / 重启都是 `mcp-core install [--restart]`**，Swift 只调这条命令，以后的 Windows 界面也一样。二进制内容变了才换，先写 `mcp-core.new` 再 rename——不能原地覆盖正在跑的文件（inode 不变会被系统按签名失效杀掉）。另有 `mcp-core uninstall`（数据保留）和 `mcp-core status`（内核不在时给界面看原因）。
- **重装 App 不会打断内核**：App 发现内核没装才自动装；要升级正在跑的内核，在 App 里点「重启」或 `scripts/build-app.sh --install-core`，客户端会断约 1 秒。
- **系统授权（录屏、辅助功能、自动化）**：授权对象是 `bin/mcp-core` 及其子进程（peekaboo、iterm 等）。只有内核更新时才可能要重新授权。
- **残留子进程**：内核被 `kill -9` 或被 launchd 重启时，子进程在独立进程组里，不会被带走。新内核启动时读 `children.json`，只杀"pid 还在、仍是自己进程组的组长、父进程已经是 1"的，防止 pid 被复用后误杀。（实测：强杀内核 13 秒内被拉起，4 个旧子进程全部清掉。）
- **端口被占时内核不退出**：否则 launchd 会反复拉起、把 MCP 一遍遍重启。记下原因（谁占着）每 5 秒重试，控制接口照常可用，界面能显示原因、能改端口。
- **App 的"开机启动"开关**只控制登录后是否自动打开菜单栏 App，和内核无关（还没做）。

## 3. 内核 core（从 mcp-rust 复制后改造）

单个 crate，二进制名 `mcp-core`，依赖：tokio、axum、reqwest（rustls）、serde、tracing、dashmap、uuid、thiserror，unix 上加 nix。从 mcp-rust 删掉了 sqlx、jsonwebtoken、clickhouse、toml、globset、tower-http 等。

| 文件 | 来源 | 说明 |
|---|---|---|
| `jsonrpc.rs` | mcp-rust 原样 | 扁平报文结构，透传不认识的字段 |
| `upstream/stdio.rs`、`upstream/http.rs` | mcp-rust 改 | 单 actor 结构不变；状态换成界面要的完整 `Status`（原因、下次重试时间、pid、日志、清单）；退避 5/15/30/60/120/300 秒，去掉熔断；找不到命令、缺变量、401/403、地址不是 MCP 服务算配置错误，不重试；握手后拉完 tools（跟 nextCursor 翻页）/ prompts / resources 才算就绪；HTTP 支持自签 CA |
| `upstream/mod.rs` | mcp-rust 改 | `UpstreamHandle`：call / restart（计次数）/ retry（只提前结束退避）|
| `registry.rs` | 重写（取代 mcp-rust 的 registry + catalog） | 配置、运行中的上游、会话、内存采样。配置一变就 `reconcile`：多的停、新用到的起、定义（或全局 env）变了的重启。按地址算成员，每个成员带自己的前缀（mcp-rust 的全局"slug__工具名"表加 glob 规则表达不了"单个地址不加前缀"和别名）|
| `router.rs` | mcp-rust 改 | 本地应答 initialize（合并 instructions），聚合 tools / prompts / resources，resources 按 URI 找归属（精确 URI → 模板固定前缀 → 唯一有 resources 的成员），每次 tools/call 记一条 |
| `northbound.rs` | mcp-rust 改 | 三种地址一个处理函数；去掉鉴权；Host / Origin 检查；会话接管；请求体上限 64MB |
| `control.rs` | 新写 | 控制接口，见 §4.1 |
| `config.rs` | 新写 | config.json 读写、导入解析、`${VAR}` 展开、名字规则 |
| `calls.rs`、`events.rs`、`children.rs`、`runtime.rs`、`logfile.rs`、`paths.rs` | 新写 | 见 §2 |
| `platform/{unix,windows,launchd}.rs` | 新写 | 平台相关的全部在这里：数据目录、子进程进程组和杀进程树、登录 shell 的 PATH、按 PATH 找命令、进程表、端口占用、自启。业务代码里没有 `#[cfg]` |

没带过来的：`db`、`auth/`、`audit_ch`、`audit.rs`（换成按调用记录格式新写的 `calls.rs`）、`api.rs`、`admin.rs`、`upstream/resolve.rs`（跳过 npx 包装那一层：会让 `@latest` 一直跑旧缓存，路径也只适用 Unix）、`web/`。

**和 mcp-rust 不同的几个决定：**
1. **不认识的 `Mcp-Session-Id` 直接接管，不回 404。** 会话里只有地址和客户端名，内核重启后原地重建；会话也写进 `sessions.json`，重启后还认得客户端名字。实测：从 App 内的临时网关切到内核时，正在用的 Claude Code 会话不用重连就能继续调用。（原计划回 404 让客户端重新 initialize，这样不依赖客户端的恢复能力。）
2. **控制接口单独监听随机端口**，不和网关共用：网关端口被占时控制接口照样能用。
3. **子进程的环境**：只给白名单里的变量（PATH、HOME、语言、npm/uv 缓存目录等，**不含代理变量**），PATH 用登录 shell 读出来的，再叠加全局 env 和每个 MCP 自己的 env。`${VAR}` 先查全局 env 再查内核自己的环境，**找不到就把这个 MCP 标成配置错误**（不再悄悄换成空串）。
4. **默认超时**：initialize 60 秒、list 30 秒、调用 600 秒（`x.timeoutSecs` 覆盖调用超时）。mcp-rust 是 20/10/60 秒，Xcode 构建撑不住。
5. **不声明 sampling / roots / elicitation**（共享单例连接无法把上游发来的请求归到具体客户端），上游真发了就回 MethodNotFound。
6. **内存**：每 5 秒一次 `ps` 读全部进程，按父子关系求每个 MCP 进程树的 RSS 之和（npx / uvx 真正干活的是子进程）。只在有界面订阅时采样。

**安全**：网关只监听 127.0.0.1；Host 只认 `localhost`、`127.0.0.1`、`host.docker.internal`（加上配置里的 `allowedHosts`），带浏览器 `Origin` 头的请求一律 403；控制接口必须带 `runtime.json` 里的令牌。

**构建**：`scripts/build-app.sh` 先 `cd core && cargo build --release`，再把产物放进 App 包。cargo 只从当前目录往上找 `.cargo/config.toml`，本机网络需要 crates 镜像时放在 `core/.cargo/`（不提交）。开发用 `CARGO_TARGET_DIR=target-dev cargo build`，和 release 的缓存分开。

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

- `port` 没写时是 8090；`allowedHosts`（可选）额外放行的 Host。
- `x.default` 没写等于 `true`；`x.alias` 是聚合地址里的前缀（默认用名字）；`x.timeoutSecs` 是调用超时；`x.caCert` 支持 `~`。
- **不认识的字段原样保留**（每一层都兜住），手写的内容不会被内核改丢。
- **每个 MCP 条目单独解析**：坏了一项只把那一项标成配置错误。
- 名字只能用字母、数字、`-`、`_`，大小写都行（`XcodeBuildMCP`），最长 64。

## 4.1 控制接口（界面 ↔ 内核）

监听 `127.0.0.1:<随机端口>`，端口和令牌在 `runtime.json` 里。每个请求带 `Authorization: Bearer <令牌>`（不对回 401），带 `Origin` 头的回 403。写操作的顺序：在副本上改 → 校验 → 原子落盘 → 替换内存里的 → reconcile → 推事件 → 返回最新对象。接口版本 `api: 1`，界面发现对不上时提示"点重启升级内核"。

| 方法 | 路径 | 请求 | 返回 |
|---|---|---|---|
| GET | `/control/ping` | | `{version, api, pid}` |
| GET | `/control/status` | | `{core, mcps, services}` |
| GET | `/control/events` | | SSE，见下 |
| POST | `/control/mcps` | `{name, entry}` | 201 + Mcp |
| PUT | `/control/mcps/{name}/default` | `{on}` | Mcp |
| POST | `/control/mcps/{name}/restart` | | Mcp（重启次数 +1）|
| POST | `/control/mcps/{name}/retry` | | Mcp（只提前结束退避，配置错误时也再试一次）|
| POST | `/control/mcps/{name}/call` | `{tool, arguments}` | `{isError, text, ms}`，记一条 route=test 的调用 |
| POST | `/control/services` | `{name, mcps}` | `[Service]` |
| PUT | `/control/services/{name}` | `{mcps?, name?}` | `[Service]` |
| DELETE | `/control/services/{name}` | | `[Service]` |
| PUT | `/control/settings` | `{port}` | Core（网关换端口，事件流不断）|
| POST | `/control/import` | 文件原文（本软件的、`mcpServers`、`servers`）| `{added, updated, services, skipped}` |
| GET | `/control/export` | | config.json 全文（含密钥明文）|
| POST | `/control/reload` | | 重新读 config.json（手改之后）|
| GET | `/control/calls?after=&limit=` | | `{calls, latest}` |
| GET | `/control/logs?lines=` | | 内核日志尾部 |

出错统一回 `{"error":{"code","message"}}`：`unknown_mcp` / `unknown_service`（404）、`invalid_name` / `missing_field` / `invalid_port` / `unrecognized`（400）、`duplicate_mcp` / `duplicate_name` / `config_unreadable`（409）。中文文案由内核给，Swift 按 code 映射回 `CoreError`。

**数据对象**（时间都是 Unix 秒）：

```jsonc
// Core
{"version":"0.1.0","api":1,"pid":4242,"port":8091,"startedAt":1794633600.0,
 "gatewayError":null,   // 网关端口起不来的原因，比如"端口 8091 起不来：…，被 python3.1（pid 20594）占着"
 "configError":null,    // config.json 整个读不了的原因
 "defaultSessions":2,"memory":18350080}

// Mcp
{"name":"obsidian","entry":{…config.json 里的原文，含密钥…},"default":true,
 "state":"backoff",     // starting | ready | backoff | config_error | stopped
 "error":"连不上 …","retryAt":1794633700.0,"attempts":3,
 "pid":null,"startedAt":null,"restarts":0,
 "tools":[{"name":"…","description":"…","inputSchema":{}}],"resources":1,"prompts":0,"instructionsLength":0,
 "log":[{"id":57,"t":1794633650.2,"level":"error","text":"…"}],   // level: info | warn | error | stderr
 "memory":null}

// Service（只有命名服务；默认服务由各 MCP 的 default 推出）
{"name":"ios","mcps":["XcodeBuildMCP","mobile"],"sessions":0}

// Call
{"id":812,"t":1794633612.4,"mcp":"desktop","tool":"read_file","route":"default","service":null,
 "client":"claude-code 2.1.0","ms":132,"error":null}      // route: default | named | single | test
```

**实时推送 `GET /control/events`**（SSE）：连上先发一份 `snapshot`，之后按"谁变了"推送；每个事件固定两行 `event:` 和单行的 `data:`，每 15 秒一行 `: keepalive`。事件总线里只放"谁变了"，发送时再读当前状态，所以积压了也不会推旧数据；积压时补发一份 `snapshot`。

| event | data | 对应 Swift 的 `CoreUpdate` |
|---|---|---|
| `snapshot` | `{core, mcps, services, calls}` | `.snapshot` |
| `core` | Core | `.core` |
| `mcp` | Mcp | `.mcp` |
| `services` | `[Service]` | `.services` |
| `calls` | `[Call]` | `.calls` |
| `memory` | `{core, mcps:{名字:字节}}`，每 5 秒 | `.memory` |

**内核不在时**界面调 `mcp-core status`（不走控制接口）：`{installed, loaded, disabled, pid, lastExitCode, label, bundledVersion, logTail, port, portOwner}`，据此显示"被系统关掉了 / 启动后退出了（退出码）/ 没有运行"，没装就自动装。

**还没做的接口**：改 / 删 MCP（`PUT/DELETE /control/mcps/{name}`）、用没保存的定义测试一次（`POST /control/mcps/test`）、对没在运行的 MCP 试调用（临时起一个）、改全局环境变量、从登录 shell 读 PATH 作为建议值。界面现在都没有入口。

## 5. App（SwiftUI）

普通 App（不是 LSUIElement）：有主窗口和完整菜单栏，另有 `MenuBarExtra(.window)` 菜单栏面板。退出 App 不影响内核。

```
app/Sources/MCPStation/
├── App/          入口、RootView（按主题挂载整套界面）、菜单命令
├── Core/         CoreClient 协议、HTTPCoreClient（控制接口客户端 + CoreInstaller）、数据模型、ConfigFile（格式定义和"类型"推导）
├── State/        AppStore（@Observable，乐观更新 + 失败回滚）、Navigator（页面与选中项）、AppTheme
├── Shared/       格式化、复制反馈、WindowChrome、PortCheck、Debug/Snapshotter（自截图）
├── ThemeGlass/   Liquid Glass：NavigationSplitView + 原生 Table + 分组 Form，玻璃材质全部来自系统控件
└── ThemeBento/   Pastel Bento：自建 token 与组件（BentoTokens + Components/ + Pages/），浅色
```

- **界面只认 `CoreClient`**：`HTTPCoreClient` 读 `runtime.json`，订阅 `/control/events`，断了每秒重连；连不上几次后调 `mcp-core status` 显示原因，没装或没在跑就用 App 包里的内核装一次（最多 30 秒一次）。「重启」= `mcp-core install --restart`，内核卡死时也管用。
- **内核状态到界面**：正常 → `.running`；网关端口起不来 → `.notInstalled`（能管理配置、客户端连不上，设置页端口那一行说被谁占着）；配置文件读不了 / 接口版本不对 / 内核不在 → `.stopped(原因)`。
- **主题 = 两套完整界面**，只共享 store / navigator；切换主题停留在当前页、保留选中项。
- **数据是推的**：按粒度推送，Observation 按属性追踪，调用记录刷新不会让 MCP 列表重绘。内存趋势由界面按每 5 秒的采样自己攒。
- **配置的读写全在内核**，App 只用 `ConfigStore.url` 做"在访达中显示"，以及启动时把改名前的数据目录（MCP Mac）搬过来。
- **构建**：`scripts/build-app.sh [--debug] [--install] [--install-core]`。
- **验证**：`swift test`；内核 `cargo test`（配置解析、导入、变量展开、名字规则、SSE 切分、调用记录旧格式）；`MCPSTATION_SNAPSHOT_DIR=<目录>` 启动会逐页自截图后退出。

## 6. 和 CC Switch 的关系

CC Switch（本机 4.0.29）管的是**客户端那一侧**：它把 MCP 条目写进 Claude Code、Codex 等工具的配置文件。它的库里现在有 15 条，其中 13 条指向 8090。它**不托管 stdio 进程，不对外提供 HTTP 地址，没有健康检查和重启功能**；它自带的 proxy 是给模型 API 用的，不是给 MCP 用的。所以它替代不了 core，两者是上下游关系。

宿主机上的客户端要改用 MCP Station 时，在 CC Switch 里把指向旧地址的条目换成 `host` 上的服务地址（比如 `mac` 指向 `/mcp`，或者逐个换成 `/servers/<名字>/mcp` 保持工具名不变）。宿主机上的 `~/.claude.json` 由 CC Switch 管理，直接手改**很可能**会被它写回去（这是推断，待核实），所以统一在 CC Switch 里改。（容器里的三份配置不归 CC Switch 管，已直接改好，见第 9 节。）

## 7. 需要验证的事

| 编号 | 验证什么 | 状态 |
|---|---|---|
| S2 | 内核重启后 Claude Code 的会话能不能恢复 | ✅ 改成"未知会话直接接管"后不依赖客户端；切换时实测正在用的会话不用重连 |
| S3 | 工具名长度 | ✅ 最长 60，不超过 64 |
| S4 | 内核由 LaunchAgent 拉起后，peekaboo（录屏、辅助功能）和 iterm（自动化）的授权还在不在、要授权给谁 | 待验证：切换后 peekaboo 已能列出工具，实际截图 / 操作还没试 |
| S5 | Claude Code 对 instructions 有没有长度上限 | 待验证，决定聚合地址的 instructions 要不要裁剪 |
| S1 | 已打开的窗口收到 `tools/list_changed` 后会不会刷新 | 不做：不提供推送流，需求本来就是"新开窗口生效" |

## 8. 实施进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| M1 | 内核：上游连接、三种地址、工具转发、安全检查、会话接管 | ✅ |
| M2 | 控制接口、事件推送、调用记录、内存采样、配置写入 / 导入 / 备份 | ✅（23 项验收） |
| M3 | 常驻：LaunchAgent、单实例锁、残留子进程清理、日志轮转（3 天） | ✅ |
| M4 | Swift 接上内核（HTTPCoreClient 替换 App 内的临时网关） | ✅ |
| M5 | 生产切换 | ✅ 2026-11-14，见第 9 节 |
| M6 | 聚合：instructions 合并、prompts / resources 聚合与路由、上游 list_changed 后重拉 | ✅ 已实现；instructions 长度（S5）待验证 |
| M7 | 进度通知转发、取消请求转发 | ✅（用 server-everything 的长时间操作实测：三条进度按时到、token 还原；取消后 1 秒结束）|
| — | logging 通知转发、改删 MCP 的接口、对没在运行的 MCP 试调用、设置页"内核可升级" | 未做 |
| — | Windows：内核在 Windows 上实际编译一次；进程管理换 Job Object；自启用任务计划；Windows 界面 | 未做（结构已预留在 `core/src/platform/windows.rs`） |

## 9. 迁移记录

1. **2026-11-13**：`claude2` 的地址改成 `host.docker.internal:8090`；ip-sync 去掉"遇到新 IP 就重启 proxy"。
2. **2026-11-14 白天**：网关先临时用 Swift 写在 App 里（`LocalCore`），监听 8091（8090 被 mcp-proxy 占着）；mcp-proxy 的 14 个 MCP 全部导入。
3. **2026-11-14**：d1 / d2 / d3 三个容器的 `claude.json` 全部改指 `http://host.docker.internal:8091/servers/<名字>/mcp`（单个 MCP 地址，工具名不变），各自旁边留了 `.bak-*-pre-mcpmac` 备份；`open-design`（mcp-proxy 里本来就没有）删掉。
4. **2026-11-14**：mcp-proxy 卸载——三个 LaunchAgent（mcp-proxy、mcp-ip-sync、mcp-log-trim）撤掉，pm2 卸载，`~/mcp` 下的脚本、日志、servers.json 及备份挪进废纸篓的 `mcp-proxy-卸载-20261114_203725`。`~/mcp` 只留 MCP Station 还在用的 genimg 脚本、obsidian 证书、`.env`、容器 SSH 密钥。
5. **2026-11-14 晚，切到 Rust 内核**：一个脚本跑完——打包 → 备份旧 App（`~/MCP Station (swift-gateway).app`）和配置（`config.json.pre-core`）→ 退出旧 App → `mcp-core install` → 装新 App。8091 空窗约 1 秒；13 个 MCP 切换前后工具数逐个一致，peekaboo 也通了；正在用的会话被接管，不用重连。顺手清掉了 5 个以前遗留的孤儿 metro-mcp 进程（它收到 stdin 结束不会自己退出）。
   - 回滚：`mcp-core uninstall`，再打开备份的旧 App（config.json 两边格式兼容）。

**之后还可以做**：宿主机上的客户端（CC Switch 管的那份）改成连 MCP Station；把端口换回 8090（mcp-proxy 已卸载，8090 空着；改端口后三个容器的配置要一起改）。

## 10. v1 不做

- 不兼容旧的 SSE 传输（客户端用 Streamable HTTP）。
- 不提供服务器推送流（`GET` 回 405），不向客户端转发 `list_changed`。
- 不用钥匙串存密钥（config.json 0600）。
- 不监听配置文件变化（手改后在 App 里点「重新检测」或 `POST /control/reload`）。
- 不声明 sampling、roots 和 elicitation。

## 待确认

1. 签名：现在内核和 App 都是 ad-hoc 签名，每次重编内核 cdhash 都变，录屏、辅助功能、自动化这类授权可能要重新给。要不要用你个人的 Apple Development 证书固定签名？
2. bundle id 和 LaunchAgent 的 Label 还是占位的 `com.example.mcp-station`。装了 LaunchAgent 之后再改，要先 `mcp-core uninstall` 再装。
3. 开关关掉会让容器里对应的单个 MCP 地址失效（见第 1 节）。保持现状，还是让单个地址也算"引用"？
