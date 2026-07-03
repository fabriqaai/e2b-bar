import Foundation

struct EnvdClient {
    var sandboxID: String
    var accessToken: String?
    var envdPort = 49983
    var username = "user"
    var session: URLSession = .shared

    private var baseURL: URL {
        URL(string: "https://\(envdPort)-\(sandboxID).e2b.app")!
    }

    func listDirectory(path: String, depth: Int = 1) async throws -> [FileEntryInfo] {
        let data = try await self.sendJSON(
            path: "filesystem.Filesystem/ListDir",
            body: ListDirectoryRequest(path: path, depth: max(depth, 1))
        )
        return try JSONDecoder().decode(FileListResponse.self, from: data).entries
    }

    func stat(path: String) async throws -> FileEntryInfo {
        let data = try await self.sendJSON(
            path: "filesystem.Filesystem/Stat",
            body: ["path": path]
        )
        return try JSONDecoder().decode(FileStatResponse.self, from: data).entry
    }

    func move(source: String, destination: String) async throws -> FileEntryInfo {
        let data = try await self.sendJSON(
            path: "filesystem.Filesystem/Move",
            body: ["source": source, "destination": destination]
        )
        return try JSONDecoder().decode(FileMoveResponse.self, from: data).entry
    }

    func remove(path: String) async throws {
        _ = try await self.sendJSON(
            path: "filesystem.Filesystem/Remove",
            body: ["path": path]
        )
    }

    func download(path: String) async throws -> Data {
        var components = URLComponents(url: self.baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw E2BClientError.invalidURL }

        var request = self.baseRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        return data
    }

    func upload(localFile: URL, remotePath: String) async throws -> [FileEntryInfo] {
        let boundary = "E2BBarBoundary\(UUID().uuidString)"
        var components = URLComponents(url: self.baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: remotePath)]
        guard let url = components.url else { throw E2BClientError.invalidURL }

        let fileData = try Data(contentsOf: localFile)
        var body = Data()
        let filename = localFile.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        var request = self.baseRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        return try JSONDecoder().decode(FileUploadResponse.self, from: data).files
    }

    func listProcesses() async throws -> [E2BProcessInfo] {
        let data = try await self.sendJSON(
            path: "process.Process/List",
            body: EmptyRequest()
        )
        return try JSONDecoder().decode(E2BProcessListResponse.self, from: data).processes
    }

    func startShellCommand(command: String, cwd: String?, tag: String?) async throws -> String {
        let config = E2BProcessConfig(
            cmd: "/bin/sh",
            args: ["-lc", command],
            envs: nil,
            cwd: cwd?.isEmpty == false ? cwd : nil
        )
        let body = ProcessStartRequest(
            process: config,
            pty: ProcessPTY(size: ProcessPTYSize(cols: 100, rows: 28)),
            tag: tag?.isEmpty == false ? tag : nil,
            stdin: true
        )
        let data = try await self.sendJSON(
            path: "process.Process/Start",
            body: body,
            contentType: "application/connect+json"
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    func sendSignal(pid: Int, signal: ProcessSignal) async throws {
        _ = try await self.sendJSON(
            path: "process.Process/SendSignal",
            body: ProcessSignalRequest(process: ProcessPID(pid: pid), signal: signal.rawValue)
        )
    }

    func sendInput(pid: Int, input: String) async throws {
        let encoded = Data(input.utf8).base64EncodedString()
        _ = try await self.sendJSON(
            path: "process.Process/SendInput",
            body: ProcessInputRequest(process: ProcessPID(pid: pid), input: ProcessInput(pty: encoded))
        )
    }

    func closeStdin(pid: Int) async throws {
        _ = try await self.sendJSON(
            path: "process.Process/CloseStdin",
            body: ["process": ["pid": pid]]
        )
    }

    private func sendJSON<T: Encodable>(
        path: String,
        body: T,
        contentType: String = "application/json"
    ) async throws -> Data {
        let url = self.baseURL.appendingPathComponent(path)
        var request = self.baseRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        return data
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(sandboxID, forHTTPHeaderField: "E2b-Sandbox-Id")
        request.setValue("\(envdPort)", forHTTPHeaderField: "E2b-Sandbox-Port")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("30000", forHTTPHeaderField: "Connect-Timeout-Ms")
        request.setValue("Basic \(Self.basicUsername(username))", forHTTPHeaderField: "Authorization")
        if let accessToken, !accessToken.isEmpty {
            request.setValue(accessToken, forHTTPHeaderField: "X-Access-Token")
        }
        return request
    }

    private static func basicUsername(_ username: String) -> String {
        Data("\(username):".utf8).base64EncodedString()
    }
}

enum ProcessSignal: String, CaseIterable, Hashable {
    case terminate = "SIGNAL_SIGTERM"
    case kill = "SIGNAL_SIGKILL"

    var label: String {
        switch self {
        case .terminate:
            "SIGTERM"
        case .kill:
            "SIGKILL"
        }
    }
}

private struct EmptyRequest: Encodable {}

private struct ListDirectoryRequest: Encodable {
    var path: String
    var depth: Int
}

private struct ProcessStartRequest: Encodable {
    var process: E2BProcessConfig
    var pty: ProcessPTY?
    var tag: String?
    var stdin: Bool?
}

private struct ProcessPTY: Encodable {
    var size: ProcessPTYSize
}

private struct ProcessPTYSize: Encodable {
    var cols: Int
    var rows: Int
}

private struct ProcessPID: Encodable {
    var pid: Int
}

private struct ProcessSignalRequest: Encodable {
    var process: ProcessPID
    var signal: String
}

private struct ProcessInputRequest: Encodable {
    var process: ProcessPID
    var input: ProcessInput
}

private struct ProcessInput: Encodable {
    var pty: String
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
