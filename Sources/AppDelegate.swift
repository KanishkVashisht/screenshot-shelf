import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusItemView!
    private let shelf = ShelfController()
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var scanning = false
    private var scanGeneration = 0
    private var lastFingerprint = ""
    private var hotKeyStatus: OSStatus = noErr
    private let holdGesture = HoldGesture()
    private var shortcut = ShelfShortcut.default
    private var shortcutEnabled = true
    private var latestScreenshot: Screenshot?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.target = nil
        statusItem.action = nil
        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness))
        statusView.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Screenshot Shelf")
        statusView.image?.isTemplate = true
        statusView.toolTip = "Click to open screenshots · Drag for the latest screenshot"
        statusView.screenshotProvider = { [weak self] in
            guard let self else { return nil }
            return ScreenshotStore.scan(folder: ScreenshotStore.folder, limit: 1).screenshots.first ?? self.latestScreenshot
        }
        statusView.onClick = { [weak self] in self?.statusClicked() }
        statusView.onRightClick = { [weak self] in self?.statusRightClicked() }
        statusView.onDragStart = { [weak self] in self?.shelf.hide() }
        statusItem.view = statusView
        shelf.onSettings = { [weak self] button in self?.settingsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button) }
        shelf.onRefresh = { [weak self] in self?.refresh(force: true) }
        shelf.onClose = { [weak self] in self?.stopMonitoring() }
        shortcut = loadShortcut()
        shortcutEnabled = loadShortcutEnabled()
        holdGesture.configure(for: shortcut)
        shelf.setShortcutName(shortcutEnabled ? shortcut.displayName : "Off")
        holdGesture.onPress = { [weak self] in self?.showShelf() }
        holdGesture.onRelease = { [weak self] in self?.shelf.hide() }
        registerHotKey()
        refresh(force: true)
        if CommandLine.arguments.contains("--enable-login") { enableLogin() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusClicked()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        stopMonitoring()
        holdGesture.release()
    }

    private func registerHotKey() {
        guard shortcutEnabled else {
            hotKeyStatus = noErr
            UserDefaults.standard.set(hotKeyStatus, forKey: "lastShortcutRegistrationStatus")
            return
        }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x53534846, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { delegate.holdGesture.press() }
            else { delegate.holdGesture.release() }
            return noErr
        }, types.count, &types, pointer, &eventHandler)
        hotKeyStatus = handlerStatus
        if handlerStatus == noErr {
            hotKeyStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x53534846, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        }
        UserDefaults.standard.set(hotKeyStatus, forKey: "lastShortcutRegistrationStatus")
        NSLog("Screenshot Shelf: global shortcut registration status = %d", hotKeyStatus)
        if hotKeyStatus != noErr {
            statusView.toolTip = "Screenshot Shelf — \(shortcut.displayName) is unavailable"
            DispatchQueue.main.async {
                self.showAlert("Couldn’t register \(self.shortcut.displayName)", "Screenshot Shelf is available from its menu bar icon. Another app may already use this shortcut. Free up \(self.shortcut.displayName), then choose Retry Shortcut in Settings. (macOS status \(self.hotKeyStatus))")
            }
        }
    }

    private func showShelf(anchor: NSPoint? = nil) {
        shelf.show(near: anchor)
        refresh(force: true)
        startMonitoring()
    }

    private func refresh(force: Bool = false) {
        guard !scanning, !shelf.isDragging else { return }
        scanning = true
        let folder = ScreenshotStore.folder
        let generation = scanGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let scan = ScreenshotStore.scan(folder: folder)
            DispatchQueue.main.async {
                self.scanning = false
                guard generation == self.scanGeneration else { self.refresh(force: true); return }
                let fingerprint = scan.folder.path + (scan.error ?? "") + scan.screenshots.map { $0.revision + String($0.thumbnail != nil) }.joined(separator: "|")
                self.latestScreenshot = scan.screenshots.first
                if !self.shelf.isDragging, force || fingerprint != self.lastFingerprint {
                    self.lastFingerprint = fingerprint
                    self.shelf.render(scan)
                }
            }
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        // Mouse-only monitors do not request Accessibility or Input Monitoring.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isPointerOverShelfOrStatusItem() else { return }
            self.shelf.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                if let self, event.window === self.shelf.panel, self.shelf.panel.onKey?(event) == true { return nil }
                return event
            }
            if let self, !self.isPointerOverShelfOrStatusItem() { self.shelf.hide() }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func stopMonitoring() {
        timer?.invalidate(); timer = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }

    private func statusClicked() {
        if shelf.panel.isVisible {
            shelf.hide()
        } else {
            showShelf(anchor: statusViewFrameInScreen?.origin)
        }
    }

    private func statusRightClicked() {
        settingsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: statusView.bounds.minY), in: statusView)
    }

    private func isPointerOverShelfOrStatusItem() -> Bool {
        let point = NSEvent.mouseLocation
        if shelf.panel.frame.contains(point) { return true }
        guard let frame = statusViewFrameInScreen else { return false }
        return frame.contains(point)
    }

    private var statusViewFrameInScreen: NSRect? {
        guard let window = statusView.window else { return nil }
        return window.convertToScreen(statusView.convert(statusView.bounds, to: nil))
    }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }
        let heading = NSMenuItem(title: shortcutEnabled ? "Hold \(shortcut.displayName) for screenshots" : "Keyboard shortcut disabled", action: nil, keyEquivalent: "")
        menu.addItem(heading)
        menu.addItem(.separator())
        _ = add("Choose Screenshot Folder…", #selector(chooseFolder))
        _ = add("Use macOS Screenshot Folder", #selector(resetFolder))
        _ = add("Open Screenshot Folder", #selector(openFolder))
        _ = add("Change Shortcut…", #selector(changeShortcut))
        menu.addItem(.separator())
        let login = add("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval {
            _ = add("Approve in Login Items…", #selector(openLoginSettings))
        }
        if hotKeyStatus != noErr { _ = add("Retry Shortcut", #selector(retryShortcut)) }
        menu.addItem(.separator())
        _ = add("Quit Screenshot Shelf", #selector(quit))
        return menu
    }

    @objc private func chooseFolder() {
        shelf.hide()
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = "Choose your screenshot folder"
        picker.message = "Screenshot Shelf shows the most recent screenshots in this folder."
        picker.prompt = "Use Folder"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.directoryURL = ScreenshotStore.folder
        if picker.runModal() == .OK, let url = picker.url {
            UserDefaults.standard.set(url.path, forKey: "screenshotFolder")
            scanGeneration += 1
            lastFingerprint = ""
        }
        refresh(force: true)
    }
    @objc private func resetFolder() {
        UserDefaults.standard.removeObject(forKey: "screenshotFolder")
        scanGeneration += 1
        refresh(force: true)
    }
    @objc private func openFolder() { NSWorkspace.shared.open(ScreenshotStore.folder) }
    @objc private func retryShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
        registerHotKey()
    }
    @objc private func changeShortcut() {
        let recorder = ShortcutRecorderView(shortcut: shortcut)
        let alert = NSAlert()
        alert.messageText = "Change Screenshot Shelf Shortcut"
        alert.informativeText = "Press a key combination. The shortcut must include at least one modifier."
        alert.accessoryView = recorder
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = recorder
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result == .alertSecondButtonReturn {
            shortcutEnabled = false
            UserDefaults.standard.set(false, forKey: "shortcutEnabled")
            holdGesture.release()
            shelf.setShortcutName("Off")
            retryShortcut()
            return
        }
        guard result == .alertFirstButtonReturn, let newShortcut = recorder.shortcut else { return }
        shortcut = newShortcut
        shortcutEnabled = true
        shelf.setShortcutName(shortcut.displayName)
        UserDefaults.standard.set(Int(newShortcut.keyCode), forKey: "shortcutKeyCode")
        UserDefaults.standard.set(Int(newShortcut.modifiers), forKey: "shortcutModifiers")
        UserDefaults.standard.set(true, forKey: "shortcutEnabled")
        holdGesture.configure(for: shortcut)
        retryShortcut()
    }
    private func loadShortcut() -> ShelfShortcut {
        guard UserDefaults.standard.object(forKey: "shortcutKeyCode") != nil else { return .default }
        return ShelfShortcut(keyCode: UInt32(UserDefaults.standard.integer(forKey: "shortcutKeyCode")), modifiers: UInt32(UserDefaults.standard.integer(forKey: "shortcutModifiers")))
    }
    private func loadShortcutEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: "shortcutEnabled") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "shortcutEnabled")
    }
    private func enableLogin() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() }
        catch { showAlert("Couldn’t enable Launch at Login", error.localizedDescription) }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else { try SMAppService.mainApp.register() }
        } catch { showAlert("Couldn’t change Launch at Login", error.localizedDescription) }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}

final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var shortcut: ShelfShortcut?

    init(shortcut: ShelfShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 42))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        label.frame = bounds.insetBy(dx: 8, dy: 7)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        shortcut = ShelfShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        updateLabel()
    }

    private func updateLabel() {
        label.stringValue = shortcut?.displayName ?? "Press a shortcut"
    }
}
