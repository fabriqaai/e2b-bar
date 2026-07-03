import AppKit
import SwiftUI

@MainActor
final class SandboxInspectorWindowController: NSObject {
    static let shared = SandboxInspectorWindowController()

    private var controllers: [String: NSWindowController] = [:]

    func show(
        sandboxID: String,
        sandboxName: String,
        apiKeyProvider: @escaping @MainActor () throws -> String,
        destructiveActionsProvider: @escaping @MainActor () -> Bool
    ) {
        if let controller = controllers[sandboxID] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = SandboxInspectorViewModel(
            sandboxID: sandboxID,
            sandboxName: sandboxName,
            apiKeyProvider: apiKeyProvider,
            destructiveActionsProvider: destructiveActionsProvider
        )
        let hostingController = NSHostingController(rootView: SandboxInspectorView(viewModel: viewModel))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sandbox - \(sandboxName)"
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 720, height: 480)
        panel.center()

        let controller = NSWindowController(window: panel)
        controllers[sandboxID] = controller
        controller.showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SandboxInspectorViewModel: ObservableObject {
    @Published private(set) var sandbox: E2BSandbox?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    @Published var filePath = "/home/user"
    @Published private(set) var fileEntries: [FileEntryInfo] = []
    @Published var selectedFilePath: String?
    @Published private(set) var isLoadingFiles = false
    @Published private(set) var fileMessage: String?

    @Published private(set) var processes: [E2BProcessInfo] = []
    @Published var selectedProcessID: Int?
    @Published var command = "pwd && ls -la"
    @Published var commandCWD = "/home/user"
    @Published var commandTag = "e2bbar"
    @Published var processInput = ""
    @Published private(set) var isLoadingProcesses = false
    @Published private(set) var processMessage: String?
    @Published private(set) var processOutput = ""

    @Published var allowInternetAccess = true
    @Published var allowOutText = ""
    @Published var denyOutText = ""
    @Published private(set) var networkMessage: String?
    @Published private(set) var isApplyingNetwork = false

    let sandboxID: String
    let sandboxName: String

    private let apiKeyProvider: @MainActor () throws -> String
    private let destructiveActionsProvider: @MainActor () -> Bool
    private var hasLoaded = false

    init(
        sandboxID: String,
        sandboxName: String,
        apiKeyProvider: @escaping @MainActor () throws -> String,
        destructiveActionsProvider: @escaping @MainActor () -> Bool
    ) {
        self.sandboxID = sandboxID
        self.sandboxName = sandboxName
        self.apiKeyProvider = apiKeyProvider
        self.destructiveActionsProvider = destructiveActionsProvider
    }

    var destructiveActionsEnabled: Bool {
        destructiveActionsProvider()
    }

    var selectedFile: FileEntryInfo? {
        guard let selectedFilePath else { return nil }
        return fileEntries.first { $0.path == selectedFilePath }
    }

    var selectedProcess: E2BProcessInfo? {
        guard let selectedProcessID else { return nil }
        return processes.first { $0.pid == selectedProcessID }
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refreshAll()
    }

    func refreshAll() async {
        await refreshDetail()
        await refreshFiles()
        await refreshProcesses()
    }

    func refreshDetail() async {
        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }

        do {
            let detail = try await self.apiClient().getSandbox(sandboxID: sandboxID)
            sandbox = detail
            syncNetworkFields(from: detail)
        } catch {
            detailError = Self.errorMessage(error)
        }
    }

    func openPort(_ port: Int) {
        NSWorkspace.shared.open(Self.portURL(sandboxID: sandboxID, port: port))
    }

    func copyPort(_ port: Int) {
        copy(Self.portURL(sandboxID: sandboxID, port: port).absoluteString)
    }

    func copySandboxID() {
        copy(sandboxID)
    }

