import Foundation

/// 真数据版 core（网关接入前的过渡实现）：
///
/// - 配置真实读写 `config.json`（ConfigStore），添加 MCP、开关、服务的增删改都马上落盘；
/// - 被用到的 MCP（默认开关打开，或在某个命名服务里）由 App 启动并握手（MCPProbe.connect），拿到真实的工具、
///   resources、prompts 和报错；握手成功后进程常驻，每 5 秒采一次它整棵进程树的内存；进程自己退出了就按退避重连；
/// - 网关在 App 里（GatewayServer）：监听 127.0.0.1:<port>，`/mcp`（默认服务）、`/s/<服务>/mcp`、`/servers/<名字>/mcp`
///   三种地址，tools/list 聚合、tools/call 转给常驻进程；每次调用（连同 App 里的"试调用"）记进配置旁边的 calls.jsonl。
///   目前只聚合工具，resources / prompts 还没转发（docs/ARCHITECTURE.md §3）。
///
/// 网关做好后换成 HTTP 版 CoreClient，这个文件删掉即可，界面只认 `CoreClient`。
actor LocalCore: CoreClient {
    private var config = ConfigFile()
    /// 配置文件读不了时的原因。这时拒绝一切修改，免得用空配置把用户的文件覆盖掉。
    private var loadError: String?
    private var core: CoreStatus
    private var mcps: [String: MCPServer] = [:]
    private var continuations: [UUID: AsyncStream<CoreUpdate>.Continuation] = [:]
    private var failures: [String: Int] = [:]
    /// 每个 MCP 检测的代数：重新检测或配置变了以后，旧的结果回来直接丢掉。
    private var generation: [String: Int] = [:]
    private var probes: [String: Task<Void, Never>] = [:]
    /// 握手成功、常驻着的连接。
    private var connections: [String: MCPConnection] = [:]
    private var ticks = 0
    private let gatewayServer = GatewayServer()
    /// 网关上的客户端会话：initialize 时建，DELETE 时删。
    private var sessions: [String: GatewaySession] = [:]
    private var ticker: Task<Void, Never>?
    private var bootstrapped = false
    private var nextLogID = 0
    private var calls: [CallRecord] = []
    private var nextCallID = 0
    private static let maxCalls = 3000

    /// 连不上时的重试间隔（秒），按连续失败次数递增。
    private static let backoff: [TimeInterval] = [5, 15, 30, 60, 120, 300]

    init() {
        core = CoreStatus(version: AppInfo.version, port: ConfigFile.defaultPort, state: .notInstalled, defaultSessions: 0)
    }

    // MARK: 订阅

    nonisolated func updates() -> AsyncStream<CoreUpdate> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.subscribe(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        }
    }

    private func subscribe(_ id: UUID, _ c: AsyncStream<CoreUpdate>.Continuation) {
        if !bootstrapped {
            bootstrapped = true
            calls = CallLog.load(max: Self.maxCalls)
            nextCallID = calls.map(\.id).max() ?? 0
            reload()
        }
        continuations[id] = c
        c.yield(snapshot)
        if ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self?.tick()
                }
            }
        }
    }

    private func unsubscribe(_ id: UUID) {
        continuations[id] = nil
        if continuations.isEmpty { ticker?.cancel(); ticker = nil }
    }

    private func emit(_ u: CoreUpdate) {
        for c in continuations.values { c.yield(u) }
    }

    private var snapshot: CoreUpdate {
        .snapshot(core, orderedNames.compactMap { mcps[$0] }, namedServices, calls)
    }

    private var orderedNames: [String] {
        mcps.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var namedServices: [NamedService] {
        config.services.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            NamedService(name: name, mcpNames: config.services[name]!.mcps.filter { config.mcps[$0] != nil },
                         sessions: sessions.values.filter { $0.route == .named(name) }.count)
        }
    }

    // MARK: 读取配置

    /// 从磁盘重新读配置、重建列表、重新检测。读不了时停在出错状态，不动文件。
    private func reload() {
        probes.values.forEach { $0.cancel() }
        probes = [:]
        for name in Array(connections.keys) { closeConnection(name) }
        let previousLogs = mcps.mapValues(\.stderr)
        mcps = [:]
        do {
            config = try ConfigStore.load()
            loadError = nil
            core.port = config.port
            core.state = .notInstalled
        } catch {
            loadError = "\(ConfigStore.url.path)：\(error.localizedDescription)"
            core.state = .stopped(reason: CoreDownReason(
                title: "配置文件读不了",
                detail: "\(loadError!)\n修好或移走这个文件后点「重新检测」。在修好之前不会改动它。",
                occupiedBy: nil, lastExitCode: 0, logTail: []))
            return
        }
        for (name, entry) in config.mcps {
            mcps[name] = server(name, entry, stderr: previousLogs[name] ?? [])
        }
        for name in orderedNames { refreshLifecycle(name) }
        startGateway()
    }

    private func server(_ name: String, _ entry: ConfigFile.MCPEntry, stderr: [LogLine] = []) -> MCPServer {
        MCPServer(name: name, kind: entry.kind, definition: entry.displayFields, tools: [],
                  resourceCount: 0, promptCount: 0, instructionsLength: 0,
                  inDefault: entry.isDefault, state: .stopped, pid: nil, startedAt: nil,
                  restarts: 0, stderr: stderr)
    }

    // MARK: 检测

    /// 被默认服务或任一命名服务用到，才需要检测（docs/ARCHITECTURE.md §1）。
    private func isReferenced(_ name: String) -> Bool {
        (config.mcps[name]?.isDefault ?? false) || config.services.values.contains { $0.mcps.contains(name) }
    }

    private func refreshLifecycle(_ name: String) {
        guard mcps[name] != nil else { return }
        if isReferenced(name) {
            if mcps[name]!.state == .stopped { probe(name) }
        } else if mcps[name]!.state != .stopped {
            probes[name]?.cancel()
            generation[name, default: 0] += 1
            closeConnection(name)
            failures[name] = nil
            mcps[name]!.state = .stopped
            mcps[name]!.startedAt = nil
            log(name, .info, "没有服务用到它，不再检测")
            emit(.mcp(mcps[name]!))
        }
    }

    private func probe(_ name: String) {
        guard let entry = config.mcps[name], mcps[name] != nil else { return }
        probes[name]?.cancel()
        generation[name, default: 0] += 1
        closeConnection(name)
        let gen = generation[name]!
        mcps[name]!.state = .starting
        log(name, .info, entry.url.map { "正在连接 \($0)" } ?? "正在启动 \(entry.command ?? "")")
        emit(.mcp(mcps[name]!))
        let env = config.env
        probes[name] = Task { [weak self] in
            let result = await MCPProbe.connect(entry, globalEnv: env)
            await self?.finish(name, gen: gen, result)
        }
    }

    private func finish(_ name: String, gen: Int, _ result: Swift.Result<(MCPProbe.Result, MCPConnection), MCPProbe.Failure>) {
        guard generation[name] == gen, mcps[name] != nil else {
            if case .success(let (_, conn)) = result { conn.close() }   // 过期的结果：连接不要了
            return
        }
        probes[name] = nil
        let now = Date.now
        switch result {
        case .success(let (r, conn)):
            connections[name] = conn
            mcps[name]!.pid = conn.pid.map(Int.init)
            conn.onExit { [weak self] reason in
                Task { await self?.connectionExited(name, gen: gen, reason: reason) }
            }
            failures[name] = nil
            for line in r.log.suffix(10) { log(name, .info, line) }
            mcps[name]!.tools = r.tools
            mcps[name]!.resourceCount = r.resources
            mcps[name]!.promptCount = r.prompts
            mcps[name]!.instructionsLength = r.instructionsLength
            mcps[name]!.state = .ready
            mcps[name]!.startedAt = now
            log(name, .info, "握手成功\(r.server.isEmpty ? "" : " · \(r.server)") · \(r.tools.count) 工具 · \(r.resources) resource · \(r.prompts) prompt")
        case .failure(.config(let reason, let lines)):
            failures[name] = nil
            for line in lines.suffix(10) { log(name, .warn, line) }
            log(name, .error, reason)
            mcps[name]!.state = .configError(reason)
        case .failure(.transient(let reason, let lines)):
            let attempts = failures[name, default: 0] + 1
            failures[name] = attempts
            let wait = Self.backoff[min(attempts, Self.backoff.count) - 1]
            for line in lines.suffix(10) { log(name, .warn, line) }
            log(name, .error, reason)
            log(name, .info, "\(Int(wait)) 秒后重试（第 \(attempts) 次）")
            mcps[name]!.state = .backoff(reason: reason, retryAt: now.addingTimeInterval(wait), attempts: attempts)
        }
        emit(.mcp(mcps[name]!))
    }

    /// 常驻的进程自己退出了（崩了、被杀）：按连不上处理，退避后重连。
    private func connectionExited(_ name: String, gen: Int, reason: String) {
        guard generation[name] == gen, connections[name] != nil else { return }
        connections[name] = nil
        mcps[name]?.memory = nil
        finish(name, gen: gen, .failure(.transient(reason, log: [])))
    }

    private func closeConnection(_ name: String) {
        connections.removeValue(forKey: name)?.close()
        mcps[name]?.pid = nil
        mcps[name]?.memory = nil
    }

    private func tick() async {
        retryDue()
        ticks += 1
        if ticks % 5 == 0 { await sampleMemory() }
    }

    /// 量一次各常驻 MCP 的内存（进程树的 RSS 合计）。HTTP 上游没有本地进程，不量。
    private func sampleMemory() async {
        let pids = connections.compactMapValues(\.pid)
        guard !pids.isEmpty else { return }
        let bytes = await Task.detached(priority: .utility) { ProcessMemory.treeRSS(pids) }.value
        guard !bytes.isEmpty else { return }
        for (name, b) in bytes { mcps[name]?.memory = b }
        emit(.memory(core: nil, mcps: bytes))
    }

    private func retryDue() {
        let now = Date.now
        for name in orderedNames {
            if case .backoff(_, let at, _) = mcps[name]!.state, at <= now, isReferenced(name) { probe(name) }
        }
    }

    // MARK: CoreClient

    func setDefault(mcp name: String, on: Bool) async throws {
        guard config.mcps[name] != nil else { throw CoreError.unknownMCP(name) }
        try change { c in
            var x = c.mcps[name]!.x ?? .init()
            x.default = on ? nil : false
            c.mcps[name]!.x = x == .init() ? nil : x
        }
        mcps[name]?.inDefault = on
        emit(.mcp(mcps[name]!))
        refreshLifecycle(name)
    }

    func restart(mcp name: String) async throws {
        try requireManage()
        guard mcps[name] != nil else { throw CoreError.unknownMCP(name) }
        mcps[name]!.restarts += 1
        probe(name)
    }

    func retryNow(mcp name: String) async throws {
        try requireManage()
        guard mcps[name] != nil else { throw CoreError.unknownMCP(name) }
        probe(name)
    }

    func addMCP(_ draft: MCPDraft) async throws {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { throw CoreError.missingField("名字") }
        try validate(name)
        guard config.mcps[name] == nil else { throw CoreError.duplicateMCP(name) }
        if draft.target.trimmingCharacters(in: .whitespaces).isEmpty { throw CoreError.missingField(draft.kind.targetLabel) }
        let entry = ConfigFile.MCPEntry(draft: draft)
        try change { $0.mcps[name] = entry }
        mcps[name] = server(name, entry)
        log(name, .info, "已添加")
        emit(.mcp(mcps[name]!))
        refreshLifecycle(name)
    }

    func createService(name: String, mcps names: [String]) async throws {
        try validate(name)
        guard config.services[name] == nil else { throw CoreError.duplicateName(name) }
        try change { $0.services[name] = .init(mcps: names) }
        emit(.services(namedServices))
        names.forEach(refreshLifecycle)
    }

    func setServiceMembers(service: String, mcps names: [String]) async throws {
        guard let old = config.services[service]?.mcps else { return }
        let ordered = orderedNames.filter(names.contains)
        try change { $0.services[service]?.mcps = ordered }
        emit(.services(namedServices))
        Set(old).union(names).forEach(refreshLifecycle)
    }

    func renameService(_ name: String, to newName: String) async throws {
        try validate(newName)
        guard config.services[newName] == nil else { throw CoreError.duplicateName(newName) }
        guard let s = config.services[name] else { return }
        try change { c in
            c.services[name] = nil
            c.services[newName] = s
        }
        emit(.services(namedServices))
    }

    func deleteService(_ name: String) async throws {
        guard let removed = config.services[name]?.mcps else { return }
        try change { $0.services[name] = nil }
        emit(.services(namedServices))
        removed.forEach(refreshLifecycle)
    }

    /// 改网关端口，马上写进配置。网关接入后由它按新端口重新监听。
    func setPort(_ port: Int) async throws {
        guard (1024...65535).contains(port) else { throw CoreError.invalidPort(port) }
        try change { $0.port = port }
        core.port = port
        startGateway()
        emit(.core(core))
    }

    /// "重新检测"：重新读配置文件（也就接上了手动改过的内容），所有用到的 MCP 重新握手。
    func restartCore() async throws {
        failures = [:]
        reload()
        emit(snapshot)
    }

    func importConfig(_ data: Data) async throws -> String {
        try requireManage()
        let imported = try ConfigStore.parseImport(data)
        var added = 0, updated = 0
        var skipped: [String] = []
        try change { c in
            for (name, entry) in imported.mcps {
                guard Self.isValidName(name) else { skipped.append(name); continue }
                if c.mcps[name] == nil { added += 1 } else { updated += 1 }
                c.mcps[name] = entry
            }
            for (name, s) in imported.services where Self.isValidName(name) { c.services[name] = s }
            for (k, v) in imported.env { c.env[k] = v }
        }
        reload()
        emit(snapshot)
        var parts = ["导入完成：新增 \(added) 个 MCP"]
        if updated > 0 { parts.append("更新 \(updated) 个") }
        if !imported.services.isEmpty { parts.append("\(imported.services.count) 个服务") }
        if !skipped.isEmpty { parts.append("跳过名字不合法的 \(skipped.count) 个（\(skipped.prefix(3).joined(separator: "、"))）") }
        return parts.joined(separator: "，")
    }

    func exportConfig() async throws -> Data {
        try requireManage()
        return try ConfigStore.encode(config)
    }

    /// 试调用：真的连上这个 MCP 调一次工具，结果记进调用记录（服务写"试调用"，客户端写"MCP Mac"）。
    func callTool(mcp name: String, tool: String, argumentsJSON: String) async throws -> ToolCallResult {
        try requireManage()
        guard let entry = config.mcps[name] else { throw CoreError.unknownMCP(name) }
        let started = Date.now
        let clock = ContinuousClock()
        let t0 = clock.now
        // 有常驻连接就直接用（不用再冷启动一遍）；没有就临时连一次
        let r: Swift.Result<MCPProbe.CallOutput, MCPProbe.Failure>
        if let conn = connections[name] {
            r = await conn.call(tool: tool, argumentsJSON: argumentsJSON)
            if case .failure(.transient(let m, _)) = r, m.contains("秒内没有完成"), connections[name] === conn {
                probe(name)   // 卡住的进程已经关掉，重新连
            }
        } else {
            r = await MCPProbe.call(entry, globalEnv: config.env, tool: tool, argumentsJSON: argumentsJSON)
        }
        let elapsed = clock.now - t0
        let result: ToolCallResult
        switch r {
        case .success(let out):
            result = ToolCallResult(isError: out.isError, text: out.text, duration: elapsed)
        case .failure(.config(let m, _)), .failure(.transient(let m, _)):
            result = ToolCallResult(isError: true, text: m, duration: elapsed)
        }
        recordCall(mcp: name, tool: tool, service: "试调用", client: "MCP Mac", started: started, elapsed: elapsed,
                   error: result.isError ? result.text : nil)
        log(name, result.isError ? .warn : .info, "试调用 \(tool)：\(result.isError ? "出错" : "成功")")
        return result
    }

    // MARK: 内部

    /// 改配置并落盘；写不进去就把内存里的配置退回去，再把错误抛给界面。
    private func change(_ body: (inout ConfigFile) -> Void) throws {
        try requireManage()
        let old = config
        body(&config)
        do {
            try ConfigStore.save(config)
        } catch {
            config = old
            throw ConfigError.unreadable("保存失败：\(error.localizedDescription)")
        }
    }

    private func requireManage() throws {
        if let loadError { throw ConfigError.unreadable(loadError) }
    }

    private func validate(_ name: String) throws {
        if !Self.isValidName(name) { throw CoreError.invalidName(name) }
    }

    /// 名字会出现在地址里（/servers/<名字>/mcp、/s/<名字>/mcp），只允许字母、数字、- 和 _。
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private func log(_ name: String, _ level: LogLine.Level, _ text: String) {
        nextLogID += 1
        mcps[name]?.stderr.append(LogLine(id: nextLogID, time: .now, level: level, text: text))
        if let n = mcps[name]?.stderr.count, n > 200 { mcps[name]!.stderr.removeFirst(n - 200) }
    }
}

