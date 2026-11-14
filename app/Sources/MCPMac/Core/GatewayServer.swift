import Foundation
import Network

/// 网关的 HTTP 层：在一个端口上收 Streamable HTTP 请求（每个 POST 一条 JSON-RPC），交给 `handler`，原样写回响应。
/// 只做 HTTP/1.1 的收发（含 keep-alive），不懂 MCP；路由和聚合在 LocalCore 里。
final class GatewayServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        /// 键是小写的。
        var headers: [String: String]
        var body: Data
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()

        static func json(_ obj: Any, status: Int = 200, headers: [String: String] = [:]) -> Response {
            var h = headers
            h["Content-Type"] = "application/json"
            return Response(status: status, headers: h, body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
        }
    }

    enum State: Sendable {
        case ready
        case failed(String)
    }

    private let queue = DispatchQueue(label: "mcp-mac.gateway")
    private var listener: NWListener?

    /// 只监听本机回环地址：Docker 容器经 host.docker.internal 访问时由 Docker 转到本机回环，局域网里的别人连不上。
    func start(port: Int, handler: @escaping @Sendable (Request) async -> Response, onState: @escaping @Sendable (State) -> Void) {
        stop()
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { onState(.failed("端口 \(port) 不对")); return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: p)
        let l: NWListener
        do { l = try NWListener(using: params) } catch {
            onState(.failed("监听不了端口 \(port)：\(error.localizedDescription)"))
            return
        }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: onState(.ready)
            case .failed(let e): onState(.failed("端口 \(port) 起不来：\(e.localizedDescription)"))
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.serve(conn, buffer: Data(), handler: handler)
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: HTTP

    private func serve(_ conn: NWConnection, buffer: Data, handler: @escaping @Sendable (Request) async -> Response) {
        if let (req, rest) = Self.parse(buffer) {
            Task {
                let resp = await handler(req)
                conn.send(content: Self.encode(resp), completion: .contentProcessed { [weak self] error in
                    if error != nil { conn.cancel(); return }
                    self?.serve(conn, buffer: rest, handler: handler)
                })
            }
            return
        }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                self?.serve(conn, buffer: buffer + data, handler: handler)
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self?.serve(conn, buffer: buffer, handler: handler)
            }
        }
    }

    /// 缓冲里够一个完整请求就拆出来（请求 + 剩下的字节），不够返回 nil。
    private static func parse(_ buf: Data) -> (Request, Data)? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buf[buf.startIndex..<sep.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard buf.distance(from: bodyStart, to: buf.endIndex) >= length else { return nil }
        let bodyEnd = buf.index(bodyStart, offsetBy: length)
        let path = String(start[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        return (Request(method: String(start[0]), path: path, headers: headers, body: Data(buf[bodyStart..<bodyEnd])),
                Data(buf[bodyEnd...]))
    }

    private static func encode(_ r: Response) -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][r.status] ?? "Status"
        var head = "HTTP/1.1 \(r.status) \(reason)\r\nContent-Length: \(r.body.count)\r\nConnection: keep-alive\r\n"
        for (k, v) in r.headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + r.body
    }
}