    func refreshFiles() async {
        isLoadingFiles = true
        fileMessage = nil
        defer { isLoadingFiles = false }

        do {
            let path = normalizedFilePath()
            filePath = path
            let entries = try await self.envdClient().listDirectory(path: path)
            fileEntries = entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            if let selectedFilePath, !fileEntries.contains(where: { $0.path == selectedFilePath }) {
                self.selectedFilePath = nil
            }
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func openSelectedDirectory() async {
        guard let selectedFile, selectedFile.isDirectory else { return }
        filePath = selectedFile.path
        await refreshFiles()
    }

    func goUpDirectory() async {
        let trimmed = normalizedFilePath()
        guard trimmed != "/" else { return }
        let url = URL(fileURLWithPath: trimmed)
        filePath = url.deletingLastPathComponent().path
        if filePath.isEmpty { filePath = "/" }
        await refreshFiles()
    }

    func statSelected() async {
        guard let selectedFile else { return }
        do {
            let entry = try await self.envdClient().stat(path: selectedFile.path)
            fileMessage = "\(entry.name): \(MetricFormatting.bytes(entry.size)) \(entry.permissions ?? "")"
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func downloadSelected() async {
        guard let selectedFile, !selectedFile.isDirectory else { return }

        do {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = selectedFile.name
            guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }
            let data = try await self.envdClient().download(path: selectedFile.path)
            try data.write(to: destination)
            fileMessage = "Downloaded \(selectedFile.name)"
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func uploadFile() async {
        do {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            guard openPanel.runModal() == .OK, let localURL = openPanel.url else { return }

            let remoteDirectory = normalizedFilePath()
            let remotePath = remoteDirectory == "/"
                ? "/\(localURL.lastPathComponent)"
                : "\(remoteDirectory)/\(localURL.lastPathComponent)"
            _ = try await self.envdClient().upload(localFile: localURL, remotePath: remotePath)
            fileMessage = "Uploaded \(localURL.lastPathComponent)"
            await refreshFiles()
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func moveSelected() async {
        guard let selectedFile else { return }
        guard let destination = promptText(
            title: "Move \(selectedFile.name)",
            message: "Destination path",
            defaultValue: selectedFile.path
        ) else { return }

        do {
            _ = try await self.envdClient().move(source: selectedFile.path, destination: destination)
            fileMessage = "Moved \(selectedFile.name)"
            await refreshFiles()
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func removeSelected() async {
        guard destructiveActionsEnabled else {
            fileMessage = "Enable destructive actions in Settings first"
            return
        }
        guard let selectedFile else { return }
        guard confirm(title: "Remove \(selectedFile.name)?", message: selectedFile.path) else { return }

        do {
            try await self.envdClient().remove(path: selectedFile.path)
            fileMessage = "Removed \(selectedFile.name)"
            await refreshFiles()
        } catch {
            fileMessage = Self.errorMessage(error)
        }
    }

    func refreshProcesses() async {
        isLoadingProcesses = true
        processMessage = nil
        defer { isLoadingProcesses = false }

        do {
            processes = try await self.envdClient().listProcesses()
                .sorted { $0.pid < $1.pid }
            if let selectedProcessID, !processes.contains(where: { $0.pid == selectedProcessID }) {
                self.selectedProcessID = nil
            }
        } catch {
            processMessage = Self.errorMessage(error)
        }
    }

    func startCommand() async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let result = try await self.envdClient().startShellCommand(
                command: trimmed,
                cwd: normalizedCommandCWD(),
                tag: commandTag
            )
            processOutput = result.output.isEmpty ? "--" : result.output
            if let status = result.status, !status.isEmpty {
                processMessage = status
            } else if let pid = result.pid {
                processMessage = "Started process \(pid)"
            } else {
                processMessage = "Command finished"
            }
            await refreshProcesses()
        } catch {
            processMessage = Self.errorMessage(error)
        }
    }

    func sendInputToSelected() async {
        guard let selectedProcess, !processInput.isEmpty else { return }
        do {
            try await self.envdClient().sendInput(pid: selectedProcess.pid, input: processInput)
            processInput = ""
            processMessage = "Sent input to \(selectedProcess.pid)"
        } catch {
            processMessage = Self.errorMessage(error)
        }
    }

    func closeSelectedStdin() async {
        guard let selectedProcess else { return }
        do {
            try await self.envdClient().closeStdin(pid: selectedProcess.pid)
            processMessage = "Closed stdin for \(selectedProcess.pid)"
        } catch {
            processMessage = Self.errorMessage(error)
        }
    }

    func signalSelected(_ signal: ProcessSignal) async {
        guard destructiveActionsEnabled else {
            processMessage = "Enable destructive actions in Settings first"
            return
        }
        guard let selectedProcess else { return }
        do {
            try await self.envdClient().sendSignal(pid: selectedProcess.pid, signal: signal)
            processMessage = "Sent \(signal.label) to \(selectedProcess.pid)"
            await refreshProcesses()
        } catch {
            processMessage = Self.errorMessage(error)
        }
    }

    func applyNetwork() async {
        guard destructiveActionsEnabled else {
            networkMessage = "Enable destructive actions in Settings first"
            return
        }

        isApplyingNetwork = true
        networkMessage = nil
        defer { isApplyingNetwork = false }

        do {
            let update = SandboxNetworkUpdate(
                allowOut: Self.lines(allowOutText),
                denyOut: Self.lines(denyOutText),
                egressProxy: sandbox?.network?.egressProxy,
                rules: sandbox?.network?.rules,
                allowInternetAccess: allowInternetAccess
            )
            try await self.apiClient().updateSandboxNetwork(sandboxID: sandboxID, update: update)
            networkMessage = "Updated network"
            await refreshDetail()
        } catch {
            networkMessage = Self.errorMessage(error)
        }
    }

    private func apiClient() throws -> E2BClient {
        E2BClient(apiKey: try apiKeyProvider())
    }

    private func envdClient() throws -> EnvdClient {
        EnvdClient(sandboxID: sandboxID, accessToken: sandbox?.envdAccessToken)
    }

    private func syncNetworkFields(from sandbox: E2BSandbox) {
        allowInternetAccess = sandbox.allowInternetAccess ?? true
        allowOutText = (sandbox.network?.allowOut ?? []).joined(separator: "\n")
        denyOutText = (sandbox.network?.denyOut ?? []).joined(separator: "\n")
    }

    private func normalizedFilePath() -> String {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.normalizedSandboxPath(trimmed)
    }

    private func normalizedCommandCWD() -> String {
        Self.normalizedSandboxPath(commandCWD.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func copyDiagnosticLogPath() {
        AppDiagnostics.copyLogPath()
    }

    func openDiagnosticLogFolder() {
        AppDiagnostics.openLogFolder()
    }

    func openNetworkDocs() {
        if let url = URL(string: "https://e2b.dev/docs/api-reference/sandboxes/update-sandbox-network") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func normalizedSandboxPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == "~" {
            return "/home/user"
        }
        if trimmed.hasPrefix("~/") {
            return "/home/user/" + trimmed.dropFirst(2)
        }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return "/home/user/" + trimmed
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func lines(_ value: String) -> [String]? {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    private static func portURL(sandboxID: String, port: Int) -> URL {
        URL(string: "https://\(port)-\(sandboxID).e2b.app")!
    }

    private static func errorMessage(_ error: Error) -> String {
        error.localizedDescription
    }
}

private struct SandboxInspectorView: View {
    @StateObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            self.header
            Divider()
            TabView {
                OverviewTab(viewModel: self.viewModel)
                    .tabItem { Label("Details", systemImage: "info.circle") }
                FilesTab(viewModel: self.viewModel)
                    .tabItem { Label("Files", systemImage: "folder") }
                ProcessesTab(viewModel: self.viewModel)
                    .tabItem { Label("Processes", systemImage: "terminal") }
                NetworkTab(viewModel: self.viewModel)
                    .tabItem { Label("Network", systemImage: "network") }
            }
            .padding(.top, 8)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await self.viewModel.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: self.viewModel.sandbox?.state == .paused ? "pause.circle" : "play.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(self.viewModel.sandbox?.state == .paused ? .orange : .green)
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
                Task { await self.viewModel.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(self.viewModel.isLoadingDetail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct OverviewTab: View {
    @ObservedObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = viewModel.detailError {
                ContentUnavailableView("Could not load sandbox", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let sandbox = viewModel.sandbox {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    row("State", sandbox.state.label)
                    row("Template", sandbox.alias?.isEmpty == false ? sandbox.alias! : sandbox.templateID)
                    row("Started", Self.date(sandbox.startedAt))
                    row("Expires", Self.date(sandbox.endAt))
                    row("Resources", sandbox.resourceSummary)
                    row("envd", sandbox.envdVersion ?? "--")
                    row("Auto-resume", Self.bool(sandbox.lifecycle?.autoResume))
                    row("Internet", Self.bool(sandbox.allowInternetAccess))
                    row("Public traffic", Self.bool(sandbox.network?.allowPublicTraffic))
                    row("Volumes", sandbox.volumeMounts.isEmpty ? "--" : sandbox.volumeMounts.map { "\($0.name):\($0.path)" }.joined(separator: ", "))
                    GridRow {
                        Text("Metadata")
                            .foregroundStyle(.secondary)
                        MetadataBlock(metadata: sandbox.metadata)
                    }
                }
                .font(.callout)

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Port URLs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Open or copy common sandbox web-server URLs, built as https://{port}-\(viewModel.sandboxID).e2b.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                    Button("Copy ID") {
                        viewModel.copySandboxID()
                    }
                    ForEach([3000, 8000, 8080], id: \.self) { port in
                        Button {
                            viewModel.openPort(port)
                        } label: {
                            Text(verbatim: "Open \(port)")
                        }
                        Button {
                            viewModel.copyPort(port)
                        } label: {
                            Text(verbatim: "Copy \(port) URL")
                        }
                    }
                    }
                }
            } else {
                ProgressView("Loading sandbox...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer()
        }
        .padding(18)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "--"
    }

    private static func bool(_ value: Bool?) -> String {
        guard let value else { return "--" }
        return value ? "Yes" : "No"
    }
}

private struct MetadataBlock: View {
    let metadata: [String: JSONValue]

    var body: some View {
        if metadata.isEmpty {
            Text("--")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(metadata.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(key)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(metadata[key]?.shortDescription ?? "")
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct FilesTab: View {
    @ObservedObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Path", text: self.$viewModel.filePath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await self.viewModel.refreshFiles() }
                        }
                    Button("Home") {
                        self.viewModel.filePath = "/home/user"
                        Task { await self.viewModel.refreshFiles() }
                    }
                    Button("Workspace") {
                        self.viewModel.filePath = "/workspace"
                        Task { await self.viewModel.refreshFiles() }
                    }
                    Button {
                        Task { await self.viewModel.goUpDirectory() }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    Button {
                        Task { await self.viewModel.refreshFiles() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(self.viewModel.isLoadingFiles)
                }
                Text("Browse sandbox files. Relative paths resolve under /home/user; try /workspace for mounted project data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = self.viewModel.fileMessage {
                InspectorMessageRow(message: message, viewModel: self.viewModel)
            }

            ZStack {
                List(selection: self.$viewModel.selectedFilePath) {
                    ForEach(self.viewModel.fileEntries) { entry in
                        FileEntryRow(entry: entry)
                            .tag(entry.path)
                            .onTapGesture(count: 2) {
                                Task { await self.viewModel.openSelectedDirectory() }
                            }
                    }
                }
                .listStyle(.inset)

                if self.viewModel.isLoadingFiles {
                    ProgressView("Loading files...")
                } else if self.viewModel.fileEntries.isEmpty {
                    ContentUnavailableView("No files shown", systemImage: "folder", description: Text("Refresh this path or try /home/user or /workspace."))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Open Folder") {
                    Task { await self.viewModel.openSelectedDirectory() }
                }
                .disabled(self.viewModel.selectedFile?.isDirectory != true)
                Button("Get Info") {
                    Task { await self.viewModel.statSelected() }
                }
                .disabled(self.viewModel.selectedFile == nil)
                Button("Download File") {
                    Task { await self.viewModel.downloadSelected() }
                }
                .disabled(self.viewModel.selectedFile == nil || self.viewModel.selectedFile?.isDirectory == true)
                Button("Upload Here") {
                    Task { await self.viewModel.uploadFile() }
                }
                Button("Move") {
                    Task { await self.viewModel.moveSelected() }
                }
                .disabled(self.viewModel.selectedFile == nil)
                Button("Remove") {
                    Task { await self.viewModel.removeSelected() }
                }
                .disabled(self.viewModel.selectedFile == nil || !self.viewModel.destructiveActionsEnabled)
                Spacer()
            }
        }
        .padding(14)
    }
}

private struct InspectorMessageRow: View {
    let message: String
    @ObservedObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Copy Log Path") {
                self.viewModel.copyDiagnosticLogPath()
            }
            Button("Open Logs") {
                self.viewModel.openDiagnosticLogFolder()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FileEntryRow: View {
    let entry: FileEntryInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? entry.path : entry.name)
                    .lineLimit(1)
                Text("\(entry.path)  \(MetricFormatting.bytes(entry.size))  \(entry.permissions ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProcessesTab: View {
    @ObservedObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Command", text: self.$viewModel.command)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await self.viewModel.startCommand() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
            }
            HStack {
                TextField("Working directory", text: self.$viewModel.commandCWD)
                    .textFieldStyle(.roundedBorder)
                TextField("Tag", text: self.$viewModel.commandTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button {
                    self.viewModel.commandCWD = "/home/user"
                } label: {
                    Text("Home")
                }
                Button {
                    self.viewModel.commandCWD = "/workspace"
                } label: {
                    Text("Workspace")
                }
                Button {
                    Task { await self.viewModel.refreshProcesses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(self.viewModel.isLoadingProcesses)
            }

            Text("Run a command through envd and view current sandbox processes. Long-running interactive terminal sessions still belong in your shell; this panel is for quick checks and one-off commands.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let message = self.viewModel.processMessage {
                InspectorMessageRow(message: message, viewModel: self.viewModel)
            }

            HSplitView {
                List(selection: self.$viewModel.selectedProcessID) {
                    ForEach(self.viewModel.processes) { process in
                        ProcessRow(process: process)
                            .tag(process.pid)
                    }
                }
                .frame(minWidth: 300)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(self.viewModel.processOutput.isEmpty ? "--" : self.viewModel.processOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .frame(minWidth: 300)
            }

            HStack {
                TextField("Input", text: self.$viewModel.processInput)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    Task { await self.viewModel.sendInputToSelected() }
                }
                .disabled(self.viewModel.selectedProcess == nil || self.viewModel.processInput.isEmpty)
                Button("Close stdin") {
                    Task { await self.viewModel.closeSelectedStdin() }
                }
                .disabled(self.viewModel.selectedProcess == nil)
                Button("SIGTERM") {
                    Task { await self.viewModel.signalSelected(.terminate) }
                }
                .disabled(self.viewModel.selectedProcess == nil || !self.viewModel.destructiveActionsEnabled)
                Button("SIGKILL") {
                    Task { await self.viewModel.signalSelected(.kill) }
                }
                .disabled(self.viewModel.selectedProcess == nil || !self.viewModel.destructiveActionsEnabled)
            }
        }
        .padding(14)
    }
}

private struct ProcessRow: View {
    let process: E2BProcessInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(process.pid)")
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                Text(process.config.cmd)
                    .lineLimit(1)
                Spacer()
                if let tag = process.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text((process.config.args + [process.config.cwd ?? ""]).filter { !$0.isEmpty }.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

private struct NetworkTab: View {
    @ObservedObject var viewModel: SandboxInspectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network controls update outbound access for this running sandbox. Applying changes replaces the current egress rules; leaving a list empty clears that list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Toggle("Allow internet access", isOn: self.$viewModel.allowInternetAccess)
                LabeledContent("Public traffic", value: self.viewModel.sandbox?.network?.allowPublicTraffic == true ? "Yes" : "No")
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow egress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: self.$viewModel.allowOutText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 180)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("Examples: api.openai.com, *.github.com, 8.8.8.8/32")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deny egress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: self.$viewModel.denyOutText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 180)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("Examples: 0.0.0.0/0, 10.0.0.0/8, 8.8.8.8. E2B does not support domains in deny rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Apply Network") {
                    Task { await self.viewModel.applyNetwork() }
                }
                .disabled(!self.viewModel.destructiveActionsEnabled || self.viewModel.isApplyingNetwork)
                Button("Refresh") {
                    Task { await self.viewModel.refreshDetail() }
                }
                Button("Open E2B Network Docs") {
                    self.viewModel.openNetworkDocs()
                }
                if let message = self.viewModel.networkMessage {
                    InspectorMessageRow(message: message, viewModel: self.viewModel)
                }
            }
            Spacer()
        }
        .padding(18)
    }
}
