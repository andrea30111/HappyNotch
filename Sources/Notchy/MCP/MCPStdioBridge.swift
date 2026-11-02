import Foundation

/// `HappyNotch --mcp-stdio`: forwards newline-delimited JSON-RPC from stdin to the running app's
/// local HTTP endpoint, so stdio-only MCP clients can connect without a second copy of the data.
enum MCPStdioBridge {
    private struct SettingsEnvelope: Decodable { let settings: AppSettings }

    static func run() -> Never {
        let settings = (try? Data(contentsOf: Store.defaultDataURL))
            .flatMap { try? Store.makeDecoder().decode(SettingsEnvelope.self, from: $0).settings }
        guard let settings, settings.mcpEnabled else {
            log("HappyNotch's AI agent server is turned off. Enable it in HappyNotch › Customize › AI Agents.")
            drainWithErrors(message: "HappyNotch's AI agent server is turned off. Enable it in HappyNotch › Customize › AI Agents.")
        }
        guard let url = URL(string: "http://127.0.0.1:\(settings.mcpPort)/mcp") else { exit(1) }

        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(settings.mcpToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = Data(line.utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var status = 0
            URLSession.shared.dataTask(with: request) { data, response, _ in
                responseData = data
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                semaphore.signal()
            }.resume()
            semaphore.wait()

            if status == 200, let responseData, !responseData.isEmpty {
                write(responseData)
            } else if status != 202 {
                writeError(for: line, message: status == 0
                    ? "HappyNotch isn't running. Open HappyNotch and try again."
                    : "HappyNotch returned HTTP \(status).")
            }
        }
        exit(0)
    }

    private static func drainWithErrors(message: String) -> Never {
        while let line = readLine(strippingNewline: true) {
            writeError(for: line, message: message)
        }
        exit(0)
    }

    private static func writeError(for line: String, message: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = object["id"] else { return }
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]
        if let data = try? JSONSerialization.data(withJSONObject: payload) { write(data) }
    }

    private static func write(_ data: Data) {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
