import Foundation

/// 配置文件 `config.json`：唯一的配置来源（格式见 docs/ARCHITECTURE.md §4，也是将来 core 读的格式）。
///
/// `mcps` 里每一项沿用 Claude 的 `command/args/env` 与 `url/headers` 写法，本软件自己的字段都放在 `x` 里，
/// 所以和 Claude Code、Cursor 等客户端的 `mcpServers` 配置可以互相导入导出。
struct ConfigFile: Codable, Equatable, Sendable {
    var version = 1
    /// 没配端口时用这个。
    static let defaultPort = 8090

    var port = ConfigFile.defaultPort
    /// 全局环境变量，每个 MCP 都能用 `${名字}` 引用。
    var env: [String: String] = [:]
    var mcps: [String: MCPEntry] = [:]
    var services: [String: ServiceEntry] = [:]

    struct MCPEntry: Codable, Equatable, Sendable {
        var command: String?
        var args: [String]?
        var env: [String: String]?
        var url: String?
        var headers: [String: String]?
        var x: Extra?

        struct Extra: Codable, Equatable, Sendable {
            /// 是否加入默认服务。没写就是加入（新加的 MCP 默认打开）。
            var `default`: Bool?
            /// HTTP 上游用自签证书时，信任这个 CA 证书文件（PEM 或 DER）。
            var caCert: String?
            var alias: String?
            var timeoutSecs: Int?
            var notes: String?
        }

        var isDefault: Bool { x?.default ?? true }
    }

    struct ServiceEntry: Codable, Equatable, Sendable {
        var mcps: [String]
    }

    init() {}

    /// 字段都可以缺省，缺了就用默认值（手写的、别的工具生成的文件常常不全）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? ConfigFile.defaultPort
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        mcps = try c.decodeIfPresent([String: MCPEntry].self, forKey: .mcps) ?? [:]
        services = try c.decodeIfPresent([String: ServiceEntry].self, forKey: .services) ?? [:]
    }
}

/// 读写配置文件。路径固定在 `~/Library/Application Support/MCP Mac/config.json`；
/// 开发时可以用环境变量 `MCPMAC_CONFIG=<路径>` 指到别处，不碰自己的真实配置。
enum ConfigStore {
    static var url: URL {
        if let p = ProcessInfo.processInfo.environment["MCPMAC_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MCP Mac/config.json")
    }

    /// 文件不存在时返回空配置（第一次打开）。文件存在但读不了、格式不对时抛错——此时绝不能用空配置覆盖它。
    static func load() throws -> ConfigFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return ConfigFile() }
        return try JSONDecoder().decode(ConfigFile.self, from: Data(contentsOf: url))
    }

    /// 原子写入，权限 0600（里面可能有密钥）。
    static func save(_ config: ConfigFile) throws {
        try write(encode(config), to: url)
    }

    static func encode(_ config: ConfigFile) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(config)
    }

    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: 导入

    struct Imported: Sendable {
        var mcps: [String: ConfigFile.MCPEntry]
        var services: [String: ConfigFile.ServiceEntry]
        var env: [String: String]
    }

    /// 认这几种 JSON：
    /// - 本软件的 config.json（`mcps` / `services` / `env`）；
    /// - Claude Code、Claude Desktop、Cursor、mcp-proxy 等的 `{"mcpServers": {...}}`；
    /// - VS Code 的 `{"servers": {...}}`。
    /// 每一项认 `command` + `args` + `env`（本地进程）或 `url` + `headers`（HTTP），其余字段忽略，`description` 记成备注。
    static func parseImport(_ data: Data) throws -> Imported {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.unrecognized("最外层不是 JSON 对象")
        }
        let isOurs = root["mcps"] != nil
        guard let table = (root["mcps"] ?? root["mcpServers"] ?? root["servers"]) as? [String: Any] else {
            throw ConfigError.unrecognized("没有找到 mcps、mcpServers 或 servers")
        }
        var mcps: [String: ConfigFile.MCPEntry] = [:]
        for (name, raw) in table {
            guard let item = raw as? [String: Any] else { continue }
            var entry = ConfigFile.MCPEntry()
            entry.command = item["command"] as? String
            entry.args = (item["args"] as? [Any])?.compactMap { $0 as? String }
            entry.env = item["env"] as? [String: String]
            entry.url = item["url"] as? String ?? item["serverUrl"] as? String
            entry.headers = item["headers"] as? [String: String]
            if isOurs, let x = item["x"], let xd = try? JSONSerialization.data(withJSONObject: x) {
                entry.x = try? JSONDecoder().decode(ConfigFile.MCPEntry.Extra.self, from: xd)
            }
            if let note = item["description"] as? String, !note.isEmpty {
                entry.x = entry.x ?? .init()
                entry.x?.notes = note
            }
            guard entry.command != nil || entry.url != nil else { continue }
            mcps[name] = entry
        }
        guard !mcps.isEmpty else { throw ConfigError.unrecognized("里面没有可导入的 MCP（每一项要有 command 或 url）") }

        var services: [String: ConfigFile.ServiceEntry] = [:]
        if isOurs, let s = root["services"] as? [String: Any] {
            for (name, raw) in s {
                if let list = (raw as? [String: Any])?["mcps"] as? [String] { services[name] = .init(mcps: list) }
            }
        }
        let env = isOurs ? (root["env"] as? [String: String] ?? [:]) : [:]
        return Imported(mcps: mcps, services: services, env: env)
    }
}

