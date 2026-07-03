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
