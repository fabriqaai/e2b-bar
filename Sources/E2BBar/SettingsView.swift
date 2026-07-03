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
            AboutSettingsView()
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
    case about

    static let defaultWidth: CGFloat = 520
    static let windowHeight: CGFloat = 360

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .about: "About"
        }
    }

    var preferredWidth: CGFloat {
        Self.defaultWidth
    }

    var preferredHeight: CGFloat {
        Self.windowHeight
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
                Toggle("Launch E2BBar at login", isOn: self.$model.launchAtLoginEnabled)
            }

            Section("Actions") {
                HStack {
                    Button("Refresh Now") {
                        Task { await self.model.refresh() }
                    }
                    .disabled(self.model.isRefreshing)
                    Button("Open Dashboard") {
                        self.model.openDashboard()
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

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 32, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("E2BBar")
                        .font(.title2.weight(.semibold))
                    Text("macOS menu bar monitor for E2B sandboxes")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Version")
                    Text("0.1.0")
                }
                GridRow {
                    Text("API")
                    Text("GET /v2/sandboxes")
                }
            }
            .font(.callout)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
