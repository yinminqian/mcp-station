import Foundation
import Security

/// 连 MCP：握手（initialize）→ 列出工具、resources、prompts。
///
/// 本地进程走标准输入输出（每行一条 JSON-RPC），HTTP 上游走 Streamable HTTP（响应可能是 JSON 或 SSE）。
/// `connect` 握手成功后连接留着（本地进程常驻），交给调用方用 `MCPConnection` 调工具、量内存；
/// `call` 是没有常驻连接时的一次性调用（连上、调一次、断开）。
enum MCPProbe {
    struct Result: Sendable {
        var tools: [ToolInfo]
        var resources: Int
        var prompts: Int
        var instructionsLength: Int
        /// 对方报的名字和版本（initialize 的 serverInfo）。
        var server: String
        /// 标准错误输出的最后几行（本地进程）。
        var log: [String]
    }

    enum Failure: Error, Sendable {
        /// 配置本身有问题（找不到命令、地址或认证不对），重试也没用。
        case config(String, log: [String])
        /// 暂时连不上、超时、握手出错，过一会儿自动重试。
        case transient(String, log: [String])
    }

    static let clientName = "MCP Mac"
    static let protocolVersion = "2025-06-18"

    /// 握手、列出工具 / resources / prompts，成功后连接不关，交给调用方（它负责 `close()`）。失败时连接已经关掉。
    static func connect(_ entry: ConfigFile.MCPEntry, globalEnv: [String: String],
                        timeout: Duration = .seconds(30)) async -> Swift.Result<(Result, MCPConnection), Failure> {
        let transport: any Transport
        switch await makeTransport(entry, globalEnv: globalEnv) {
        case .success(let t): transport = t
        case .failure(let f): return .failure(f)
        }
        let r = await withTimeout(timeout, what: "握手", transport) { await handshake($0) }
        switch r {
        case .success(let result): return .success((result, MCPConnection(transport)))
        case .failure(let f):
            transport.close()
            return .failure(f)
        }
    }

    /// 试调用的输出。
    struct CallOutput: Sendable {
        var isError: Bool
        var text: String
    }

    /// 一次性试调用（没有常驻连接时用）：连上、握手、调一次 `tools/call`、断开。
    static func call(_ entry: ConfigFile.MCPEntry, globalEnv: [String: String], tool: String, argumentsJSON: String,
                     timeout: Duration = .seconds(60)) async -> Swift.Result<CallOutput, Failure> {
        if let bad = invalidArguments(argumentsJSON) { return .failure(bad) }
        let transport: any Transport
        switch await makeTransport(entry, globalEnv: globalEnv) {
        case .success(let t): transport = t
        case .failure(let f): return .failure(f)
        }
        defer { transport.close() }
        return await withTimeout(timeout, what: "调用", transport) { t in
            do {
                _ = try await initialize(t)
            } catch let f as Failure {
                return .failure(f)
            } catch {
                return .failure(.transient(error.localizedDescription, log: t.log()))
            }
            return await callTool(t, tool: tool, argumentsJSON: argumentsJSON)
        }
    }