// MARK: - 内存

/// 进程树的内存：一次 `ps` 拿到所有进程的 pid / ppid / RSS，再把每个根进程和它所有子孙加起来。
/// npx / uvx 起的 MCP 真正干活的是子进程，只量根进程会少算。
enum ProcessMemory {
    static func treeRSS(_ roots: [String: Int32]) -> [String: Int64] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-A", "-o", "pid=,ppid=,rss="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var children: [Int32: [Int32]] = [:]
        var rss: [Int32: Int64] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 3, let pid = Int32(f[0]), let ppid = Int32(f[1]), let kb = Int64(f[2]) else { continue }
            children[ppid, default: []].append(pid)
            rss[pid] = kb * 1024
        }
        var result: [String: Int64] = [:]
        for (name, root) in roots where rss[root] != nil {
            var total: Int64 = 0
            var stack = [root]
            while let pid = stack.popLast() {
                total += rss[pid] ?? 0
                stack += children[pid] ?? []
            }
            result[name] = total
        }
        return result
    }
}

// MARK: - 调用记录

/// 调用记录落盘：配置文件旁边的 calls.jsonl，一行一条，只追加。启动时读最近的几千条。
enum CallLog {
    static var url: URL { ConfigStore.url.deletingLastPathComponent().appendingPathComponent("calls.jsonl") }

