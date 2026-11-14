import Foundation
import Observation

/// 全局状态仓库：持有 core 推来的状态，提供派生数据和带乐观更新的操作。
///
/// 两套主题都只读写这里，不直接碰 CoreClient。状态按块存放（core / mcps / services / calls），
/// SwiftUI 的 Observation 按属性追踪，所以调用记录刷新不会让 MCP 列表重绘。
@MainActor @Observable
final class AppStore {
    private(set) var core: CoreStatus?
    private(set) var mcps: [MCPServer] = []
    private(set) var namedServices: [NamedService] = []
    private(set) var calls: [CallRecord] = []
    /// 调用统计。只在调用记录变化时重算一次，而不是每次界面读取都算。
    private(set) var stats = CallStats(calls: [], now: .now)
    /// 操作失败时给界面的一句话提示，几秒后自动消失。
    private(set) var toast: Toast?

    /// 正在进行中的操作（按钮显示转圈、防重复点击）。
    private(set) var busy: Set<String> = []

    /// 正在重试的 MCP：从"需要处理"（等待重试 / 配置错误）变成"启动中"的。
    /// 重试出结果前它仍算需要处理，卡片不消失；成功（正常）或别的结果出来再移出。
    /// 否则点"立即重试"会先闪一下"一切正常"，失败了卡片再冒出来（2026-11-14 用户反馈）。
    private(set) var retrying: Set<String> = []

    /// 保留多少条调用记录（够画 7 小时的柱状图）。
    static let maxCalls = 3000

    @ObservationIgnored private let client: any CoreClient
    @ObservationIgnored private var subscription: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(client: any CoreClient) {
        self.client = client
    }


    func start() {
        guard subscription == nil else { return }
        subscription = Task { [weak self, client] in
            for await update in client.updates() {
                self?.apply(update)
            }
        }
    }

    private func apply(_ update: CoreUpdate) {
        switch update {
        case let .snapshot(c, m, s, k):
            core = c; mcps = m; namedServices = s; calls = k
            retrying = retrying.filter { name in m.contains { $0.name == name && $0.state == .starting } }
            stats = CallStats(calls: calls, now: .now)
        case .core(let c):
            core = c
        case .mcp(let m):
            let i = mcps.firstIndex(where: { $0.name == m.name })
            if m.state != .starting {
                retrying.remove(m.name)
            } else if let i, mcps[i].state.needsAttention || retrying.contains(m.name) {
                retrying.insert(m.name)
            }
            if let i { mcps[i] = m } else { mcps.append(m) }
        case .services(let s):
            namedServices = s
        case let .memory(coreBytes, byName):
            core?.memory = coreBytes
            for i in mcps.indices {
                let v = byName[mcps[i].name]
                mcps[i].memory = v
                if let v {
                    mcps[i].memoryHistory.append(v)
                    if mcps[i].memoryHistory.count > 30 { mcps[i].memoryHistory.removeFirst() }
                }
            }
        case .calls(let batch):
            calls.append(contentsOf: batch)
            if calls.count > Self.maxCalls { calls.removeFirst(calls.count - Self.maxCalls) }
            stats = CallStats(calls: calls, now: .now)
        }
    }

    // MARK: 派生数据

    func mcp(_ name: String?) -> MCPServer? {
        guard let name else { return nil }
        return mcps.first { $0.name == name }
    }

    var activeMCPs: [MCPServer] { mcps.filter { $0.state != .stopped } }