    fileprivate static func invalidArguments(_ json: String) -> Failure? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] == nil {
            return .config("参数不是合法的 JSON 对象", log: [])
        }
        return nil
    }

    /// 在已经握过手的连接上调一次 `tools/call`。
    fileprivate static func callTool(_ t: any Transport, tool: String, argumentsJSON: String) async -> Swift.Result<CallOutput, Failure> {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = trimmed.isEmpty ? [:] : (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] ?? [:]
        do {
            let r = try await t.request("tools/call", ["name": tool, "arguments": args])
            return .success(CallOutput(isError: r["isError"] as? Bool ?? false, text: contentText(r["content"])))
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(.transient(error.localizedDescription, log: t.log()))
        }
    }

    private static func makeTransport(_ entry: ConfigFile.MCPEntry, globalEnv: [String: String]) async -> Swift.Result<any Transport, Failure> {
        let env = await ProbeEnvironment.merged(global: globalEnv, own: entry.env ?? [:])
        do {
            if let url = entry.url {
                return .success(try HTTPTransport(url: ProbeEnvironment.expand(url, env), headers: (entry.headers ?? [:]).mapValues { ProbeEnvironment.expand($0, env) },
                                                  caCert: entry.x?.caCert.map { ($0 as NSString).expandingTildeInPath }))
            } else if let command = entry.command {
                return .success(try StdioTransport(command: ProbeEnvironment.expand(command, env),
                                                   args: (entry.args ?? []).map { ProbeEnvironment.expand($0, env) }, env: env))
            } else {
                return .failure(.config("既没有 command 也没有 url", log: []))
            }
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(.config(error.localizedDescription, log: []))
        }
    }

    /// 跑 `body`，超过 `timeout` 就返回超时失败（不关连接，由调用方决定）。
    fileprivate static func withTimeout<R: Sendable>(_ timeout: Duration, what: String, _ transport: any Transport,
                                                    _ body: @escaping @Sendable (any Transport) async -> Swift.Result<R, Failure>)
        async -> Swift.Result<R, Failure> {
        await withTaskGroup(of: Swift.Result<R, Failure>?.self) { group in
            group.addTask { await body(transport) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return Task.isCancelled ? nil : .failure(.transient("\(timeout.components.seconds) 秒内没有完成\(what)", log: transport.log()))
            }
            var first: Swift.Result<R, Failure>?
            for await r in group where r != nil {
                first = r
                break
            }
            group.cancelAll()
            return first ?? .failure(.transient("被取消", log: []))
        }
    }

    /// initialize + notifications/initialized，返回 initialize 的结果。
    private static func initialize(_ t: any Transport) async throws -> [String: Any] {
        let initResult = try await t.request("initialize", [
            "protocolVersion": protocolVersion,
            "capabilities": [String: Any](),
            "clientInfo": ["name": clientName, "version": AppInfo.version],
        ])
        if let v = initResult["protocolVersion"] as? String { t.negotiated(version: v) }
        try await t.notify("notifications/initialized")
        return initResult
    }

    private static func handshake(_ t: any Transport) async -> Swift.Result<Result, Failure> {
        do {
            let initResult = try await initialize(t)
            let caps = initResult["capabilities"] as? [String: Any] ?? [:]
            let info = initResult["serverInfo"] as? [String: Any] ?? [:]
            let server = [info["name"] as? String, info["version"] as? String].compactMap { $0 }.joined(separator: " ")

            var tools: [ToolInfo] = []
            if caps["tools"] != nil {
                var cursor: String?
                for _ in 0..<20 {
                    let r = try await t.request("tools/list", cursor.map { ["cursor": $0] } ?? [:])
                    for item in r["tools"] as? [[String: Any]] ?? [] {
                        guard let name = item["name"] as? String else { continue }
                        tools.append(ToolInfo(name: name, summary: summary(item["description"] as? String),
                                              inputSchema: pretty(item["inputSchema"]),
                                              description: item["description"] as? String))
                    }
                    cursor = r["nextCursor"] as? String
                    if cursor == nil { break }
                }
            }
            let resources = caps["resources"] != nil ? (try? await t.request("resources/list", [:]))?["resources"] as? [Any] : nil
            let prompts = caps["prompts"] != nil ? (try? await t.request("prompts/list", [:]))?["prompts"] as? [Any] : nil
            return .success(Result(tools: tools, resources: resources?.count ?? 0, prompts: prompts?.count ?? 0,
                                   instructionsLength: (initResult["instructions"] as? String)?.count ?? 0,
                                   server: server, log: t.log()))
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(.transient(error.localizedDescription, log: t.log()))
        }
    }

    private static func pretty(_ obj: Any?) -> String? {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// tools/call 返回的 content：文字原样拼起来，图片等写成占位说明；太长就截断（最多 20000 字）。
    private static func contentText(_ content: Any?) -> String {
        let parts: [String] = (content as? [[String: Any]] ?? []).map { item in
            switch item["type"] as? String {
            case "text": return item["text"] as? String ?? ""
            case "image": return "[图片 \(item["mimeType"] as? String ?? "")]"
            case "audio": return "[音频 \(item["mimeType"] as? String ?? "")]"
            case "resource", "resource_link":
                let r = item["resource"] as? [String: Any]
                return "[资源 \(r?["uri"] as? String ?? item["uri"] as? String ?? "")]"
            default: return "[\(item["type"] as? String ?? "未知内容")]"
            }
        }
        let text = parts.joined(separator: "\n")
        return text.count > 20000 ? String(text.prefix(20000)) + "\n…（已截断）" : text
    }

    /// 工具说明只留第一行，最多 120 个字。
    private static func summary(_ s: String?) -> String {
        let line = s?.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }
}

