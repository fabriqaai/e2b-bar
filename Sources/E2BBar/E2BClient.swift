import Foundation

struct E2BClient {
    var apiKey: String
    var baseURL = URL(string: "https://api.e2b.app")!
    var session: URLSession = .shared

    func listSandboxes(
        states: [E2BSandboxState],
        metadata: String?,
        limit: Int = 100
    ) async throws -> E2BListPage {
        var allSandboxes: [E2BSandbox] = []
        var mergedTotals = E2BListTotals()
        var nextToken: String?
        var pages = 0

        repeat {
            let page = try await self.fetchPage(
                states: states,
                metadata: metadata,
                nextToken: nextToken,
                limit: min(max(limit, 1), 100)
            )
            allSandboxes.append(contentsOf: page.sandboxes)
            mergedTotals.runningHeader = page.totals.runningHeader ?? mergedTotals.runningHeader
            mergedTotals.pausedHeader = page.totals.pausedHeader ?? mergedTotals.pausedHeader
            nextToken = page.nextToken
            pages += 1
        } while nextToken?.isEmpty == false && pages < 20

        mergedTotals.fetched = allSandboxes.count
        return E2BListPage(sandboxes: allSandboxes, totals: mergedTotals, nextToken: nextToken)
    }

    func getSandboxMetrics(
        sandboxID: String,
        start: Int64,
        end: Int64
    ) async throws -> [E2BMetric] {
        let queryItems = [
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "end", value: "\(end)")
        ]
        let data = try await self.request(
            path: "sandboxes/\(sandboxID)/metrics",
            method: "GET",
            queryItems: queryItems
        )
        return try JSONDecoder().decode([E2BMetric].self, from: data)
    }

    func getSandboxLogs(
        sandboxID: String,
        limit: Int = 100,
        direction: E2BLogDirection = .backward
    ) async throws -> [E2BLogEntry] {
        let queryItems = [
            URLQueryItem(name: "limit", value: "\(min(max(limit, 0), 1000))"),
            URLQueryItem(name: "direction", value: direction.rawValue)
        ]
        let data = try await self.request(
            path: "v2/sandboxes/\(sandboxID)/logs",
            method: "GET",
            queryItems: queryItems
        )
        return try JSONDecoder().decode(E2BLogResponse.self, from: data).logs
    }

    func refreshSandbox(sandboxID: String, duration: Int) async throws {
        try await self.sendJSON(
            path: "sandboxes/\(sandboxID)/refreshes",
            method: "POST",
            body: ["duration": min(max(duration, 0), 3600)]
        )
    }

    func setSandboxTimeout(sandboxID: String, timeout: Int) async throws {
        try await self.sendJSON(
            path: "sandboxes/\(sandboxID)/timeout",
            method: "POST",
            body: ["timeout": max(timeout, 0)]
        )
    }

    func pauseSandbox(sandboxID: String, memory: Bool = true) async throws {
        try await self.sendJSON(
            path: "sandboxes/\(sandboxID)/pause",
            method: "POST",
            body: ["memory": memory]
        )
    }

    func deleteSandbox(sandboxID: String) async throws {
        _ = try await self.request(
            path: "sandboxes/\(sandboxID)",
            method: "DELETE"
        )
    }

    private func fetchPage(
        states: [E2BSandboxState],
        metadata: String?,
        nextToken: String?,
        limit: Int
    ) async throws -> E2BListPage {
        var components = URLComponents(url: self.baseURL.appendingPathComponent("v2/sandboxes"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        let stateValues = states.filter { $0 != .unknown }.map(\.rawValue)
        if !stateValues.isEmpty {
            queryItems.append(URLQueryItem(name: "state", value: stateValues.joined(separator: ",")))
        }
        if let metadata = metadata?.trimmingCharacters(in: .whitespacesAndNewlines), !metadata.isEmpty {
            queryItems.append(URLQueryItem(name: "metadata", value: metadata))
        }
        if let nextToken, !nextToken.isEmpty {
            queryItems.append(URLQueryItem(name: "nextToken", value: nextToken))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw E2BClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(self.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        let sandboxes = try JSONDecoder().decode([E2BSandbox].self, from: data)

        let http = response as? HTTPURLResponse
        let totals = E2BListTotals(
            fetched: sandboxes.count,
            runningHeader: http?.intHeader("X-Total-Running"),
            pausedHeader: http?.intHeader("X-Total-Paused")
        )
        return E2BListPage(
            sandboxes: sandboxes,
            totals: totals,
            nextToken: http?.value(forHTTPHeaderField: "X-Next-Token")
        )
    }

    @discardableResult
    private func sendJSON<T: Encodable>(
        path: String,
        method: String,
        body: T
    ) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try await self.request(
            path: path,
            method: method,
            body: data,
            contentType: "application/json"
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw E2BClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(self.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        return data
    }
}

struct E2BListPage: Sendable {
    var sandboxes: [E2BSandbox]
    var totals: E2BListTotals
    var nextToken: String?
}

enum E2BClientError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid E2B API URL"
        }
    }
}

private extension HTTPURLResponse {
    func intHeader(_ name: String) -> Int? {
        guard let value = value(forHTTPHeaderField: name) else { return nil }
        return Int(value)
    }
}