    static func load(max: Int) -> [CallRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        let records = lines.suffix(max).compactMap { try? dec.decode(CallRecord.self, from: Data($0)) }
        // 文件比保留的多出一倍就整理一次，免得一直长
        if lines.count > max * 2 {
            let enc = JSONEncoder()
            let body = records.compactMap { try? enc.encode($0) }.map { $0 + Data([0x0A]) }.reduce(Data(), +)
            try? ConfigStore.write(body, to: url)
        }
        return records
    }

    static func append(_ record: CallRecord) {
        guard var line = try? JSONEncoder().encode(record) else { return }
        line.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? ConfigStore.write(line, to: url)
            return
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
    }
}

// MARK: - 网关

struct GatewaySession: Sendable {
    var client: String
    var route: GatewayRoute
}

enum GatewayRoute: Equatable, Sendable {
    case all
    case named(String)
    case single(String)

    init?(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        switch parts.count {
        case 1 where parts[0] == "mcp": self = .all
        case 3 where parts[0] == "s" && parts[2] == "mcp": self = .named(parts[1])
        case 3 where parts[0] == "servers" && parts[2] == "mcp": self = .single(parts[1])
        default: return nil
        }
    }

    /// 调用记录里「服务」一栏。
    var serviceLabel: String {
        switch self {
        case .all: "默认"
        case .named(let n): n
        case .single: "单独地址"
        }
    }
}