/// 一条常驻的 MCP 连接（本地进程一直开着）。调用按顺序一个一个来，不并发写同一个进程。
final class MCPConnection: @unchecked Sendable {
    fileprivate let transport: any Transport
    private let gate = CallGate()

    fileprivate init(_ transport: any Transport) {
        self.transport = transport
    }

    /// 本地进程的 pid；HTTP 上游没有。
    var pid: Int32? { (transport as? StdioTransport)?.pid }

    /// 本地进程自己退出时（崩了、被杀）回调一次，参数是给人看的原因。主动 `close()` 不算。
    func onExit(_ handler: @escaping @Sendable (String) -> Void) {
        (transport as? StdioTransport)?.setOnExit(handler)
    }

    /// 调一次工具。超时会关掉连接（卡住的进程不能再用），调用方需要重新连。
    func call(tool: String, argumentsJSON: String, timeout: Duration = .seconds(60)) async -> Swift.Result<MCPProbe.CallOutput, MCPProbe.Failure> {
        if let bad = MCPProbe.invalidArguments(argumentsJSON) { return .failure(bad) }
        let t = transport
        return await gate.run {
            let r = await MCPProbe.withTimeout(timeout, what: "调用", t) { await MCPProbe.callTool($0, tool: tool, argumentsJSON: argumentsJSON) }
            if case .failure(.transient(let m, _)) = r, m.contains("秒内没有完成") { t.close() }
            return r
        }
    }

    /// 网关转发：把一条请求（参数是 JSON 编码的对象）原样发给上游，拿回 result 的 JSON。
    func forward(_ method: String, params: Data, timeout: Duration = .seconds(120)) async -> Swift.Result<Data, MCPProbe.Failure> {
        let t = transport
        return await gate.run {
            let r = await MCPProbe.withTimeout(timeout, what: method, t) { t -> Swift.Result<Data, MCPProbe.Failure> in
                let p = (try? JSONSerialization.jsonObject(with: params)) as? [String: Any] ?? [:]
                do {
                    let result = try await t.request(method, p)
                    return .success((try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8))
                } catch let f as MCPProbe.Failure {
                    return .failure(f)
                } catch {
                    return .failure(.transient(error.localizedDescription, log: t.log()))
                }
            }
            if case .failure(.transient(let m, _)) = r, m.contains("秒内没有完成") { t.close() }
            return r
        }
    }

    func close() { transport.close() }
}

/// 让异步操作排队一个一个执行。
private actor CallGate {
    private var tail: Task<Void, Never>?

    func run<R: Sendable>(_ op: @escaping @Sendable () async -> R) async -> R {
        let previous = tail
        let task = Task { await previous?.value; return await op() }
        tail = Task { _ = await task.value }
        return await task.value
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
}

// MARK: - 环境变量

/// 从图形界面启动的 App 拿到的 PATH 很短（没有 Homebrew、nvm），npx / uvx 都找不到。
/// 所以第一次检测前从用户的登录 shell 读一次 PATH，再叠加全局环境变量和每个 MCP 自己的环境变量。
enum ProbeEnvironment {
    private static let cache = PathCache()

    static func merged(global: [String: String], own: [String: String]) async -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = await cache.loginPath()
        for (k, v) in global { env[k] = expand(v, env) }
        for (k, v) in own { env[k] = expand(v, env) }
        return env
    }

    /// 把 `${NAME}` 换成环境变量的值；没有这个变量就换成空串。
    static func expand(_ s: String, _ env: [String: String]) -> String {
        guard s.contains("${") else { return s }
        var out = "", rest = Substring(s)
        while let start = rest.range(of: "${"), let end = rest[start.upperBound...].firstIndex(of: "}") {
            out += rest[..<start.lowerBound]
            out += env[String(rest[start.upperBound..<end])] ?? ""
            rest = rest[rest.index(after: end)...]
        }
        return out + rest
    }

    private actor PathCache {
        private var path: String?

        func loginPath() async -> String {
            if let path { return path }
            let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            let shell = getpwuid(getuid()).map { String(cString: $0.pointee.pw_shell) } ?? ""
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell.isEmpty ? "/bin/zsh" : shell)
            p.arguments = ["-ilc", "printf '\\n__MCPMAC_PATH__%s' \"$PATH\""]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var result = fallback
            if (try? p.run()) != nil {
                let proc = Unchecked(value: p), handle = Unchecked(value: out.fileHandleForReading)
                let killer = Task { try? await Task.sleep(for: .seconds(5)); if proc.value.isRunning { proc.value.terminate() } }
                let data = await Task.detached { handle.value.readDataToEndOfFile() }.value
                killer.cancel()
                if let text = String(data: data, encoding: .utf8),
                   let r = text.range(of: "__MCPMAC_PATH__", options: .backwards) {
                    let found = text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !found.isEmpty { result = found }
                }
            }
            path = result
            return result
        }
    }
}

