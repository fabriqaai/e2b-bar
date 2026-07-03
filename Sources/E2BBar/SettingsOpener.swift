import AppKit

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    private var openHandler: (() -> Void)?

    private init() {}

    func configure(open: @escaping () -> Void) {
        self.openHandler = open
    }

    func open() {
        if let openHandler {
            openHandler()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
