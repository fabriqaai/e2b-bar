import AppKit
import SwiftUI

@main
@MainActor
struct E2BBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model: AppModel

    init() {
        let model = AppModel()
        self.model = model
        self.appDelegate.configure(model: model)
    }

    var body: some Scene {
        WindowGroup("E2BBarLifecycleKeepalive") {
            LifecycleKeepaliveView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(model: self.model)
        }
        .defaultSize(width: SettingsTab.general.preferredWidth, height: SettingsTab.general.preferredHeight)
        .windowResizability(.contentSize)
    }
}

private struct LifecycleKeepaliveView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onAppear {
                SettingsOpener.shared.configure {
                    self.openSettings()
                }
                guard let window = NSApp.windows.first(where: { $0.title == "E2BBarLifecycleKeepalive" }) else { return }
                window.styleMask = [.borderless]
                window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                window.isExcludedFromWindowsMenu = true
                window.level = .floating
                window.isOpaque = false
                window.alphaValue = 0
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.canHide = false
                window.setContentSize(NSSize(width: 1, height: 1))
                window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    func configure(model: AppModel) {
        self.menuController = StatusMenuController(model: model)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        self.menuController?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.menuController?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