extension LocalCore {
    fileprivate func startGateway() {
        guard loadError == nil else { return }
        let port = config.port
        sessions = [:]
        core.defaultSessions = 0
        gatewayServer.start(port: port) { [weak self] req in
            guard let self else { return .json(["error": "gone"], status: 404) }
            return await self.handleGateway(req)
        } onState: { [weak self] state in
            Task { await self?.gatewayStateChanged(state, port: port) }
        }
    }

    private func gatewayStateChanged(_ state: GatewayServer.State, port: Int) {
        guard port == config.port else { return }
        switch state {
        case .ready:
            core.state = .running(pid: Int(getpid()), since: .now)
        case .failed:
            // 端口被占等：配置和检测照常可用（不能用 .stopped，那样连改端口都改不了）；设置页的端口那一行会提示被谁占着
            core.state = .notInstalled
        }
        emit(.core(core))
    }

    private func members(_ route: GatewayRoute) -> [String] {
        switch route {
        case .all: orderedNames.filter { config.mcps[$0]?.isDefault ?? false }
        case .named(let n): config.services[n]?.mcps.filter { config.mcps[$0] != nil } ?? []
        case .single(let n): config.mcps[n] == nil ? [] : [n]
        }
    }

    /// 工具名前缀：聚合地址用 `<别名或名字>__`，单个 MCP 的地址不加。
    private func prefix(_ mcp: String, _ route: GatewayRoute) -> String {
        if case .single = route { return "" }
        return (config.mcps[mcp]?.x?.alias ?? mcp) + "__"
    }

