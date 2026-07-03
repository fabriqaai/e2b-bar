import AppKit
import SwiftUI

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private enum Metrics {
        static let menuWidth: CGFloat = 360
        static let sandboxMenuWidth: CGFloat = 520
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
        guard let sandboxID = sender.representedObject as? String else { return }
        self.model.copySandboxID(sandboxID)
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
        let item = NSMenuItem(title: "", action: #selector(self.copySandboxID(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = sandbox.sandboxID
        item.toolTip = "Copy sandbox ID: \(sandbox.sandboxID)"
        let highlightState = MenuItemHighlightState()
        item.view = MenuItemHostingView(
            rootView: AnyView(
                SandboxRowView(sandbox: sandbox) { [weak self] in
                    self?.model.copySandboxID(sandbox.sandboxID)
                    self?.menu.cancelTracking()
                }
            ),
            highlightState: highlightState
        )
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
