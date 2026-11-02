import Foundation

struct HTTPRequest {
    enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 4 * 1024 * 1024

    static func parse(_ data: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= maxBodyBytes else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])

        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return .complete(HTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: body))
    }
}

enum HTTPResponse {
    static func make(status: Int, reason: String, body: Data = Data(), contentType: String? = "application/json", extraHeaders: [String: String] = [:]) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if let contentType, !body.isEmpty { head += "Content-Type: \(contentType)\r\n" }
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        for (name, value) in extraHeaders { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    static func error(_ status: Int, _ reason: String, message: String) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
        return make(status: status, reason: reason, body: body)
    }
}
