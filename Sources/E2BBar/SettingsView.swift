import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = SettingsTab.general
    @State private var contentWidth = SettingsTab.general.preferredWidth
    @State private var contentHeight = SettingsTab.general.preferredHeight

    var body: some View {
        TabView(selection: self.$selectedTab) {
            GeneralSettingsView(model: self.model)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            AccountSettingsView(model: self.model)
                .tabItem { Label("Account", systemImage: "key") }
                .tag(SettingsTab.account)
            UsageSettingsView(model: self.model)
                .tabItem { Label("Usage", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(SettingsTab.usage)
            AboutSettingsView(model: self.model)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: self.contentWidth, height: self.contentHeight)
        .onAppear {
            self.updateLayout(for: self.selectedTab, animate: false)
        }
        .onChange(of: self.selectedTab) { _, tab in
            self.updateLayout(for: tab, animate: true)
        }
    }

    private func updateLayout(for tab: SettingsTab, animate: Bool) {
        let change = {
            self.contentWidth = tab.preferredWidth
            self.contentHeight = tab.preferredHeight
        }
        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { change() }
        } else {
            change()
        }
        Self.resizeSettingsWindow(width: tab.preferredWidth, height: tab.preferredHeight, animate: animate)
    }

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
    private static let knownTabTitles = Set(SettingsTab.allCases.map(\.title))

    private static func resizeSettingsWindow(width: CGFloat, height: CGFloat, animate: Bool) {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == self.settingsWindowIdentifier || self.knownTabTitles.contains($0.title)
        }) else { return }

        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        guard toolbarHeight > 0 else { return }

        let newSize = NSSize(width: width, height: height + toolbarHeight)
        var frame = window.frame
        frame.origin.y += frame.size.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: animate)
    }
}

enum SettingsTab: CaseIterable, Hashable {
    case general
    case account
    case usage
    case about

    static let defaultWidth: CGFloat = 560
    static let aboutWidth: CGFloat = 640
    static let windowHeight: CGFloat = 470
    static let usageHeight: CGFloat = 570

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .usage: "Usage"
        case .about: "About"
        }
    }

    var preferredWidth: CGFloat {
        switch self {
        case .about, .usage:
            Self.aboutWidth
        case .general, .account:
            Self.defaultWidth
        }
    }

    var preferredHeight: CGFloat {
        switch self {
        case .usage:
            Self.usageHeight
        case .general, .account, .about:
            Self.windowHeight
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Sandboxes") {
                Picker("State", selection: self.$model.stateFilter) {
                    ForEach(SandboxStateFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                TextField("Metadata filter", text: self.$model.metadataFilter)
                Picker("Refresh interval", selection: self.$model.pollInterval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                    Text("5 minutes").tag(TimeInterval(300))
                }
            }

            Section("Startup") {
                Toggle("Launch e2b.bar at login", isOn: self.$model.launchAtLoginEnabled)
            }

            Section("Notifications") {
                Picker("Expiration alert", selection: self.$model.expirationAlertThreshold) {
                    ForEach(ExpirationAlertThreshold.allCases, id: \.self) { threshold in
                        Text(threshold.label).tag(threshold)
                    }
                }
            }

            Section("Lifecycle Events") {
                Toggle("Use lifecycle events between full refreshes", isOn: self.$model.lifecycleEventsEnabled)
                if let event = self.model.lastLifecycleEvent {
                    Text(event.displaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = self.model.lifecycleEventsError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Menu-open refreshes still use the full sandbox list; scheduled ticks check lifecycle events first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Safety") {
                Toggle("Show destructive actions", isOn: self.$model.destructiveActionsEnabled)
                Text("Pause and Delete are hidden from sandbox menus until this is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                HStack {
                    Button("Refresh Now") {
                        Task { await self.model.refresh() }
                    }
                    .disabled(self.model.isRefreshing)
                    Button("Open Usage Dashboard") {
                        self.model.openUsageDashboard()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct AccountSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("E2B Account") {
                LabeledContent("Status", value: self.model.credentialState.label)
                SecureField("API key", text: self.$apiKey)
                HStack {
                    Button("Save API Key") {
                        self.model.saveAPIKey(self.apiKey)
                        self.apiKey = ""
                    }
                    .disabled(self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear Saved Key") {
                        self.model.clearSavedAPIKey()
                    }
                    Button("Refresh Now") {
                        Task { await self.model.refresh() }
                    }
                    .disabled(self.model.isRefreshing)
                }
            }

            Section("Open") {
                HStack {
                    Button("E2B Dashboard") {
                        self.model.openDashboard()
                    }
                    Button("E2B Docs") {
                        self.model.openDocs()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct UsageSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Team") {
                TextField("Team ID", text: self.$model.teamID)
                TextField("Dashboard slug or usage URL", text: self.$model.usageDashboardPath)
                Text("Use the account/team part from your dashboard URL, for example cengiz from e2b.dev/dashboard/cengiz/usage. E2B's API key endpoints do not expose this dashboard slug.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Refresh Usage") {
                        Task { await self.model.refreshTeamUsage() }
                    }
                    .disabled(self.model.isRefreshingTeamUsage || self.model.teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Open Dashboard") {
                        self.model.openDashboard()
                    }
                }
            }

            Section("Last 24 Hours") {
                if let usage = self.model.teamUsage {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Latest concurrent")
                            Text("\(usage.latest?.concurrentSandboxes ?? 0)")
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Latest start rate")
                            Text(Self.rate(usage.latest?.sandboxStartRate))
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Max concurrent")
                            Text(Self.number(usage.maxConcurrent?.value))
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Max start rate")
                            Text(Self.rate(usage.maxStartRate?.value))
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Samples")
                            Text("\(usage.samples.count)")
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Window")
                            Text("\(usage.windowStart.formatted(date: .omitted, time: .shortened)) - \(usage.windowEnd.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .font(.callout)
                } else if let error = self.model.teamUsageError {
                    Text(error)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No usage loaded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value)
    }

    private static func rate(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(String(format: "%.2f", value * 60))/min"
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Self.appIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("e2b.bar")
                        .font(.title2.weight(.semibold))
                    Text("Your E2B sandboxes, one glance away.")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()

            Text("e2b.bar is a tiny macOS menu bar app for people who keep remote E2B environments running while they build, test, or hand work between agents. It shows running and paused sandboxes, resource totals, expiration timing, metadata, and quick links without opening the dashboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Version")
                    Text(Self.version)
                }
                GridRow {
                    Text("Website")
                    Text("e2b.bar")
                }
                GridRow {
                    Text("Source")
                    Text("github.com/fabriqaai/e2b-bar")
                }
                GridRow {
                    Text("API")
                    Text("GET /v2/sandboxes")
                }
                GridRow {
                    Text("Storage")
                    Text("API key is stored in macOS Keychain")
                }
            }
            .font(.callout)

            HStack {
                Button("Website") {
                    self.model.openWebsite()
                }
                Button("GitHub") {
                    self.model.openGitHub()
                }
                Button("Releases") {
                    self.model.openReleases()
                }
                Button(self.model.isCheckingForUpdates ? "Checking..." : "Check for Updates") {
                    Task { await self.model.checkForUpdates() }
                }
                .disabled(self.model.isCheckingForUpdates)
                Button("E2B Docs") {
                    self.model.openDocs()
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private static var appIcon: some View {
        if let image = NSImage(named: "E2BBarIcon") {
            Image(nsImage: image)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "shippingbox")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
        }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
