import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: PlayerStore!
    var controller: PlayerViewController!
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let loginItem = LoginItemController()
    private var localClicks: Any?
    private var outsideClicks: Any?
    private var inactiveObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opening a second copy should not create a second audio player.
        let identifier = Bundle.main.bundleIdentifier ?? AppPreferences.bundleIdentifier
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if let peer = peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            peer.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil); return
        }
        installMenu()
        AppPreferences.migrate()
        store = PlayerStore()
        controller = PlayerViewController(store: store)
        controller.close = { [weak self] in self?.popover.performClose(nil) }
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 340, height: 460)
        // Transient popovers dismiss on mouse-down before the status button's
        // mouse-up action, making a second icon click immediately reopen them.
        popover.behavior = .applicationDefined
        popover.animates = false
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.title = ""
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            button.image = icon
        }
        button.setAccessibilityLabel("Motif")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self; button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installDismissalMonitors()
        store.changed = { [weak self] in self?.refresh() }
        refresh()
        if CommandLine.arguments.contains("--enable-login-item") { updateLoginItem(enabled: true) }
        let loginLaunch = LoginItemController.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        if !loginLaunch && !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { self.show() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
        if let localClicks { NSEvent.removeMonitor(localClicks) }
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
    }
    private func installDismissalMonitors() {
        localClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closeIfOutside(); return event
        }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeIfOutside()
        }
        inactiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                  object: NSApp, queue: .main) { [weak self] _ in
            guard let self else { return }
            // A status-icon click can also cause an activation change. Let its
            // mouse-up action close the popup instead of closing and reopening.
            if NSEvent.pressedMouseButtons != 0, let button = self.statusItem.button,
               let window = button.window,
               window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation) { return }
            self.popover.performClose(nil)
        }
    }
    private func closeIfOutside() {
        guard popover.isShown, let button = statusItem.button, let window = button.window else { return }
        let iconFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let popupFrame = popover.contentViewController?.view.window?.frame ?? .zero
        if PopoverHitTest.isOutside(NSEvent.mouseLocation, icon: iconFrame, popup: popupFrame) {
            popover.performClose(nil)
        }
    }
    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Motif", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Motif", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenu(title: "Edit")
        for (name, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    func show() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button { showMenu(button) }
        else if popover.isShown { popover.performClose(nil) }
        else { show() }
    }
    private func refresh() {
        controller.render()
        guard let button = statusItem.button else { return }
        button.title = ""
        button.toolTip = store.current.map { "\($0.title) · \($0.artist)" } ?? "Motif"
    }

    private func showMenu(_ anchor: NSView) {
        popover.performClose(nil)
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            ("Show player", #selector(openPlayer)), ("Search…", #selector(focusSearch)),
            ("Play / Pause", #selector(toggle)), ("Next track", #selector(next)),
            ("Retry mix", #selector(retryMix)), ("Open track on YouTube", #selector(openTrack)),
            ("About Motif", #selector(about))
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        let volumeItem = NSMenuItem()
        let volumeView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 34))
        let volumeLabel = label("Volume", size: 12)
        volumeLabel.frame = NSRect(x: 14, y: 8, width: 55, height: 18)
        let slider = NSSlider(value: Double(store.volume * 100), minValue: 0, maxValue: 100, target: self, action: #selector(changeVolume(_:)))
        slider.cell = AccentSliderCell()
        slider.minValue = 0; slider.maxValue = 100; slider.doubleValue = Double(store.volume * 100)
        slider.target = self; slider.action = #selector(changeVolume(_:))
        slider.isContinuous = true
        slider.frame = NSRect(x: 74, y: 7, width: 110, height: 20)
        slider.setAccessibilityLabel("Volume")
        volumeView.addSubview(volumeLabel); volumeView.addSubview(slider)
        volumeItem.view = volumeView; menu.addItem(volumeItem)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = loginItem.menuState
        menu.addItem(login)
        if loginItem.status == .requiresApproval {
            let settings = NSMenuItem(title: "Allow in System Settings…", action: #selector(openLoginSettings), keyEquivalent: "")
            settings.target = self; menu.addItem(settings)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Motif", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
    }
    @objc private func changeVolume(_ sender: NSSlider) { store.volume = sender.floatValue / 100 }
    @objc private func toggleLoginItem() {
        updateLoginItem(enabled: loginItem.menuState == .off)
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    private func updateLoginItem(enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            if enabled && loginItem.status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "Allow Motif to open at login"
                alert.informativeText = "Enable Motif in System Settings → General → Login Items."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { openLoginSettings() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc private func openPlayer() { show() }
    @objc private func focusSearch() { show(); controller.focusSearch() }
    @objc private func toggle() { store.toggle() }
    @objc private func next() { store.next() }
    @objc private func previous() { store.previous() }
    @objc private func retryMix() { store.retryMix() }
    @objc private func openTrack() { if let url = store.current?.url { NSWorkspace.shared.open(url) } }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Motif", .applicationVersion: "1.4.1",
            .credits: NSAttributedString(string: "A native macOS adaptation of itsdotdev/omarchy-youtube-music.\nPublic YouTube search and mixes. No account required.\nBuilt with yt-dlp and Deno.\nNot affiliated with YouTube or Google.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

if CommandLine.arguments.contains("--login-item-status") {
    print(LoginItemController().statusDescription)
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
