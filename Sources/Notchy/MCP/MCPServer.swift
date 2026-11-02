import Foundation
import Network

/// Local MCP server using the Streamable HTTP transport (JSON responses, no SSE stream).
/// Binds to 127.0.0.1 only and requires `Authorization: Bearer <token>`.
@MainActor
final class MCPServer: ObservableObject {
    struct Client: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let version: String
        var lastSeen: Date
    }

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var clients: [Client] = []
    @Published private(set) var port: Int = 0

    let toolbox: MCPToolbox
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.notchy.mcp")

    init(toolbox: MCPToolbox) {
        self.toolbox = toolbox
        toolbox.onClientInitialized = { [weak self] name, version in
            self?.recordClient(name: name, version: version)
        }
        toolbox.onRequest = { [weak self] name in
            self?.touchClient(name: name)
        }
    }

    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    func start(port: Int, token: String) {
        stop()
        guard !token.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            lastError = "Invalid port or token."
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            let toolbox = self.toolbox
            let queue = self.queue
            let handler = MCPHTTPHandler(token: token) { body in
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated { toolbox.handle(body) }
                }
            }
            listener.newConnectionHandler = { [handler, queue] connection in
                handler.accept(connection, on: queue)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed(let error):
                        self.isRunning = false
                        self.lastError = "Couldn't start on port \(port): \(error.localizedDescription)"
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            self.port = port
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func recordClient(name: String, version: String) {
        if let index = clients.firstIndex(where: { $0.name == name }) {
            clients[index] = Client(name: name, version: version, lastSeen: Date())
        } else {
            clients.append(Client(name: name, version: version, lastSeen: Date()))
        }
    }

    private func touchClient(name: String?) {
        guard let name, let index = clients.firstIndex(where: { $0.name == name }) else { return }
        clients[index].lastSeen = Date()
    }
}

/// Runs on the listener's queue; only the JSON-RPC handling hops to the main actor.
final class MCPHTTPHandler: @unchecked Sendable {
    private let token: String
    private let handleRPC: (Data) -> Data?

    init(token: String, handleRPC: @escaping (Data) -> Data?) {
        self.token = token
        self.handleRPC = handleRPC
    }

    func accept(_ connection: NWConnection, on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                send(respond(to: request), on: connection)
            case .invalid:
                send(HTTPResponse.error(400, "Bad Request", message: "Malformed request"), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func respond(to request: HTTPRequest) -> Data {
        // Browsers can reach loopback servers; refuse anything that isn't a local origin (DNS rebinding).
        if let origin = request.headers["origin"], !Self.isLocalOrigin(origin) {
            return HTTPResponse.error(403, "Forbidden", message: "Origin not allowed")
        }
        guard request.path == "/mcp" else {
            return HTTPResponse.error(404, "Not Found", message: "Use /mcp")
        }
        guard request.method == "POST" else {
            return HTTPResponse.make(status: 405, reason: "Method Not Allowed", extraHeaders: ["Allow": "POST"])
        }
        guard Self.constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return HTTPResponse.error(401, "Unauthorized", message: "Missing or invalid bearer token")
        }
        guard let body = handleRPC(request.body) else {
            return HTTPResponse.make(status: 202, reason: "Accepted")
        }
        return HTTPResponse.make(status: 200, reason: "OK", body: body)
    }

    private static func isLocalOrigin(_ origin: String) -> Bool {
        guard let host = URL(string: origin)?.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
