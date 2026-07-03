import AppKit
import SwiftUI

@MainActor
final class LogsWindowController: NSObject {
    static let shared = LogsWindowController()

    private var controllers: [String: NSWindowController] = [:]

    func show(
        sandboxID: String,
        sandboxName: String,
        apiKeyProvider: @escaping @MainActor () throws -> String
    ) {
        if let controller = controllers[sandboxID] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = SandboxLogsViewModel(
            sandboxID: sandboxID,
            sandboxName: sandboxName,
            apiKeyProvider: apiKeyProvider
        )
        let hostingController = NSHostingController(rootView: SandboxLogsView(viewModel: viewModel))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Logs - \(sandboxName)"
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 560, height: 360)
        panel.center()

        let controller = NSWindowController(window: panel)
        controllers[sandboxID] = controller
        controller.showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SandboxLogsViewModel: ObservableObject {
    @Published private(set) var logs: [E2BLogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var levelFilter = "All levels"

    let sandboxID: String
    let sandboxName: String

    private let apiKeyProvider: @MainActor () throws -> String
    private var hasLoaded = false

    static let allLevelsLabel = "All levels"

    init(
        sandboxID: String,
        sandboxName: String,
        apiKeyProvider: @escaping @MainActor () throws -> String
    ) {
        self.sandboxID = sandboxID
        self.sandboxName = sandboxName
        self.apiKeyProvider = apiKeyProvider
    }

    var levelOptions: [String] {
        let levels = Set(logs.compactMap { entry in
            entry.levelDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        return [Self.allLevelsLabel] + levels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var filteredLogs: [E2BLogEntry] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return logs.filter { entry in
            let matchesLevel = levelFilter == Self.allLevelsLabel
                || entry.levelDescription?.caseInsensitiveCompare(levelFilter) == .orderedSame
            guard matchesLevel else { return false }

            guard !search.isEmpty else { return true }
            let haystack = [
                entry.timestampDescription,
                entry.levelDescription,
                entry.messageDescription
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let apiKey = try apiKeyProvider()
            let client = E2BClient(apiKey: apiKey)
            logs = try await client.getSandboxLogs(sandboxID: sandboxID, limit: 500)
            if !levelOptions.contains(levelFilter) {
                levelFilter = Self.allLevelsLabel
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyVisibleLogs() {
        let transcript = E2BLogEntry.transcript(sandboxID: sandboxID, logs: filteredLogs)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

private struct SandboxLogsView: View {
    @StateObject var viewModel: SandboxLogsViewModel

    var body: some View {
        VStack(spacing: 0) {
            self.toolbar
            Divider()
            self.filters
            Divider()
            self.content
        }
        .frame(minWidth: 560, minHeight: 360)
        .task {
            await self.viewModel.refreshIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.viewModel.sandboxName)
                    .font(.headline)
                    .lineLimit(1)
                Text(self.viewModel.sandboxID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await self.viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(self.viewModel.isLoading)

            Button {
                self.viewModel.copyVisibleLogs()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(self.viewModel.filteredLogs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search logs", text: self.$viewModel.searchText)
                .textFieldStyle(.roundedBorder)
            Picker("Level", selection: self.$viewModel.levelFilter) {
                ForEach(self.viewModel.levelOptions, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if self.viewModel.isLoading && self.viewModel.logs.isEmpty {
            ProgressView("Loading logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = self.viewModel.errorMessage {
            ContentUnavailableView("Could not load logs", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if self.viewModel.filteredLogs.isEmpty {
            ContentUnavailableView("No logs", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(self.viewModel.filteredLogs.enumerated()), id: \.offset) { _, entry in
                    LogEntryRow(entry: entry)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct LogEntryRow: View {
    let entry: E2BLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let timestamp = entry.timestampDescription {
                    Text(timestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let level = entry.levelDescription, !level.isEmpty {
                    Text(level.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Text(entry.messageDescription)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}