// MARK: - 传输

private protocol Transport: Sendable {
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any]
    func notify(_ method: String) async throws
    func negotiated(version: String)
    func log() -> [String]
    func close()
}

/// 把不标 Sendable 的系统对象（Process、FileHandle）带进别的任务。调用方保证不会并发改它。
private struct Unchecked<T>: @unchecked Sendable { let value: T }

/// 线程安全的小盒子（传输对象在几个任务之间共享）。
private final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ v: T) { value = v }
    func with<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

private func rpcError(_ msg: [String: Any]) -> String? {
    guard let e = msg["error"] as? [String: Any] else { return nil }
    return (e["message"] as? String) ?? "错误 \(e["code"] ?? "")"
}

/// 本地进程：`/usr/bin/env <command> <args…>`，按 PATH 找命令；stdin 写请求，stdout 一行一条响应。
private final class StdioTransport: Transport, @unchecked Sendable {
    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private let tail = Locked<[String]>([])
    private let nextID = Locked(0)
    private var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator
    private let command: String
    private let exitHandler = Locked<(@Sendable (String) -> Void)?>(nil)
    private let closing = Locked(false)

    var pid: Int32 { process.processIdentifier }

    func setOnExit(_ handler: @escaping @Sendable (String) -> Void) {
        exitHandler.with { $0 = handler }
    }

    init(command: String, args: [String], env: [String: String]) throws {
        self.command = command
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.environment = env
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        lines = stdout.fileHandleForReading.bytes.lines.makeAsyncIterator()
        let tail = self.tail
        stderr.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            tail.with { t in
                t += text.split(whereSeparator: \.isNewline).map(String.init)
                if t.count > 40 { t.removeFirst(t.count - 40) }
            }
        }
        let exitHandler = self.exitHandler, closing = self.closing
        process.terminationHandler = { p in
            guard !closing.with({ $0 }), let handler = exitHandler.with({ $0 }) else { return }
            let last = tail.with { $0.last }.map { "：\($0)" } ?? ""
            handler("进程退出了（退出码 \(p.terminationStatus)）\(last)")
        }
        do { try process.run() } catch {
            throw MCPProbe.Failure.config("启动不了「\(command)」：\(error.localizedDescription)", log: [])
        }
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID.with { $0 += 1; return $0 }
        try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while true {
            var it = lines
            let next = try await it.next()
            lines = it
            guard let line = next else { throw exited() }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // 对方发来的请求（比如 roots/list）：回一个"不支持"，免得它一直等
            if let m = msg["method"] as? String, let rid = msg["id"] {
                try? write(["jsonrpc": "2.0", "id": rid, "error": ["code": -32601, "message": "MCP Mac 不支持 \(m)"]])
                continue
            }
            guard (msg["id"] as? Int) == id else { continue }
            if let e = rpcError(msg) { throw MCPProbe.Failure.transient("\(method) 出错：\(e)", log: log()) }
            return msg["result"] as? [String: Any] ?? [:]
        }
    }

    func notify(_ method: String) async throws {
        try write(["jsonrpc": "2.0", "method": method])
    }

    func negotiated(version: String) {}

    func log() -> [String] { tail.with { $0 } }

    func close() {
        closing.with { $0 = true }
        try? stdin.fileHandleForWriting.close()   // 大多数 MCP 收到 EOF 就自己退出
        let p = Unchecked(value: process)
        guard p.value.isRunning else { return }
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if p.value.isRunning { p.value.terminate() }
            try? await Task.sleep(for: .seconds(2))
            if p.value.isRunning { kill(p.value.processIdentifier, SIGKILL) }
        }
    }

    private func write(_ obj: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: obj)
        data.append(0x0A)
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    /// stdout 关了：进程退出了。退出码 127 是 env 找不到命令。
    private func exited() -> MCPProbe.Failure {
        process.waitUntilExit()
        let code = process.terminationStatus
        let log = log()
        if code == 127 {
            return .config("找不到命令「\(command)」（PATH 里没有它）", log: log)
        }
        let last = log.last.map { "：\($0)" } ?? ""
        return .transient("进程退出了（退出码 \(code)）\(last)", log: log)
    }
}