    private func updateSessionCounts() {
        core.defaultSessions = sessions.values.filter { $0.route == .all }.count
        emit(.core(core))
        emit(.services(namedServices))
    }

    func handleGateway(_ req: GatewayServer.Request) async -> GatewayServer.Response {
        guard let route = GatewayRoute(path: req.path) else { return .json(["error": "没有这个地址：\(req.path)"], status: 404) }
        if case .named(let n) = route, config.services[n] == nil { return .json(["error": "没有服务 \(n)"], status: 404) }
        if case .single(let n) = route, config.mcps[n] == nil { return .json(["error": "没有 MCP \(n)"], status: 404) }
        let sid = req.headers["mcp-session-id"]
        switch req.method {
        case "POST": break
        case "DELETE":
            if let sid, sessions.removeValue(forKey: sid) != nil { updateSessionCounts() }
            return GatewayServer.Response(status: 200)
        default:
            // 不提供服务器主动推送的 SSE 流
            return GatewayServer.Response(status: 405, headers: ["Allow": "POST, DELETE"])
        }
        guard let msg = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
              let method = msg["method"] as? String else {
            return .json(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "不是一条 JSON-RPC 请求"]], status: 400)
        }
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        // 通知（没有 id）：收下就行
        guard let id else { return GatewayServer.Response(status: 202) }

        func reply(_ result: Any, headers: [String: String] = [:]) -> GatewayServer.Response {
            .json(["jsonrpc": "2.0", "id": id, "result": result], headers: headers)
        }
        func fail(_ code: Int, _ message: String) -> GatewayServer.Response {
            .json(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }

        if method == "initialize" {
            let newID = UUID().uuidString
            let info = params["clientInfo"] as? [String: Any] ?? [:]
            let client = [info["name"] as? String, info["version"] as? String].compactMap { $0 }.joined(separator: " ")
            sessions[newID] = GatewaySession(client: client.isEmpty ? "未知客户端" : client, route: route)
            updateSessionCounts()
            return reply([
                "protocolVersion": params["protocolVersion"] as? String ?? MCPProbe.protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "MCP Mac", "version": AppInfo.version],
            ], headers: ["Mcp-Session-Id": newID])
        }
        // App 重启后旧会话 id 就没了：按规范回 404，客户端会重新 initialize
        if let sid, sessions[sid] == nil { return .json(["error": "会话已失效，请重新连接"], status: 404) }
        let client = sid.flatMap { sessions[$0]?.client } ?? "未知客户端"

        switch method {
        case "ping":
            return reply([String: Any]())
        case "tools/list":
            var tools: [[String: Any]] = []
            for m in members(route) {
                guard let server = mcps[m], server.state == .ready else { continue }
                let p = prefix(m, route)
                for t in server.tools {
                    let schema: Any = t.inputSchema.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? ["type": "object"]
                    tools.append(["name": p + t.name, "description": t.description ?? t.summary, "inputSchema": schema])
                }
            }
            return reply(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String else { return fail(-32602, "缺少工具名") }
            // 前缀最长的先匹配，免得 a__ 抢了 a_b__ 的工具
            let candidates = members(route).map { ($0, prefix($0, route)) }.sorted { $0.1.count > $1.1.count }
            guard let (m, p) = candidates.first(where: { name.hasPrefix($0.1) }) else { return fail(-32602, "没有这个工具：\(name)") }
            let tool = String(name.dropFirst(p.count))
            guard let conn = connections[m] else {
                return fail(-32603, "\(m) 现在没在运行（\(Format.stateLabel(mcps[m]?.state ?? .stopped))）")
            }
            var upstream = params
            upstream["name"] = tool
            let body = (try? JSONSerialization.data(withJSONObject: upstream)) ?? Data("{}".utf8)
            let started = Date.now
            let clock = ContinuousClock(), t0 = clock.now
            let r = await conn.forward("tools/call", params: body)
            let elapsed = clock.now - t0
            switch r {
            case .success(let data):
                let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                let isError = result["isError"] as? Bool ?? false
                let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
                recordCall(mcp: m, tool: tool, service: route.serviceLabel, client: client, started: started, elapsed: elapsed,
                           error: isError ? (text.isEmpty ? "工具返回出错" : text) : nil)
                return reply(result)
            case .failure(.config(let reason, _)), .failure(.transient(let reason, _)):
                recordCall(mcp: m, tool: tool, service: route.serviceLabel, client: client, started: started, elapsed: elapsed, error: reason)
                if reason.contains("秒内没有完成"), connections[m] === conn { probe(m) }
                return fail(-32603, reason)
            }
        case "resources/list":
            return reply(["resources": [Any]()])
        case "resources/templates/list":
            return reply(["resourceTemplates": [Any]()])
        case "prompts/list":
            return reply(["prompts": [Any]()])
        default:
            return fail(-32601, "MCP Mac 网关还不支持 \(method)")
        }
    }

    /// 记一条调用：内存里留最近的，磁盘上追加一行，推给界面。
    fileprivate func recordCall(mcp: String, tool: String, service: String, client: String,
                                started: Date, elapsed: Duration, error: String?) {
        nextCallID += 1
        let firstLine = error.map { $0.split(whereSeparator: \.isNewline).first.map(String.init) ?? "出错" }
        let record = CallRecord(id: nextCallID, time: started, mcp: mcp, tool: tool, service: service, client: client,
                                duration: elapsed, outcome: firstLine.map { .error(String($0.prefix(200))) } ?? .ok)
        calls.append(record)
        if calls.count > Self.maxCalls { calls.removeFirst(calls.count - Self.maxCalls) }
        CallLog.append(record)
        emit(.calls([record]))
    }
}
