import Foundation
import Testing
@testable import MCPMac

/// 记录收到的 setDefault 调用；可设延迟和失败。
private actor FakeCore: CoreClient {
    var received: [Bool] = []
    var failNext = false
    let delay: Duration

    init(delay: Duration = .milliseconds(80)) { self.delay = delay }

    func setFailNext() { failNext = true }

    nonisolated func updates() -> AsyncStream<CoreUpdate> {
        AsyncStream { c in
            let m = MCPServer(name: "desktop", kind: .npx, definition: [], tools: [ToolInfo(name: "read_file", summary: "")],
                              resourceCount: 0, promptCount: 0, instructionsLength: 0, inDefault: true,
                              state: .ready, pid: 1, startedAt: .now, restarts: 0, stderr: [])
            c.yield(.snapshot(CoreStatus(version: "t", port: 8090, state: .running(pid: 1, since: .now), defaultSessions: 0),
                              [m], [], []))
        }
    }

    func setDefault(mcp: String, on: Bool) async throws {
        try await Task.sleep(for: delay)
        if failNext { failNext = false; throw CoreError.notRunning }
        received.append(on)
    }
    func restart(mcp: String) async throws {}
    func retryNow(mcp: String) async throws {}
    func addMCP(_ draft: MCPDraft) async throws {}
    func createService(name: String, mcps: [String]) async throws {}
    func setServiceMembers(service: String, mcps: [String]) async throws {}
    func renameService(_ name: String, to newName: String) async throws {}
    func deleteService(_ name: String) async throws {}
    func restartCore() async throws {}
    func setPort(_ port: Int) async throws {}
    func importConfig(_ data: Data) async throws -> String { "" }
    func exportConfig() async throws -> Data { Data() }
    func callTool(mcp: String, tool: String, argumentsJSON: String) async throws -> ToolCallResult {
        ToolCallResult(isError: false, text: "", duration: .zero)
    }
}

@MainActor
@Suite("AppStore 乐观更新")
struct AppStoreSyncTests {
    private func ready(_ core: FakeCore) async -> AppStore {
        let store = AppStore(client: core)
        store.start()
        for _ in 0..<50 where store.mcps.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return store
    }

    @Test("请求在途时连拨两次：core 最终收到最后一次的值")
    func latestWins() async throws {
        let core = FakeCore()
        let store = await ready(core)

        store.setDefault("desktop", on: false)   // 发出 false
        store.setDefault("desktop", on: true)    // 在途中又改回 true
        #expect(store.mcp("desktop")?.inDefault == true)

        try await Task.sleep(for: .milliseconds(400))
        #expect(await core.received.last == true, "最后一次修改必须送到 core")
        #expect(store.mcp("desktop")?.inDefault == true)
    }

    @Test("失败时回滚到 core 最后确认过的值，并提示")
    func rollbackOnFailure() async throws {
        let core = FakeCore()
        let store = await ready(core)
        await core.setFailNext()

        store.setDefault("desktop", on: false)
        #expect(store.mcp("desktop")?.inDefault == false)   // 乐观更新
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.mcp("desktop")?.inDefault == true)    // 回滚
        #expect(store.toast?.style == .error)
    }
}
