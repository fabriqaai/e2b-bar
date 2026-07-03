import Foundation

struct GitHubUpdater {
    private let owner = "fabriqaai"
    private let repository = "e2b-bar"
    private let assetName = "E2BBar.dmg"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdate(currentVersion: String) async throws -> UpdateCheckResult {
        let release = try await self.fetchLatestRelease()
        guard let asset = release.assets.first(where: { $0.name == self.assetName }) else {
            throw GitHubUpdaterError.missingAsset(self.assetName)
        }

        let current = AppVersion(currentVersion)
        let latest = AppVersion(release.versionString)
        let candidate = UpdateCandidate(
            currentVersion: currentVersion,
            release: release,
            asset: asset
        )

        if latest > current {
            return .available(candidate)
        }
        return .upToDate(currentVersion: currentVersion, latestVersion: release.versionString)
    }

    func downloadAndInstall(_ update: UpdateCandidate) async throws -> UpdateInstallResult {
        let dmgURL = try await self.download(asset: update.asset, tagName: update.release.tagName)
        let mountedVolume = try await self.mount(dmgURL: dmgURL)

        do {
            let mountedApp = try self.findMountedApp(in: mountedVolume.mountPoint)
            let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            guard FileManager.default.isWritableFile(atPath: applicationsURL.path) else {
                try await self.detach(mountedVolume)
                return .manual(dmgURL: dmgURL, reason: "/Applications is not writable")
            }

            let destination = applicationsURL.appendingPathComponent("E2BBar.app", isDirectory: true)
            let scriptURL = try self.writeInstallerScript()
            try self.launchInstallerScript(
                scriptURL: scriptURL,
                currentProcessID: ProcessInfo.processInfo.processIdentifier,
                sourceApp: mountedApp,
                destinationApp: destination,
                mountPoint: mountedVolume.mountPoint
            )
            return .scheduledRelaunch(version: update.release.versionString)
        } catch {
            try? await self.detach(mountedVolume)
            throw error
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(self.owner)/\(self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("E2BBar-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.session.data(for: request)
        try HTTP.validate(response: response, data: data)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(asset: GitHubReleaseAsset, tagName: String) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("E2BBar-Updater", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await self.session.download(for: request)
        try HTTP.validate(response: response, data: Data())

        let updatesDirectory = try self.updatesDirectory()
        let safeTag = tagName.replacingOccurrences(of: "/", with: "-")
        let destination = updatesDirectory.appendingPathComponent("E2BBar-\(safeTag).dmg")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func mount(dmgURL: URL) async throws -> MountedVolume {
        let result = try await Self.runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"]
        )
        guard result.exitCode == 0 else {
            throw GitHubUpdaterError.processFailed("hdiutil attach", result.errorMessage)
        }

        let mountPoint = try Self.parseMountPoint(from: result.stdout)
        return MountedVolume(mountPoint: mountPoint)
    }

    private func detach(_ mountedVolume: MountedVolume) async throws {
        let result = try await Self.runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountedVolume.mountPoint.path]
        )
        guard result.exitCode == 0 else {
            throw GitHubUpdaterError.processFailed("hdiutil detach", result.errorMessage)
        }
    }

    private func findMountedApp(in mountPoint: URL) throws -> URL {
        let directURL = mountPoint.appendingPathComponent("E2BBar.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if let app = contents.first(where: { $0.pathExtension == "app" && $0.lastPathComponent == "E2BBar.app" }) {
            return app
        }
        throw GitHubUpdaterError.missingAppInDMG
    }

    private func writeInstallerScript() throws -> URL {
        let directory = try self.updatesDirectory()
        let scriptURL = directory.appendingPathComponent("install-e2bbar-update.zsh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        LOG="$HOME/Library/Logs/E2BBar-updater.log"
        mkdir -p "$(dirname "$LOG")"
        exec >> "$LOG" 2>&1

        PID="$1"
        SRC="$2"
        DEST="$3"
        MOUNT="$4"

        while /bin/kill -0 "$PID" 2>/dev/null; do
          /bin/sleep 0.2
        done

        /bin/rm -rf "$DEST"
        /usr/bin/ditto "$SRC" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
        /usr/bin/hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
        /usr/bin/open "$DEST"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func launchInstallerScript(
        scriptURL: URL,
        currentProcessID: Int32,
        sourceApp: URL,
        destinationApp: URL,
        mountPoint: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "\(currentProcessID)",
            sourceApp.path,
            destinationApp.path,
            mountPoint.path
        ]
        try process.run()
    }

    private func updatesDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("E2BBar/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func parseMountPoint(from plistData: Data) throws -> URL {
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        guard
            let dictionary = plist as? [String: Any],
            let entities = dictionary["system-entities"] as? [[String: Any]]
        else {
            throw GitHubUpdaterError.invalidMountResponse
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }
        throw GitHubUpdaterError.invalidMountResponse
    }

    private static func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                stderr: errorPipe.fileHandleForReading.readDataToEndOfFile()
            )
        }.value
    }
}

struct UpdateCandidate: Sendable {
    var currentVersion: String
    var release: GitHubRelease
    var asset: GitHubReleaseAsset
}

enum UpdateCheckResult: Sendable {
    case available(UpdateCandidate)
    case upToDate(currentVersion: String, latestVersion: String)
}

enum UpdateInstallResult: Sendable {
    case scheduledRelaunch(version: String)
    case manual(dmgURL: URL, reason: String)
}

struct GitHubRelease: Decodable, Sendable {
    var tagName: String
    var name: String?
    var htmlURL: URL
    var assets: [GitHubReleaseAsset]

    var versionString: String {
        if tagName.lowercased().hasPrefix("v") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable, Sendable {
    var name: String
    var browserDownloadURL: URL
    var size: Int?

    var sizeLabel: String {
        guard let size else { return "unknown size" }
        return MetricFormatting.bytes(Int64(size))
    }

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

private struct MountedVolume: Sendable {
    var mountPoint: URL
}

private struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data

    var errorMessage: String {
        String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct AppVersion: Comparable {
    let rawValue: String
    let components: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .trimmingPrefix("V")
        self.components = normalized
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { character in
                    character.isNumber
                }
                return Int(digits) ?? 0
            }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

enum GitHubUpdaterError: LocalizedError {
    case missingAsset(String)
    case missingAppInDMG
    case invalidMountResponse
    case processFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .missingAsset(let name):
            "Latest GitHub release does not include \(name)"
        case .missingAppInDMG:
            "Downloaded DMG does not contain E2BBar.app"
        case .invalidMountResponse:
            "Could not read the mounted update volume"
        case .processFailed(let command, let message):
            message.isEmpty ? "\(command) failed" : "\(command) failed: \(message)"
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}
