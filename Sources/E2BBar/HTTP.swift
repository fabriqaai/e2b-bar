import Foundation

enum HTTP {
    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw HTTPError(statusCode: http.statusCode, body: body)
        }
    }
}

struct HTTPError: LocalizedError {
    var statusCode: Int
    var body: String

    var errorDescription: String? {
        if body.isEmpty {
            return "HTTP \(statusCode)"
        }
        return "HTTP \(statusCode): \(body)"
    }
}