enum ConfigError: LocalizedError {
    case unreadable(String)
    case unrecognized(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let why): "配置文件读不了：\(why)"
        case .unrecognized(let why): "认不出这个文件：\(why)"
        }
    }
}

// MARK: 定义 ↔ 界面

extension ConfigFile.MCPEntry {
    /// 界面上的"类型"由字段推出来，不单独存。
    var kind: MCPKind {
        if url != nil { return .http }
        switch (command.map { ($0 as NSString).lastPathComponent }) {
        case "npx": return .npx
        case "uvx": return .uvx
        default: return .command
        }
    }

    /// 详情页显示的定义行。名字里像密钥的（KEY、TOKEN、SECRET、PASSWORD、AUTH）默认打码。
    var displayFields: [DefinitionField] {
        var out: [DefinitionField] = []
        let args = self.args ?? []
        switch kind {
        case .http:
            out.append(.init(key: "地址", value: url ?? "", monospaced: true))
            for (k, v) in (headers ?? [:]).sorted(by: { $0.key < $1.key }) {
                out.append(.init(key: k, value: v, secret: Self.looksSecret(k), monospaced: true))
            }
            if let ca = x?.caCert { out.append(.init(key: "CA 证书", value: ca, monospaced: true)) }
        case .npx, .uvx:
            // 包名是第一个不以 - 开头的参数；npx 的 -y 不显示
            let pkgIndex = args.firstIndex { !$0.hasPrefix("-") }
            if let i = pkgIndex { out.append(.init(key: "包", value: args[i], monospaced: true)) }
            let rest = args.enumerated().filter { $0.offset != pkgIndex && $0.element != "-y" }.map(\.element)
            if !rest.isEmpty { out.append(.init(key: "参数", value: rest.joined(separator: " "), monospaced: true)) }
        case .command:
            out.append(.init(key: "命令", value: command ?? "", monospaced: true))
            if !args.isEmpty { out.append(.init(key: "参数", value: args.joined(separator: " "), monospaced: true)) }
        }
        for (k, v) in (env ?? [:]).sorted(by: { $0.key < $1.key }) {
            out.append(.init(key: k, value: v, secret: Self.looksSecret(k), monospaced: true))
        }
        if let notes = x?.notes, !notes.isEmpty { out.append(.init(key: "备注", value: notes)) }
        return out
    }

    static func looksSecret(_ key: String) -> Bool {
        let k = key.uppercased()
        return ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"].contains { k.contains($0) }
    }

    /// 由新增表单的内容生成。
    init(draft d: MCPDraft) {
        let target = d.target.trimmingCharacters(in: .whitespaces)
        let args = d.args.split(whereSeparator: \.isWhitespace).map(String.init)
        let pairs = Self.pairs(d.extra, separator: d.kind == .http ? ":" : "=")
        switch d.kind {
        case .npx: command = "npx"; self.args = ["-y", target] + args
        case .uvx: command = "uvx"; self.args = [target] + args
        case .command: command = target; self.args = args.isEmpty ? nil : args
        case .http: url = target
        }
        if d.kind == .http { headers = pairs.isEmpty ? nil : pairs } else { env = pairs.isEmpty ? nil : pairs }
        x = d.inDefault ? nil : Extra(default: false)
    }

    /// 每行一条 `KEY=VALUE`（或 `名字: 值`）。
    private static func pairs(_ text: String, separator: Character) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let i = line.firstIndex(of: separator) else { continue }
            let key = line[..<i].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            out[key] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}