    /// 内存合计：后台服务 + 所有 MCP 进程组。
    var totalMemory: Int64 { (core?.memory ?? 0) + mcps.reduce(0) { $0 + ($1.memory ?? 0) } }
    /// 占内存最多的 MCP，降序。
    var memoryRanking: [MCPServer] { mcps.filter { $0.memory != nil }.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) } }
    var healthyCount: Int { mcps.filter(\.state.isHealthy).count }
    /// 需要处理的 MCP，包括正在重试、还没出结果的（见 `retrying`）。
    var attention: [MCPServer] { mcps.filter { $0.state.needsAttention || retrying.contains($0.name) } }

    /// 默认服务在最前，后面是命名服务。默认服务的成员由开关推出。
    var services: [ServiceSummary] {
        let byName = Dictionary(uniqueKeysWithValues: mcps.map { ($0.name, $0) })
        let defaultMembers = mcps.filter(\.inDefault)
        var out = [ServiceSummary(name: "默认", path: "/mcp", isDefault: true,
                                  members: defaultMembers, sessions: core?.defaultSessions ?? 0)]
        out += namedServices.map { s in
            ServiceSummary(name: s.name, path: "/s/\(s.name)/mcp", isDefault: false,
                           members: s.mcpNames.compactMap { byName[$0] }, sessions: s.sessions)
        }
        return out
    }

    func service(_ name: String?) -> ServiceSummary? {
        guard let name else { return nil }
        return services.first { $0.name == name }
    }

    /// 某个 MCP 被哪些服务用到（"默认" 在前）。
    func usedBy(_ m: MCPServer) -> [String] {
        (m.inDefault ? ["默认"] : []) + namedServices.filter { $0.mcpNames.contains(m.name) }.map(\.name)
    }

    // MARK: 操作（乐观更新，失败回滚）

    func setDefault(_ name: String, on: Bool) {
        guard let i = mcps.firstIndex(where: { $0.name == name }), mcps[i].inDefault != on else { return }
        let confirmed = mcps[i].inDefault
        mcps[i].inDefault = on
        sync("default:\(name)", desired: on, confirmed: confirmed) { [client] v in
            try await client.setDefault(mcp: name, on: v)
        } revert: { store, v in
            if let j = store.mcps.firstIndex(where: { $0.name == name }) { store.mcps[j].inDefault = v }
        }
    }

    func restart(_ name: String) {
        perform("restart:\(name)") { [client] in try await client.restart(mcp: name) }
    }

    func retryNow(_ name: String) {
        perform("retry:\(name)") { [client] in try await client.retryNow(mcp: name) }
    }

    func setMembers(of service: String, to members: [String]) {
        guard let i = namedServices.firstIndex(where: { $0.name == service }) else { return }
        let confirmed = namedServices[i].mcpNames
        let ordered = mcps.map(\.name).filter(members.contains)
        namedServices[i].mcpNames = ordered
        sync("members:\(service)", desired: ordered, confirmed: confirmed) { [client] v in
            try await client.setServiceMembers(service: service, mcps: v)
        } revert: { store, v in
            if let j = store.namedServices.firstIndex(where: { $0.name == service }) { store.namedServices[j].mcpNames = v }
        }
    }

    func toggleMember(_ mcp: String, in service: String) {
        guard let s = namedServices.first(where: { $0.name == service }) else { return }
        let next = s.mcpNames.contains(mcp) ? s.mcpNames.filter { $0 != mcp } : s.mcpNames + [mcp]
        setMembers(of: service, to: next)
    }

    /// 新增 MCP。成功返回 true；失败原因用 toast 提示，表单保持打开方便改。
    func addMCP(_ draft: MCPDraft) async -> Bool {
        await run("add-mcp") { [client] in try await client.addMCP(draft) }
    }

    func createService(_ name: String, members: [String] = []) async -> Bool {
        await run("create-service") { [client] in try await client.createService(name: name, mcps: members) }
    }

    func renameService(_ name: String, to newName: String) async -> Bool {
        await run("rename:\(name)") { [client] in try await client.renameService(name, to: newName) }
    }

    func deleteService(_ name: String) {
        perform("delete:\(name)") { [client] in try await client.deleteService(name) }
    }

    func setPort(_ port: Int) async -> Bool {
        await run("port") { [client] in try await client.setPort(port) }
    }

    func restartCore() {
        perform("core-restart") { [client] in try await client.restartCore() }
    }

    /// 从文件导入配置，合并进当前配置。结果用 toast 告诉用户。
    func importConfig(from url: URL) async {
        busy.insert("import")
        defer { busy.remove("import") }
        do {
            let summary = try await client.importConfig(Data(contentsOf: url))
            showToast(summary)
        } catch {
            showToast(error.localizedDescription, style: .error)
        }
    }

    /// 试调用一个工具。出错（连不上、参数不对）时也返回结果，由界面显示；只有 App 自己出问题才用 toast。
    func callTool(mcp: String, tool: String, argumentsJSON: String) async -> ToolCallResult? {
        busy.insert("call:\(mcp)")
        defer { busy.remove("call:\(mcp)") }
        do {
            return try await client.callTool(mcp: mcp, tool: tool, argumentsJSON: argumentsJSON)
        } catch {
            showToast(error.localizedDescription, style: .error)
            return nil
        }
    }

    /// 把当前配置导出到文件（权限 0600，里面有密钥明文）。
    func exportConfig(to url: URL) async {
        do {
            try ConfigStore.write(try await client.exportConfig(), to: url)
            showToast("已导出到 \(url.lastPathComponent)")
        } catch {
            showToast(error.localizedDescription, style: .error)
        }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    func showToast(_ text: String, style: Toast.Style = .info) {
        toast = Toast(text: text, style: style)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: 内部

    /// 「以最后一次为准」的同步：界面已经乐观更新到 `desired`；请求在途时再次修改只记下新目标，
    /// 在途请求回来后若目标又变了就再发一次。失败时回滚到 core 最后确认过的值。
    ///
    /// 不能用"忙就丢弃"：那样第二次修改只改了界面、没发给 core，两边会对不上。
    @ObservationIgnored private var pendingTargets: [String: any Sendable] = [:]
    @ObservationIgnored private var inflight: Set<String> = []

    private func sync<V: Equatable & Sendable>(
        _ key: String, desired: V, confirmed: V,
        send: @escaping @Sendable (V) async throws -> Void,
        revert: @escaping (AppStore, V) -> Void
    ) {
        pendingTargets[key] = desired
        guard !inflight.contains(key) else { return }
        inflight.insert(key)
        Task { [weak self] in
            var lastConfirmed = confirmed
            while let self, let target = self.pendingTargets[key] as? V {
                do {
                    try await send(target)
                    lastConfirmed = target
                } catch {
                    self.pendingTargets[key] = nil
                    revert(self, lastConfirmed)
                    self.showToast(error.localizedDescription, style: .error)
                    break
                }
                if (self.pendingTargets[key] as? V) == target { self.pendingTargets[key] = nil }
            }
            self?.inflight.remove(key)
        }
    }


    private func perform(_ key: String,
                         _ op: @escaping @Sendable () async throws -> Void,
                         rollback: ((AppStore) -> Void)? = nil) {
        guard !busy.contains(key) else { return }
        busy.insert(key)
        Task { [weak self] in
            do {
                try await op()
            } catch {
                guard let self else { return }
                rollback?(self)
                self.showToast(error.localizedDescription, style: .error)
            }
            self?.busy.remove(key)
        }
    }

    private func run(_ key: String, _ op: @escaping @Sendable () async throws -> Void) async -> Bool {
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await op()
            return true
        } catch {
            showToast(error.localizedDescription, style: .error)
            return false
        }
    }
}

