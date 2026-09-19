import Cocoa
import ServiceManagement

/// The menu bar chevron and the show/hide logic.
///
/// Tuck does not push or overflow anything. It uses Apple's own per-app
/// "show in menu bar" switches (System Settings → Menu Bar), driven through
/// Accessibility, so tucked icons are removed cleanly on every display with
/// no « button. "Peek" simply switches them on again for a while.
@MainActor
final class TuckController: NSObject {
    /// Where the "Support Tuck on Ko-fi" menu item goes.
    static let supportURL = URL(string: "https://ko-fi.com/YOUR-KOFI-NAME")!

    let driver = SettingsDriver()
    private var statusItem: NSStatusItem!
    private var autoHideTimer: Timer?
    private var chooser: ChooserWindowController?

    private(set) var isCollapsed = true
    private var busy = false

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "tuck.chevron"
        statusItem.behavior = []
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Tuck – click to show or hide tucked icons. Right-click for options."
        }
        updateImage()
        installSignalToggle()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    /// System Settings was quit: warm it up again in the background so the
    /// next peek does not have to wait for it to launch.
    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == SettingsDriver.settingsBundleID else { return }
        warmUp(after: 1.5)
    }

    func warmUp(after delay: TimeInterval = 0) {
        guard Preferences.keepSettingsReady, !Preferences.tuckedApps.isEmpty, SettingsDriver.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.busy else { return }
            self.driver.withAppRows { _ in }
        }
    }

    /// `kill -USR1 $(pgrep -x Tuck)` toggles Tuck and `kill -USR2 …` opens the
    /// chooser, handy for scripting and Shortcuts.
    private var signalSources: [DispatchSourceSignal] = []
    private func installSignalToggle() {
        for (sig, handler) in [(SIGUSR1, { [weak self] in self?.toggleCollapsed() }),
                               (SIGUSR2, { [weak self] in self?.showChooser() })] as [(Int32, @MainActor () -> Void)] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { handler() }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Show / hide

    func collapse() { apply(show: false, reason: "hide") }

    func expand() {
        apply(show: true, reason: "peek") { [weak self] in self?.scheduleAutoHideIfNeeded() }
    }

    func toggleCollapsed() {
        if isCollapsed { expand() } else { collapse() }
    }

    /// Switches every tucked app on or off.
    private func apply(show: Bool, reason: String, completion: (@MainActor () -> Void)? = nil) {
        let names = Preferences.tuckedApps
        isCollapsed = !show
        updateImage()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard !names.isEmpty, SettingsDriver.isTrusted else { completion?(); return }
        guard !busy else { return }
        let started = Date()
        if driver.fastSet(names: names, on: show) {
            log("\(reason): \(names.count) apps via cached switches in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            completion?()
            return
        }
        busy = true
        driver.withAppRows { [weak self] rows in
            guard let self else { return }
            let scanned = Date()
            var missing: [String] = []
            for name in names where !self.driver.set(rows, name: name, on: show) {
                missing.append(name)
            }
            self.busy = false
            let ms1 = Int(scanned.timeIntervalSince(started) * 1000), ms2 = Int(Date().timeIntervalSince(scanned) * 1000)
            self.log("\(reason): \(names.count) apps, missing=\(missing) scan=\(ms1)ms press=\(ms2)ms path=\(self.driver.lastPath)")
            completion?()
        }
    }

    /// Called by the chooser when one app is (un)tucked.
    func didChangeTucked(name: String, tucked: Bool) {
        guard SettingsDriver.isTrusted else { return }
        // While collapsed a newly tucked app hides at once; un-tucking shows it.
        let show = tucked ? !isCollapsed : true
        if driver.fastSet(names: [name], on: show) { return }
        driver.withAppRows { [weak self] rows in
            self?.driver.set(rows, name: name, on: show)
        }
    }

    private func scheduleAutoHideIfNeeded() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard Preferences.autoHideEnabled, !isCollapsed else { return }
        let timer = Timer(timeInterval: Preferences.autoHideSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimer = timer
    }

    private func updateImage() {
        statusItem.button?.image = IconStyle.current.image(collapsed: isCollapsed)
    }

    // MARK: - Chooser

    func showChooser() {
        if chooser == nil { chooser = ChooserWindowController(controller: self) }
        chooser?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        chooser?.window?.makeKeyAndOrderFront(nil)
        if UserDefaults.standard.bool(forKey: "debugSnapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.snapshotChooser() }
        }
    }

    /// Debug: writes the chooser window's content to ~/Library/Logs/Tuck-chooser.png.
    private func snapshotChooser() {
        guard let view = chooser?.window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tuck-chooser.png")
        try? png.write(to: url)
    }

    // MARK: - Actions & menu

    @objc private func clicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleCollapsed()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: isCollapsed ? "Show Tucked Icons" : "Hide Tucked Icons",
                                    action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = !Preferences.tuckedApps.isEmpty
        menu.addItem(toggleItem)

        let choose = NSMenuItem(title: "Choose Icons to Tuck…", action: #selector(menuChoose), keyEquivalent: ",")
        choose.target = self
        menu.addItem(choose)
        menu.addItem(.separator())

        let autoHide = NSMenuItem(title: "Hide Again After", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let never = NSMenuItem(title: "Never", action: #selector(setAutoHideNever), keyEquivalent: "")
        never.target = self
        never.state = Preferences.autoHideEnabled ? .off : .on
        sub.addItem(never)
        sub.addItem(.separator())
        for (title, secs) in [("5 seconds", 5.0), ("10 seconds", 10.0), ("30 seconds", 30.0), ("1 minute", 60.0), ("5 minutes", 300.0)] {
            let mi = NSMenuItem(title: title, action: #selector(setAutoHideSeconds(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = secs
            mi.state = (Preferences.autoHideEnabled && Preferences.autoHideSeconds == secs) ? .on : .off
            sub.addItem(mi)
        }
        autoHide.submenu = sub
        menu.addItem(autoHide)

        let styleItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in IconStyle.allCases {
            let mi = NSMenuItem(title: style.title, action: #selector(setIconStyle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = style.rawValue
            mi.image = style.image(collapsed: true)
            mi.state = style == IconStyle.current ? .on : .off
            styleMenu.addItem(mi)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let ready = NSMenuItem(title: "Keep System Settings Ready (Instant Peek)", action: #selector(toggleKeepReady), keyEquivalent: "")
        ready.target = self
        ready.state = Preferences.keepSettingsReady ? .on : .off
        menu.addItem(ready)

        if !SettingsDriver.isTrusted {
            let ax = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }

        menu.addItem(.separator())
        let support = NSMenuItem(title: "Support Tuck on Ko-fi ♥", action: #selector(openSupport), keyEquivalent: "")
        support.target = self
        menu.addItem(support)
        menu.addItem(NSMenuItem(title: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggle() { toggleCollapsed() }
    @objc private func menuChoose() { showChooser() }

    @objc private func setAutoHideNever() {
        Preferences.autoHideEnabled = false
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    @objc private func setAutoHideSeconds(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        Preferences.autoHideEnabled = true
        Preferences.autoHideSeconds = secs
        if !isCollapsed { scheduleAutoHideIfNeeded() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func setIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = IconStyle(rawValue: raw) else { return }
        IconStyle.current = style
        updateImage()
    }

    @objc private func toggleKeepReady() {
        Preferences.keepSettingsReady.toggle()
        if Preferences.keepSettingsReady { warmUp() }
    }

    @objc private func openSupport() {
        NSWorkspace.shared.open(Self.supportURL)
    }

    @objc private func grantAccessibility() {
        SettingsDriver.promptForTrust()
        SettingsDriver.openAccessibilitySettings()
    }

    // MARK: - Logging

    /// Writes to ~/Library/Logs/Tuck.log when `defaults write com.champ.tuck debugLog -bool true`.
    func log(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tuck.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}
