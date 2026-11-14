import Foundation

/// 端口有没有被别的程序占着：问一下 lsof 谁在监听它。没人监听返回 nil。
/// 内核自己（mcp-core）在听不算占用。
enum PortCheck {
    static func listener(on port: Int) async -> String? {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            // 输出形如 "p20594\ncpython3.1\n"
            var pid = "", name = ""
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                if line.hasPrefix("p"), pid.isEmpty { pid = String(line.dropFirst()) }
                if line.hasPrefix("c"), name.isEmpty { name = String(line.dropFirst()) }
            }
            return pid.isEmpty || name == "mcp-core" ? nil : "\(name.isEmpty ? String(localized: "进程") : name)（pid \(pid)）"
        }.value
    }
}