struct Toast: Equatable, Identifiable {
    enum Style { case info, error }
    let id = UUID()
    var text: String
    var style: Style
}

struct ServiceSummary: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var path: String
    var isDefault: Bool
    var members: [MCPServer]
    var sessions: Int

    /// 客户端对 MCP 工具名的长度上限（Claude Code 为 64）。
    static let toolNameLimit = 64

    var toolCount: Int { members.reduce(0) { $0 + $1.toolCount } }
    var healthy: Int { members.filter(\.state.isHealthy).count }
    var instructionsLength: Int { members.reduce(0) { $0 + $1.instructionsLength } }
    var withInstructions: Int { members.filter { $0.instructionsLength > 0 }.count }
    /// 聚合后最长的工具名（客户端看到的是 mcp__<客户端名>__<MCP>__<工具>，这里按 "mac" 估）。
    var longestToolName: Int {
        members.flatMap { m in m.tools.map { "mcp__mac__\(m.name)__\($0.name)".count } }.max() ?? 0
    }
}

struct HourBucket: Hashable {
    var hour: Int
    var byService: [String: Int]
    var errors: Int
    var total: Int { byService.values.reduce(0, +) }
}

/// 调用统计。纯函数，按需从调用记录算出来。
struct CallStats {
    var total1h: Int
    var errors1h: Int
    var perMinute: Int
    var peakPerMinute: Int
    /// 最近 30 分钟每分钟调用数（折线图）。
    var perMinuteSeries: [Int]
    /// 最近 30 分钟每分钟错误数。
    var errorSeries: [Int]
    /// 最近 7 个小时每小时调用数，按服务拆分（柱状图）。
    var hourly: [HourBucket]
    var avgDuration: Duration?
    var p95Duration: Duration?
    var errorSources: [String]

    init(calls: [CallRecord], now: Date) {
        let hourAgo = now.addingTimeInterval(-3600)
        let recent = calls.filter { $0.time >= hourAgo }
        total1h = recent.count
        let errs = recent.filter(\.isError)
        errors1h = errs.count
        errorSources = Array(Set(errs.map(\.mcp))).sorted()
        perMinuteSeries = (0..<30).reversed().map { i in
            let from = now.addingTimeInterval(-Double(i + 1) * 60), to = now.addingTimeInterval(-Double(i) * 60)
            return calls.lazy.filter { $0.time >= from && $0.time < to }.count
        }
        errorSeries = (0..<30).reversed().map { i in
            let from = now.addingTimeInterval(-Double(i + 1) * 60), to = now.addingTimeInterval(-Double(i) * 60)
            return calls.lazy.filter { $0.isError && $0.time >= from && $0.time < to }.count
        }
        perMinute = perMinuteSeries.last ?? 0
        peakPerMinute = perMinuteSeries.max() ?? 0
        let cal = Calendar.current
        let thisHour = cal.component(.hour, from: now)
        let startOfHour = cal.dateInterval(of: .hour, for: now)?.start ?? now
        hourly = (0..<7).reversed().map { back in
            let from = startOfHour.addingTimeInterval(-Double(back) * 3600), to = from.addingTimeInterval(3600)
            var by: [String: Int] = [:]
            var errors = 0
            for c in calls where c.time >= from && c.time < to {
                by[c.service, default: 0] += 1
                if c.isError { errors += 1 }
            }
            return HourBucket(hour: (thisHour - back + 24) % 24, byService: by, errors: errors)
        }
        let durations = recent.compactMap(\.duration).sorted()
        if durations.isEmpty {
            avgDuration = nil; p95Duration = nil
        } else {
            avgDuration = durations.reduce(.zero, +) / durations.count
            p95Duration = durations[min(durations.count - 1, Int(Double(durations.count) * 0.95))]
        }
    }
}
