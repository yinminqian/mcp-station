import Foundation

/// 内核（mcp-core，Rust）的控制接口客户端。界面只认 `CoreClient`，换掉原来 App 里的临时网关（LocalCore）后界面不用动。
///
/// - 端口和令牌在内核写的 runtime.json 里（数据目录，见 `ConfigStore.dataDir`）；
/// - 实时状态订阅 `GET /control/events`（SSE）：每个事件固定两行 `event:` + `data:`，按行读；
/// - 断了每秒重连；连不上几次后问 `mcp-core status` 内核为什么不在，必要时自动安装（App 包里带着内核）。
actor HTTPCoreClient: CoreClient {
    /// 这个 App 需要的控制接口版本。内核报的不一样就提示重启（重启会升级内核）。
    static let apiVersion = 1

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 700
        c.timeoutIntervalForResource = .infinity
        return URLSession(configuration: c)
    }()
    /// 最后一次知道的内核状态（断线时在它的基础上改 state，端口、版本这些还能显示）。
    private var lastCore = CoreStatus(version: "—", port: ConfigFile.defaultPort, state: .restarting, defaultSessions: 0)
    private var lastInstallAttempt: Date = .distantPast

    nonisolated func updates() -> AsyncStream<CoreUpdate> {
        AsyncStream { continuation in
            let task = Task { await self.pump(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func pump(_ out: AsyncStream<CoreUpdate>.Continuation) async {
        var failures = 0
        while !Task.isCancelled {
            if let rt = Runtime.read() {
                do {
                    var req = URLRequest(url: rt.url("/control/events"))
                    req.setValue("Bearer \(rt.token)", forHTTPHeaderField: "Authorization")
                    req.timeoutInterval = .infinity
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw CoreError.notRunning }
                    var event = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            failures = 0
                            if let u = decode(event, Data(line.dropFirst(5).utf8)) { out.yield(u) }
                        }
                    }
                } catch {}
            }
            if Task.isCancelled { return }
            failures += 1
            if failures == 1 {
                lastCore.state = .restarting
                out.yield(.core(lastCore))
            } else if failures % 5 == 0 {
                lastCore.state = await diagnose()
                out.yield(.core(lastCore))
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// 内核连不上：问 `mcp-core status` 为什么，没装或没在跑就装 / 拉起一次（最多 30 秒一次）。
    private func diagnose() async -> CoreState {
        let st = await CoreInstaller.status()
        let installed = st?["installed"] as? Bool ?? false
        let pid = st?["pid"] as? Int
        if (!installed || pid == nil), Date.now.timeIntervalSince(lastInstallAttempt) > 30, CoreInstaller.bundled != nil {
            lastInstallAttempt = .now
            if (try? await CoreInstaller.ensure(restart: false)) != nil { return .restarting }
        }
        let tail = st?["logTail"] as? [String] ?? []
        let exit = st?["lastExitCode"] as? Int ?? 0
        let owner = st?["portOwner"] as? String
        let reason: CoreDownReason
        if st?["disabled"] as? Bool == true {
            reason = .init(title: "后台服务被系统关掉了",
                           detail: "在「系统设置 → 通用 → 登录项与扩展」里打开 mcp-core，然后点「重启」。",
                           occupiedBy: nil, lastExitCode: exit, logTail: tail)
        } else if CoreInstaller.bundled == nil, !installed {
            reason = .init(title: "后台服务没有安装", detail: "这个 App 包里没有带内核（mcp-core），用 scripts/build-app.sh 重新构建。",
                           occupiedBy: nil, lastExitCode: 0, logTail: [])
        } else if exit != 0 {
            reason = .init(title: "后台服务启动后退出了（退出码 \(exit)）", detail: "下面是内核日志的最后几行。点「重启」再试一次。",
                           occupiedBy: owner, lastExitCode: exit, logTail: tail)
        } else {
            reason = .init(title: "后台服务没有运行", detail: "点「重启」启动它。", occupiedBy: owner, lastExitCode: exit, logTail: tail)
        }
        return .stopped(reason: reason)
    }

    // MARK: 事件 → CoreUpdate

    private func decode(_ event: String, _ data: Data) -> CoreUpdate? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        switch event {
        case "snapshot":
            guard let d = obj as? [String: Any], let c = d["core"] as? [String: Any] else { return nil }
            let core = Self.core(c)
            lastCore = core
            return .snapshot(core, (d["mcps"] as? [[String: Any]] ?? []).map(Self.mcp),
                             (d["services"] as? [[String: Any]] ?? []).map(Self.service),
                             (d["calls"] as? [[String: Any]] ?? []).map(Self.call))
        case "core":
            guard let c = obj as? [String: Any] else { return nil }
            lastCore = Self.core(c)
            return .core(lastCore)
        case "mcp":
            return (obj as? [String: Any]).map { .mcp(Self.mcp($0)) }
        case "services":
            return (obj as? [[String: Any]]).map { .services($0.map(Self.service)) }
        case "calls":
            return (obj as? [[String: Any]]).map { .calls($0.map(Self.call)) }
        case "memory":
            guard let d = obj as? [String: Any] else { return nil }
            let mcps = (d["mcps"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.int64Value }
            return .memory(core: (d["core"] as? NSNumber)?.int64Value, mcps: mcps)
        default:
            return nil
        }
    }

    private static func date(_ v: Any?) -> Date? { (v as? Double).map { Date(timeIntervalSince1970: $0) } }

    private static func core(_ c: [String: Any]) -> CoreStatus {
        let state: CoreState
        if (c["api"] as? Int) != apiVersion {
            state = .stopped(reason: .init(title: "内核版本不对",
                                           detail: "运行的内核接口版本是 \(c["api"] ?? "?")，这个 App 需要 \(apiVersion)。点「重启」会升级内核，客户端会断几秒。",
                                           occupiedBy: nil, lastExitCode: 0, logTail: []))
        } else if let e = c["configError"] as? String {
            state = .stopped(reason: .init(title: "配置文件读不了",
                                           detail: "\(e)\n修好或移走这个文件后点「重启」。在修好之前不会改动它（现在用的是上一份能用的备份）。",
                                           occupiedBy: nil, lastExitCode: 0, logTail: []))
        } else if c["gatewayError"] is String {
            // 网关端口起不来：配置能管、客户端连不上，正是 .notInstalled 的含义；设置页端口那一行会说被谁占着
            state = .notInstalled
        } else {
            state = .running(pid: c["pid"] as? Int ?? 0, since: date(c["startedAt"]) ?? .now)
        }
        return CoreStatus(version: c["version"] as? String ?? "—", port: c["port"] as? Int ?? ConfigFile.defaultPort, state: state,
                          defaultSessions: c["defaultSessions"] as? Int ?? 0, memory: (c["memory"] as? NSNumber)?.int64Value)
    }

    private static func mcp(_ d: [String: Any]) -> MCPServer {
        let entryData = (try? JSONSerialization.data(withJSONObject: d["entry"] ?? [:])) ?? Data("{}".utf8)
        let entry = (try? JSONDecoder().decode(ConfigFile.MCPEntry.self, from: entryData)) ?? .init()
        let error = d["error"] as? String ?? ""
        let state: MCPState = switch d["state"] as? String {
        case "ready": .ready
        case "starting": .starting
        case "backoff": .backoff(reason: error, retryAt: date(d["retryAt"]) ?? .now, attempts: d["attempts"] as? Int ?? 1)
        case "config_error": .configError(error)
        default: .stopped
        }
        let tools = (d["tools"] as? [[String: Any]] ?? []).map { t in
            let desc = t["description"] as? String
            return ToolInfo(name: t["name"] as? String ?? "", summary: summary(desc), inputSchema: pretty(t["inputSchema"]), description: desc)
        }
        let log = (d["log"] as? [[String: Any]] ?? []).map { l in
            let level: LogLine.Level = switch l["level"] as? String {
            case "error": .error
            case "warn": .warn
            default: .info
            }
            return LogLine(id: l["id"] as? Int ?? 0, time: date(l["t"]) ?? .now, level: level, text: l["text"] as? String ?? "")
        }
        return MCPServer(name: d["name"] as? String ?? "", kind: entry.kind, definition: entry.displayFields, tools: tools,
                         resourceCount: d["resources"] as? Int ?? 0, promptCount: d["prompts"] as? Int ?? 0,
                         instructionsLength: d["instructionsLength"] as? Int ?? 0, inDefault: d["default"] as? Bool ?? true,
                         state: state, pid: d["pid"] as? Int, startedAt: date(d["startedAt"]), restarts: d["restarts"] as? Int ?? 0,
                         stderr: log, memory: (d["memory"] as? NSNumber)?.int64Value)
    }

    private static func service(_ d: [String: Any]) -> NamedService {
        NamedService(name: d["name"] as? String ?? "", mcpNames: d["mcps"] as? [String] ?? [], sessions: d["sessions"] as? Int ?? 0)
    }

    private static func call(_ d: [String: Any]) -> CallRecord {
        let service = switch d["route"] as? String {
        case "default": "默认"
        case "test": "试调用"
        case "single": "单独地址"
        default: d["service"] as? String ?? "—"
        }
        let error = d["error"] as? String
        return CallRecord(id: d["id"] as? Int ?? 0, time: date(d["t"]) ?? .now, mcp: d["mcp"] as? String ?? "",
                          tool: d["tool"] as? String ?? "", service: service, client: d["client"] as? String ?? "未知客户端",
                          duration: .milliseconds(d["ms"] as? Int ?? 0), outcome: error.map { .error($0) } ?? .ok)
    }

    /// 工具说明只留第一行，最多 120 个字。
    private static func summary(_ s: String?) -> String {
        let line = s?.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }

    private static func pretty(_ obj: Any?) -> String? {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: 操作

    func setDefault(mcp: String, on: Bool) async throws {
        _ = try await send("PUT", "/control/mcps/\(mcp)/default", ["on": on])
    }

    func restart(mcp: String) async throws {
        _ = try await send("POST", "/control/mcps/\(mcp)/restart")
    }

    func retryNow(mcp: String) async throws {
        _ = try await send("POST", "/control/mcps/\(mcp)/retry")
    }

    func addMCP(_ draft: MCPDraft) async throws {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { throw CoreError.missingField("名字") }
        if draft.target.trimmingCharacters(in: .whitespaces).isEmpty { throw CoreError.missingField(draft.kind.targetLabel) }
        let entry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ConfigFile.MCPEntry(draft: draft)))
        _ = try await send("POST", "/control/mcps", ["name": name, "entry": entry])
    }

    func createService(name: String, mcps: [String]) async throws {
        _ = try await send("POST", "/control/services", ["name": name, "mcps": mcps])
    }

    func setServiceMembers(service: String, mcps: [String]) async throws {
        _ = try await send("PUT", "/control/services/\(service)", ["mcps": mcps])
    }

    func renameService(_ name: String, to newName: String) async throws {
        _ = try await send("PUT", "/control/services/\(name)", ["name": newName])
    }

    func deleteService(_ name: String) async throws {
        _ = try await send("DELETE", "/control/services/\(name)")
    }

    func setPort(_ port: Int) async throws {
        _ = try await send("PUT", "/control/settings", ["port": port])
    }

    /// "重启"：重启内核（顺带升级成 App 包里带的版本）。内核卡死时也管用，因为它不走控制接口。
    func restartCore() async throws {
        try await CoreInstaller.ensure(restart: true)
    }

    func importConfig(_ data: Data) async throws -> String {
        let r = try await send("POST", "/control/import", raw: data) as? [String: Any] ?? [:]
        var parts = ["导入完成：新增 \(r["added"] as? Int ?? 0) 个 MCP"]
        if let u = r["updated"] as? Int, u > 0 { parts.append("更新 \(u) 个") }
        if let s = r["services"] as? Int, s > 0 { parts.append("\(s) 个服务") }
        if let skipped = r["skipped"] as? [String], !skipped.isEmpty {
            parts.append("跳过名字不合法的 \(skipped.count) 个（\(skipped.prefix(3).joined(separator: "、"))）")
        }
        return parts.joined(separator: "，")
    }

    func exportConfig() async throws -> Data {
        try await request("GET", "/control/export", body: nil).0
    }

    func callTool(mcp: String, tool: String, argumentsJSON: String) async throws -> ToolCallResult {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let args: Any
        if trimmed.isEmpty {
            args = [String: Any]()
        } else if let obj = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] {
            args = obj
        } else {
            return ToolCallResult(isError: true, text: "参数不是合法的 JSON 对象", duration: .zero)
        }
        let r = try await send("POST", "/control/mcps/\(mcp)/call", ["tool": tool, "arguments": args]) as? [String: Any] ?? [:]
        return ToolCallResult(isError: r["isError"] as? Bool ?? true, text: r["text"] as? String ?? "", duration: .milliseconds(r["ms"] as? Int ?? 0))
    }

    // MARK: 请求

    private func send(_ method: String, _ path: String, _ json: [String: Any]? = nil, raw: Data? = nil) async throws -> Any? {
        let body = try raw ?? json.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, _) = try await request(method, path, body: body)
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// 发一个控制请求。令牌不对（内核重启换了令牌）或连不上时重读 runtime.json 再试一次。
    private func request(_ method: String, _ path: String, body: Data?) async throws -> (Data, Int) {
        for attempt in 0..<2 {
            guard let rt = Runtime.read() else { throw CoreError.notRunning }
            var req = URLRequest(url: rt.url(path))
            req.httpMethod = method
            req.httpBody = body
            req.setValue("Bearer \(rt.token)", forHTTPHeaderField: "Authorization")
            if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let data: Data, resp: URLResponse
            do {
                (data, resp) = try await session.data(for: req)
            } catch {
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(500)); continue }
                throw CoreError.notRunning
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, attempt == 0 { continue }
            if (200..<300).contains(status) { return (data, status) }
            throw Self.error(data)
        }
        throw CoreError.notRunning
    }

    private static func error(_ data: Data) -> Error {
        let e = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        let message = e?["message"] as? String ?? "内核返回了错误"
        return switch e?["code"] as? String {
        case "unknown_mcp", "unknown_service": CoreAPIError(message: message)
        case "invalid_name": CoreError.invalidName(message)
        case "duplicate_mcp": CoreError.duplicateMCP(message)
        case "duplicate_name": CoreError.duplicateName(message)
        case "missing_field": CoreError.missingField(message)
        case "invalid_port": CoreError.invalidPort(Int(message) ?? 0)
        default: CoreAPIError(message: message)
        }
    }
}