/// HTTP 上游（Streamable HTTP）：每个请求一次 POST，响应是 JSON 或 SSE；会话 ID 在 Mcp-Session-Id 头里。
private final class HTTPTransport: NSObject, Transport, URLSessionDelegate, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let anchor: SecCertificate?
    private let state = Locked<(session: String?, version: String?, nextID: Int)>((nil, nil, 0))
    private var urlSession: URLSession!

    init(url raw: String, headers: [String: String], caCert: String?) throws {
        guard let u = URL(string: raw), let scheme = u.scheme, ["http", "https"].contains(scheme) else {
            throw MCPProbe.Failure.config("地址不对：\(raw)", log: [])
        }
        url = u
        self.headers = headers
        if let path = caCert {
            guard let cert = Self.loadCertificate(path) else {
                throw MCPProbe.Failure.config("读不了 CA 证书 \(path)", log: [])
            }
            anchor = cert
        } else {
            anchor = nil
        }
        super.init()
        urlSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = state.with { $0.nextID += 1; return $0.nextID }
        let (data, response) = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        if let sid = response.value(forHTTPHeaderField: "Mcp-Session-Id") { state.with { $0.session = sid } }
        let messages: [[String: Any]]
        if (response.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
            messages = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .filter { $0.hasPrefix("data:") }
                .compactMap { try? JSONSerialization.jsonObject(with: Data($0.dropFirst(5).utf8)) as? [String: Any] }
        } else {
            messages = [(try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]]
        }
        guard let msg = messages.first(where: { ($0["id"] as? Int) == id }) else {
            throw MCPProbe.Failure.transient("\(method) 没有收到响应", log: [])
        }
        if let e = rpcError(msg) { throw MCPProbe.Failure.transient("\(method) 出错：\(e)", log: []) }
        return msg["result"] as? [String: Any] ?? [:]
    }

    func notify(_ method: String) async throws {
        _ = try await post(["jsonrpc": "2.0", "method": method])
    }

    func negotiated(version: String) { state.with { $0.version = version } }

    func log() -> [String] { [] }

    func close() {
        // 礼貌地结束会话（失败也无所谓）
        if let sid = state.with({ $0.session }) {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let s: URLSession = urlSession
            Task.detached { _ = try? await s.data(for: req); s.finishTasksAndInvalidate() }
        } else {
            urlSession.finishTasksAndInvalidate()
        }
    }

    private func post(_ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let (sid, version) = state.with { ($0.session, $0.version) }
        if let sid { req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        if let version { req.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw MCPProbe.Failure.transient("连不上 \(url.absoluteString)（\(error.localizedDescription)）", log: [])
        }
        guard let http = response as? HTTPURLResponse else { throw MCPProbe.Failure.transient("响应不是 HTTP", log: []) }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw MCPProbe.Failure.config("认证失败（HTTP \(http.statusCode)），检查请求头里的令牌", log: [])
        case 404, 405: throw MCPProbe.Failure.config("这个地址不是 MCP 服务（HTTP \(http.statusCode)）", log: [])
        default: throw MCPProbe.Failure.transient("HTTP \(http.statusCode)", log: [])
        }
    }

    // 配了 CA 证书时，用它来信任自签证书的服务器
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let anchor, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)
        return SecTrustEvaluateWithError(trust, nil) ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
    }

    private static func loadCertificate(_ path: String) -> SecCertificate? {
        guard let raw = FileManager.default.contents(atPath: path) else { return nil }
        var der = raw
        if let text = String(data: raw, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") {
            let body = text.components(separatedBy: "-----BEGIN CERTIFICATE-----")[1]
                .components(separatedBy: "-----END CERTIFICATE-----")[0]
                .components(separatedBy: .whitespacesAndNewlines).joined()
            guard let d = Data(base64Encoded: body) else { return nil }
            der = d
        }
        return SecCertificateCreateWithData(nil, der as CFData)
    }
}
