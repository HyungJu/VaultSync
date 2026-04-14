import AppKit
import Combine
import SwiftUI

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let manager: GitSyncManager

    init(manager: GitSyncManager) {
        self.manager = manager
        super.init(window: nil)

        let hostingController = NSHostingController(rootView: setupRootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "VaultSync"
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.delegate = self
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        guard let hostingController = window?.contentViewController as? NSHostingController<AnyView> else { return }
        hostingController.rootView = AnyView(setupRootView())
    }

    func showAndFocus() {
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        manager.closeSetup()
        sender.orderOut(nil)
        return false
    }

    private func setupRootView() -> AnyView {
        guard let target = manager.setupTargetViewModel() else {
            return AnyView(EmptyView())
        }
        return AnyView(SetupWizardView(manager: manager, target: target))
    }
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    init(manager: GitSyncManager) {
        super.init(window: nil)

        let contentView = ContentView(
            manager: manager,
            compact: false,
            onOpenWindow: nil,
            onOpenSetup: { id in
                manager.openSetup(for: id)
            }
        )
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "VaultSync"
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.delegate = self
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

final class StatusBarController: NSObject {
    private let manager: GitSyncManager
    private let statusItem: NSStatusItem
    private let dashboardWindowController: DashboardWindowController
    private let setupWindowController: SetupWindowController
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var lastIconName: String?

    init(manager: GitSyncManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.dashboardWindowController = DashboardWindowController(manager: manager)
        self.setupWindowController = SetupWindowController(manager: manager)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        observeManager()
    }

    func openDashboard() {
        dashboardWindowController.showAndFocus()
    }

    func closeDashboard() {
        dashboardWindowController.hide()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 600)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(
                manager: manager,
                compact: true,
                onOpenWindow: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.openDashboard()
                },
                onOpenSetup: { [weak self] id in
                    self?.popover.performClose(nil)
                    self?.manager.openSetup(for: id)
                }
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        updateStatusIcon()
    }

    private func observeManager() {
        manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)

        manager.$setupTargetID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                if id == nil {
                    self.setupWindowController.hide()
                } else {
                    self.setupWindowController.showAndFocus()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let nextIconName = manager.menuBarIconName
        guard nextIconName != lastIconName else { return }
        lastIconName = nextIconName
        button.image = NSImage(systemSymbolName: nextIconName, accessibilityDescription: "VaultSync")
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            openDashboard()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open VaultSync", action: #selector(openDashboardAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close Window", action: #selector(closeDashboardAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VaultSync", action: #selector(quitAction), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func openDashboardAction() {
        openDashboard()
    }

    @objc
    private func closeDashboardAction() {
        closeDashboard()
    }

    @objc
    private func quitAction() {
        NSApp.terminate(nil)
    }
}
