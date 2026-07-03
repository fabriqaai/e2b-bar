import AppKit
import Foundation

enum AppDiagnostics {
    static var logURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("e2b.bar.log")
    }

    static func log(_ message: String, component: String, metadata: [String: String] = [:]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let extras = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let line = extras.isEmpty
            ? "\(timestamp) [\(component)] \(sanitize(message))\n"
            : "\(timestamp) [\(component)] \(sanitize(message)) \(extras)\n"

        do {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("e2b.bar diagnostics logging failed: \(error.localizedDescription)")
        }
    }

    static func copyLogPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logURL.path, forType: .string)
    }

    static func openLogFolder() {
        NSWorkspace.shared.open(logURL.deletingLastPathComponent())
    }

    private static func sanitize(_ value: String) -> String {
        var result = value
        let patterns = [
            #"e2b_[A-Za-z0-9]+"#,
            #""envdAccessToken"\s*:\s*"[^"]+""#,
            #""trafficAccessToken"\s*:\s*"[^"]+""#,
            #"X-Access-Token:\s*[A-Za-z0-9._-]+"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        return result
    }
}
