import AppKit
import SwiftUI

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private enum Metrics {
        static let menuWidth: CGFloat = 360
        static let sandboxMenuWidth: CGFloat = 520
    }

    private final class SandboxActionRequest: NSObject {
        let sandboxID: String
        let sandboxName: String
        let seconds: Int

        init(sandboxID: String, sandboxName: String, seconds: Int = 0) {
            self.sandboxID = sandboxID
            self.sandboxName = sandboxName
            self.seconds = seconds
        }
    }

    private let model: AppModel
    private let statusBar: NSStatusBar
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var timer: Timer?

    init(model: AppModel, statusBar: NSStatusBar = .system) {
        self.model = model
        self.statusBar = statusBar
        super.init()
        self.menu.autoenablesItems = false
        self.menu.delegate = self
    }

    func start() {
        let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "e2bbar-main-v1"
        item.isVisible = true
        item.button?.imageScaling = .scaleNone
        item.menu = self.menu
        self.statusItem = item

        self.model.onSnapshotChange = { [weak self] in
            self?.applyStatusItemAppearance()
            self?.rebuildMenu()
        }
        self.model.onPollIntervalChange = { [weak self] interval in
            self?.scheduleTimer(interval: interval)
        }

        self.rebuildMenu()
        self.applyStatusItemAppearance()
        self.scheduleTimer(interval: self.model.pollInterval)
        Task { await self.model.refresh() }
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        if let statusItem {
            statusItem.menu = nil
            statusItem.button?.image = nil
            self.statusBar.removeStatusItem(statusItem)
        }
        self.statusItem = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        self.rebuildMenu()
        Task { await self.model.refresh() }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        self.updateHighlights(in: menu, highlightedItem: item)
    }

    func menuDidClose(_ menu: NSMenu) {
        self.updateHighlights(in: menu, highlightedItem: nil)
    }

    @objc private func refreshNow() {
        Task { await self.model.refresh() }
    }

    @objc private func openSettings() {
        SettingsOpener.shared.open()
    }

    @objc private func openDashboard() {
        self.model.openDashboard()
        self.menu.cancelTracking()
    }

    @objc private func openDocs() {
        self.model.openDocs()
        self.menu.cancelTracking()
    }

    @objc private func copySandboxID(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        self.model.copySandboxID(request.sandboxID)
        self.menu.cancelTracking()
    }

    @objc private func copySandboxLogs(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        Task { await self.model.copySandboxLogs(request.sandboxID) }
        self.menu.cancelTracking()
    }

    @objc private func copySandboxMetrics(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        Task { await self.model.copySandboxMetrics(request.sandboxID) }
        self.menu.cancelTracking()
    }

    @objc private func refreshSandboxTTL(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        Task { await self.model.refreshSandboxTTL(request.sandboxID, duration: request.seconds) }
        self.menu.cancelTracking()
    }

    @objc private func setSandboxTimeout(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        Task { await self.model.setSandboxTimeout(request.sandboxID, timeout: request.seconds) }
        self.menu.cancelTracking()
    }

    @objc private func pauseSandbox(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        Task { await self.model.pauseSandbox(request.sandboxID) }
        self.menu.cancelTracking()
    }

    @objc private func deleteSandbox(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SandboxActionRequest else { return }
        guard self.confirmDeleteSandbox(request) else { return }
        Task { await self.model.deleteSandbox(request.sandboxID) }
        self.menu.cancelTracking()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func rebuildMenu() {
        self.menu.removeAllItems()
        self.menu.addItem(self.headerItem())
        self.menu.addItem(.separator())

        self.menu.addItem(self.disabledItem("Running: \(self.model.snapshot.runningCount)"))
        self.menu.addItem(self.disabledItem("Paused: \(self.model.snapshot.pausedCount)"))
        self.menu.addItem(self.disabledItem("API: \(self.model.snapshot.totals.debugSummary)"))
        if let refreshedAt = self.model.snapshot.refreshedAt {
            self.menu.addItem(self.disabledItem("Updated: \(refreshedAt.formatted(date: .omitted, time: .standard))"))
        }
        if let message = self.model.lastActionMessage {
            self.menu.addItem(self.wrappingDisabledItem("Last action: \(message)"))
        }
        if let error = self.model.snapshot.error {
            self.menu.addItem(self.wrappingDisabledItem("Error: \(error)"))
        }

        self.menu.addItem(.separator())
        self.menu.addItem(self.sandboxesItem())
        self.menu.addItem(self.actionItem("Refresh Now", action: #selector(self.refreshNow), image: "arrow.clockwise"))

        self.menu.addItem(.separator())
        self.menu.addItem(self.actionItem("Open E2B Dashboard", action: #selector(self.openDashboard), image: "arrow.up.right.square"))
        self.menu.addItem(self.actionItem("Open E2B Docs", action: #selector(self.openDocs), image: "book"))
        self.menu.addItem(self.actionItem("Settings...", action: #selector(self.openSettings), image: "gearshape"))

        self.menu.addItem(.separator())
        self.menu.addItem(self.actionItem("Quit E2BBar", action: #selector(self.quit), image: "power"))
        self.refreshViewHeights(in: self.menu)
        self.menu.update()
    }

    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem()
        let view = MenuItemHostingView(
            rootView: AnyView(MenuHeaderView(
                snapshot: self.model.snapshot,
                credentialState: self.model.credentialState
            ))
        )
        item.view = view
        item.isEnabled = false
        return item
    }

    private func sandboxesItem() -> NSMenuItem {
        let count = self.model.snapshot.sandboxes.count
        let title = count > 0 ? "Sandboxes (\(count))" : "Sandboxes"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self

        if self.model.snapshot.sandboxes.isEmpty {
            let title = self.model.snapshot.error == nil ? "No sandboxes for this filter" : "No sandbox data"
            submenu.addItem(self.disabledItem(title))
        } else {
            for sandbox in self.model.snapshot.sandboxes {
                submenu.addItem(self.sandboxItem(for: sandbox))
            }
        }

        self.refreshViewHeights(in: submenu, width: Metrics.sandboxMenuWidth)
        item.submenu = submenu
        return item
    }

    private func sandboxItem(for sandbox: E2BSandbox) -> NSMenuItem {
        let request = SandboxActionRequest(sandboxID: sandbox.sandboxID, sandboxName: sandbox.displayName)
        let item = NSMenuItem(title: sandbox.displayName, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: self.iconName(for: sandbox.state), accessibilityDescription: nil)
        item.toolTip = "\(sandbox.state.label): \(sandbox.sandboxID)"
        item.submenu = self.sandboxActionsMenu(for: sandbox, request: request)
        return item
    }

    private func sandboxActionsMenu(for sandbox: E2BSandbox, request: SandboxActionRequest) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self

        let header = NSMenuItem()
        header.view = MenuItemHostingView(
            rootView: AnyView(
                SandboxRowView(sandbox: sandbox) { [weak self] in
                    self?.model.copySandboxID(sandbox.sandboxID)
                    self?.menu.cancelTracking()
                }
            )
        )
        header.isEnabled = false
        submenu.addItem(header)
        submenu.addItem(.separator())

        submenu.addItem(self.sandboxActionItem(
            "Copy Sandbox ID",
            action: #selector(self.copySandboxID(_:)),
            image: "doc.on.doc",
            request: request
        ))
        submenu.addItem(self.sandboxActionItem(
            "Copy Recent Logs",
            action: #selector(self.copySandboxLogs(_:)),
            image: "doc.text.magnifyingglass",
            request: request
        ))
        submenu.addItem(self.sandboxActionItem(
            "Copy Metrics Summary",
            action: #selector(self.copySandboxMetrics(_:)),
            image: "chart.xyaxis.line",
            request: request
        ))

        submenu.addItem(.separator())
        submenu.addItem(self.extendTTLItem(for: request))
        submenu.addItem(self.setTimeoutItem(for: request))
        if sandbox.state == .running {
            submenu.addItem(self.sandboxActionItem(
                "Pause Sandbox",
                action: #selector(self.pauseSandbox(_:)),
                image: "pause.circle",
                request: request
            ))
        }

        submenu.addItem(.separator())
        submenu.addItem(self.sandboxActionItem(
            "Delete Sandbox...",
            action: #selector(self.deleteSandbox(_:)),
            image: "trash",
            request: request
        ))

        self.refreshViewHeights(in: submenu, width: Metrics.sandboxMenuWidth)
        return submenu
    }

    private func extendTTLItem(for request: SandboxActionRequest) -> NSMenuItem {
        let item = NSMenuItem(title: "Extend TTL", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for option in [(900, "15 minutes"), (1800, "30 minutes"), (3600, "1 hour")] {
            submenu.addItem(self.sandboxActionItem(
                "+\(option.1)",
                action: #selector(self.refreshSandboxTTL(_:)),
                image: "plus.circle",
                request: SandboxActionRequest(
                    sandboxID: request.sandboxID,
                    sandboxName: request.sandboxName,
                    seconds: option.0
                )
            ))
        }
        item.submenu = submenu
        return item
    }

    private func setTimeoutItem(for request: SandboxActionRequest) -> NSMenuItem {
        let item = NSMenuItem(title: "Set Timeout", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for option in [(3600, "1 hour"), (21600, "6 hours"), (86400, "24 hours")] {
            submenu.addItem(self.sandboxActionItem(
                option.1,
                action: #selector(self.setSandboxTimeout(_:)),
                image: "clock",
                request: SandboxActionRequest(
                    sandboxID: request.sandboxID,
                    sandboxName: request.sandboxName,
                    seconds: option.0
                )
            ))
        }
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func wrappingDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuTextItemView(title: title, width: Metrics.menuWidth)
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector, image: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        return item
    }

    private func sandboxActionItem(
        _ title: String,
        action: Selector,
        image: String,
        request: SandboxActionRequest
    ) -> NSMenuItem {
        let item = self.actionItem(title, action: action, image: image)
        item.representedObject = request
        return item
    }

    private func applyStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }
        self.statusItem?.length = NSStatusItem.variableLength
        button.attributedTitle = NSAttributedString()
        button.title = self.statusTitle()
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
        button.imagePosition = .imageLeft
        button.toolTip = "E2BBar: \(self.model.snapshot.runningCount) running, \(self.model.snapshot.pausedCount) paused"
    }

    private func statusTitle() -> String {
        let title = "\(self.model.snapshot.runningCount)"
        return self.model.snapshot.isHealthy ? title : "! \(title)"
    }

    private func scheduleTimer(interval: TimeInterval) {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh()
            }
        }
    }

    private func confirmDeleteSandbox(_ request: SandboxActionRequest) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete \(request.sandboxName)?"
        alert.informativeText = "This kills sandbox \(request.sandboxID). This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func iconName(for state: E2BSandboxState) -> String {
        switch state {
        case .running:
            "play.circle"
        case .paused:
            "pause.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    private func refreshViewHeights(in menu: NSMenu, width: CGFloat = Metrics.menuWidth) {
        for item in menu.items {
            guard let view = item.view, let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
    }

    private func updateHighlights(in menu: NSMenu, highlightedItem: NSMenuItem?) {
        for item in menu.items {
            guard let highlighting = item.view as? MenuItemHighlighting else { continue }
            highlighting.setHighlighted(item === highlightedItem && item.isEnabled)
        }
    }
}

@MainActor
private final class MenuTextItemView: NSView, MenuItemMeasuring {
    private enum Metrics {
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 4
    }

    private let textField = NSTextField(labelWithString: "")

    override var allowsVibrancy: Bool {
        true
    }

    init(title: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        self.textField.stringValue = title
        self.textField.font = .menuFont(ofSize: 0)
        self.textField.textColor = .disabledControlTextColor
        self.textField.lineBreakMode = .byWordWrapping
        self.textField.maximumNumberOfLines = 0
        self.textField.cell?.wraps = true
        self.addSubview(self.textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.textField.frame = self.labelFrame(width: self.bounds.width, height: self.bounds.height)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let labelWidth = width - Metrics.horizontalInset * 2
        let boundingSize = NSSize(width: labelWidth, height: .greatestFiniteMagnitude)
        let measured = self.textField.cell?.cellSize(forBounds: NSRect(origin: .zero, size: boundingSize)).height
            ?? self.textField.intrinsicContentSize.height
        return ceil(measured + Metrics.verticalInset * 2)
    }

    private func labelFrame(width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: Metrics.horizontalInset,
            y: Metrics.verticalInset,
            width: width - Metrics.horizontalInset * 2,
            height: height - Metrics.verticalInset * 2
        )
    }
}