/// 内核返回的、没有专门对应的错误：原样显示内核给的说明。
struct CoreAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 内核写的 runtime.json：控制接口的端口和令牌。
private struct Runtime {
    let controlPort: Int
    let token: String

    static func read() -> Runtime? {
        let url = ConfigStore.dataDir.appendingPathComponent("runtime.json")
        guard let d = try? Data(contentsOf: url),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let port = o["controlPort"] as? Int, let token = o["token"] as? String else { return nil }
        return Runtime(controlPort: port, token: token)
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(controlPort)\(path)")!
    }
}

/// 装 / 升级 / 重启内核，查它为什么不在。调 App 包里带的 `mcp-core`（它会把自己复制到数据目录、写 LaunchAgent）。
enum CoreInstaller {
    static var bundled: URL? { Bundle.main.url(forResource: "mcp-core", withExtension: nil) }

    /// 包里没带时（开发时直接跑 swift build 出来的二进制）用已经装好的那个查状态。
    private static var binary: URL? {
        bundled ?? {
            let installed = ConfigStore.dataDir.appendingPathComponent("bin/mcp-core")
            return FileManager.default.isExecutableFile(atPath: installed.path) ? installed : nil
        }()
    }

    static func status() async -> [String: Any]? {
        await run(["status"])
    }

    static func ensure(restart: Bool) async throws {
        guard bundled != nil else { throw CoreAPIError(message: "这个 App 包里没有带内核（mcp-core）") }
        let r = await run(restart ? ["install", "--restart"] : ["install"])
        if r?["ok"] as? Bool != true {
            throw CoreAPIError(message: "后台服务装不上：\(r?["error"] as? String ?? "没有输出")")
        }
    }

    private static func run(_ args: [String]) async -> [String: Any]? {
        guard let bin = args.first == "status" ? binary : bundled else { return nil }
        let data: Data? = await Task.detached {
            let p = Process()
            p.executableURL = bin
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return data
        }.value
        // 最后一行是 JSON
        let line = data.flatMap { String(decoding: $0, as: UTF8.self).split(whereSeparator: \.isNewline).last.map(String.init) } ?? ""
        return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
}
