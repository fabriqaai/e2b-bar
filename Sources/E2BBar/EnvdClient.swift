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
        return try self.decode(FileListResponse.self, from: data, endpoint: "filesystem.Filesystem/ListDir").entries
    }

    func stat(path: String) async throws -> FileEntryInfo {
        let data = try await self.sendJSON(
            path: "filesystem.Filesystem/Stat",
            body: ["path": path]
        )
        return try self.decode(FileStatResponse.self, from: data, endpoint: "filesystem.Filesystem/Stat").entry
    }

    func move(source: String, destination: String) async throws -> FileEntryInfo {
        let data = try await self.sendJSON(
            path: "filesystem.Filesystem/Move",
            body: ["source": source, "destination": destination]
        )
        return try self.decode(FileMoveResponse.self, from: data, endpoint: "filesystem.Filesystem/Move").entry
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
        do {
            try HTTP.validate(response: response, data: data)
        } catch {
            self.logFailure(endpoint: "files download", error: error, data: data)
            throw error
        }
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
        do {
            try HTTP.validate(response: response, data: data)
        } catch {
            self.logFailure(endpoint: "files upload", error: error, data: data)
            throw error
        }
        return try self.decode(FileUploadResponse.self, from: data, endpoint: "files upload").files
    }

    func listProcesses() async throws -> [E2BProcessInfo] {
        let data = try await self.sendJSON(
            path: "process.Process/List",
            body: EmptyRequest()
        )
        return try self.decode(E2BProcessListResponse.self, from: data, endpoint: "process.Process/List").processes
    }

    func startShellCommand(command: String, cwd: String?, tag: String?) async throws -> ProcessRunResult {
        let config = E2BProcessConfig(
            cmd: "/bin/bash",
            args: ["-lc", command],
            envs: nil,
            cwd: cwd?.isEmpty == false ? cwd : nil
        )
        let body = ProcessStartRequest(
            process: config,
            pty: ProcessPTY(size: ProcessPTYSize(cols: 100, rows: 28)),
            tag: tag?.isEmpty == false ? tag : nil,
            stdin: false
        )
        let data = try await self.sendConnectStreamingJSON(
            path: "process.Process/Start",
            body: body,
            contentType: "application/connect+json"
        )
        return try ProcessRunResult(connectStreamData: data)
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
        do {
            try HTTP.validate(response: response, data: data)
        } catch {
            self.logFailure(endpoint: path, error: error, data: data)
            throw error
        }
        return data
    }

    private func sendConnectStreamingJSON<T: Encodable>(
        path: String,
        body: T,
        contentType: String
    ) async throws -> Data {
        let url = self.baseURL.appendingPathComponent(path)
        var request = self.baseRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentType, forHTTPHeaderField: "Accept")
        request.httpBody = try ConnectJSONFraming.encode(JSONEncoder().encode(body))

        let (data, response) = try await self.session.data(for: request)
        do {
            try HTTP.validate(response: response, data: data)
        } catch {
            self.logFailure(endpoint: path, error: error, data: data)
            throw error
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            self.logFailure(endpoint: endpoint, error: error, data: data)
            throw EnvdClientError.decoding(endpoint: endpoint)
        }
    }

    private func logFailure(endpoint: String, error: Error, data: Data) {
        AppDiagnostics.log(
            "envd request failed",
            component: "envd",
            metadata: [
                "endpoint": endpoint,
                "sandbox": Self.shortID(sandboxID),
                "error": error.localizedDescription,
                "body": String(data: data.prefix(800), encoding: .utf8) ?? "<binary \(data.count) bytes>"
            ]
        )
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

    private static func shortID(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(6))...\(id.suffix(4))"
    }
}

enum EnvdClientError: LocalizedError {
    case decoding(endpoint: String)
    case connectFrame(String)

    var errorDescription: String? {
        switch self {
        case .decoding(let endpoint):
            "Could not read envd response from \(endpoint). Diagnostic details were written to \(AppDiagnostics.logURL.path)."
        case .connectFrame(let message):
            "Could not read envd stream: \(message). Diagnostic details were written to \(AppDiagnostics.logURL.path)."
        }
    }
}

struct ProcessRunResult: Hashable, Sendable {
    var pid: Int?
    var output: String
    var status: String?
    var exited: Bool?

    init(connectStreamData data: Data) throws {
        var pid: Int?
        var output = ""
        var status: String?
        var exited: Bool?

        do {
            let frames = try ConnectJSONFraming.decode(data)
            for frame in frames {
                guard !frame.message.isEmpty else { continue }
                let response = try JSONDecoder().decode(ProcessStartStreamResponse.self, from: frame.message)
                if let start = response.event?.start {
                    pid = start.pid
                }
                if let pty = response.event?.data?.pty,
                   let decoded = Data(base64Encoded: pty),
                   let text = String(data: decoded, encoding: .utf8) {
                    output += text
                }
                if let end = response.event?.end {
                    status = end.status
                    exited = end.exited
                }
            }
        } catch {
            AppDiagnostics.log(
                "connect stream decode failed",
                component: "envd",
                metadata: [
                    "error": error.localizedDescription,
                    "bytes": "\(data.count)"
                ]
            )
            throw error
        }

        self.pid = pid
        self.output = output
        self.status = status
        self.exited = exited
    }
}

private enum ConnectJSONFraming {
    static func encode(_ message: Data) -> Data {
        var data = Data([0])
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(message)
        return data
    }

    static func decode(_ data: Data) throws -> [(flags: UInt8, message: Data)] {
        var frames: [(UInt8, Data)] = []
        var index = 0

        while index < data.count {
            guard index + 5 <= data.count else {
                throw EnvdClientError.connectFrame("truncated frame header")
            }

            let flags = data[index]
            index += 1
            let length = data[index..<(index + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            index += 4

            guard index + Int(length) <= data.count else {
                throw EnvdClientError.connectFrame("truncated frame body")
            }

            frames.append((flags, Data(data[index..<(index + Int(length))])))
            index += Int(length)
        }

        return frames
    }
}

private struct ProcessStartStreamResponse: Decodable {
    var event: ProcessStartEvent?
}

private struct ProcessStartEvent: Decodable {
    var start: ProcessStartEventStart?
    var data: ProcessStartEventData?
    var end: ProcessStartEventEnd?
}

private struct ProcessStartEventStart: Decodable {
    var pid: Int
}

private struct ProcessStartEventData: Decodable {
    var pty: String?
}

private struct ProcessStartEventEnd: Decodable {
    var exited: Bool?
    var status: String?
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
