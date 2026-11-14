import Foundation
import Testing
@testable import MCPStation

@Suite("配置文件")
struct ConfigFileTests {
    @Test("新增表单生成的定义：npx 带 -y、环境变量按行解析、密钥默认打码")
    func draftToEntry() {
        var d = MCPDraft()
        d.name = "fs"; d.kind = .npx; d.target = "@scope/server"; d.args = "--root /tmp"; d.extra = "API_KEY=abc\nMODE = fast"
        let e = ConfigFile.MCPEntry(draft: d)
        #expect(e.command == "npx")
        #expect(e.args == ["-y", "@scope/server", "--root", "/tmp"])
        #expect(e.env == ["API_KEY": "abc", "MODE": "fast"])
        #expect(e.displayFields.first { $0.key == "包" }?.value == "@scope/server")
        #expect(e.displayFields.first { $0.key == "API_KEY" }?.secret == true)
    }

    @Test("文件缺字段时用默认值")
    func lenientDecode() throws {
        let c = try JSONDecoder().decode(ConfigFile.self, from: Data("{}".utf8))
        #expect(c.port == 8090 && c.mcps.isEmpty)
    }
}

@Suite("派生数据")
struct DerivedTests {
    private func call(_ id: Int, ago: TimeInterval, error: Bool = false, ms: Int = 100, now: Date) -> CallRecord {
        CallRecord(id: id, time: now.addingTimeInterval(-ago), mcp: "desktop", tool: "read_file", service: "默认",
                   client: "Claude Code", duration: .milliseconds(ms), outcome: error ? .error("x") : .ok)
    }

    @Test("调用统计只算最近一小时，错误和来源正确")
    func callStats() {
        let now = Date.now
        let calls = [
            call(1, ago: 7200, now: now),                 // 两小时前，不计入 1h
            call(2, ago: 30, ms: 200, now: now),
            call(3, ago: 20, error: true, ms: 400, now: now),
            call(4, ago: 10, ms: 600, now: now),
        ]
        let s = CallStats(calls: calls, now: now)
        #expect(s.total1h == 3)
        #expect(s.errors1h == 1)
        #expect(s.errorSources == ["desktop"])
        #expect(s.perMinute == 3)
        #expect(s.avgDuration == .milliseconds(400))
    }

    @Test("客户端配置：容器用 host.docker.internal，默认服务叫 mac")
    func clientCommand() {
        let svc = ServiceSummary(name: "ios", path: "/s/ios/mcp", isDefault: false, members: [], sessions: 0)
        #expect(Format.clientCommand(service: svc, client: .local, port: 8090)
                == "claude mcp add --transport http mac-ios http://127.0.0.1:8090/s/ios/mcp")
        #expect(Format.clientCommand(service: svc, client: .container, port: 8090).contains("host.docker.internal:8090"))
        let def = ServiceSummary(name: "默认", path: "/mcp", isDefault: true, members: [], sessions: 0)
        #expect(Format.clientCommand(service: def, client: .local, port: 8090).contains(" mac http://"))
    }
}
