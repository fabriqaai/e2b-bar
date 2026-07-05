import Foundation

struct SandboxLogArchiveResult: Sendable {
    var sandboxID: String
    var fileURL: URL
    var fetchedCount: Int
    var appendedCount: Int
}

struct SandboxLogArchiver: Sendable {
    var directory: URL

    static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".e2b-bar", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func archive(
        sandbox: E2BSandbox,
        logs: [E2BLogEntry],
        fetchedAt: Date = Date()
    ) throws -> SandboxLogArchiveResult {
        try ensureDirectory()

        let fileURL = directory.appendingPathComponent(Self.fileName(for: sandbox))
        let existingContents = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let existingLines = Set(existingContents
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })

        let lines = logs.reversed().map(\.archiveLine)
        var seen = existingLines
        let newLines = lines.filter { line in
            guard !seen.contains(line) else { return false }
            seen.insert(line)
            return true
        }

        guard !newLines.isEmpty else {
            return SandboxLogArchiveResult(
                sandboxID: sandbox.sandboxID,
                fileURL: fileURL,
                fetchedCount: logs.count,
                appendedCount: 0
            )
        }

        var payload = ""
        if existingContents.isEmpty {
            payload += """
            # e2b.bar archived logs
            # sandbox_id=\(sandbox.sandboxID)
            # sandbox_name=\(Self.oneLine(sandbox.displayName))
            # created_at=\(Self.iso8601String(fetchedAt))

            """
        }
        payload += newLines.joined(separator: "\n")
        payload += "\n"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = payload.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return SandboxLogArchiveResult(
            sandboxID: sandbox.sandboxID,
            fileURL: fileURL,
            fetchedCount: logs.count,
            appendedCount: newLines.count
        )
    }

    private static func fileName(for sandbox: E2BSandbox) -> String {
        let name = sanitizedFileName(sandbox.displayName)
        let shortID = sandbox.sandboxID.count > 12
            ? "\(sandbox.sandboxID.prefix(8))"
            : sandbox.sandboxID
        if name.isEmpty {
            return "\(shortID).log"
        }
        return "\(name)-\(shortID).log"
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return String(collapsed.prefix(80))
    }

    private static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension E2BLogEntry {
    var archiveLine: String {
        [
            self.timestampDescription.map { "[\(Self.oneLine($0))]" },
            self.levelDescription.map { Self.oneLine($0).uppercased() },
            Self.oneLine(self.messageDescription)
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")
    }

    private static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }
}
