import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TuckController?
    private var trustPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = TuckController()
        self.controller = controller

        if SettingsDriver.isTrusted {
            // Make sure tucked apps are hidden (they normally already are:
            // macOS remembers the switches across restarts).
            if !Preferences.tuckedApps.isEmpty { controller.collapse() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.askForAccessibility() }
            let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard SettingsDriver.isTrusted else { return }
                    timer.invalidate()
                    self?.controller?.collapse()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            trustPoll = timer
        }

        if !Preferences.hasLaunchedBefore || Preferences.tuckedApps.isEmpty {
            Preferences.hasLaunchedBefore = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { controller.showChooser() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.driver.quitIfLaunchedByUs()
    }

    private func askForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Tuck needs Accessibility access"
        alert.informativeText = """
        Tuck hides icons with macOS's own “show in menu bar” switches (System Settings → Menu Bar), flipping them for you through Accessibility. That is what keeps the menu bar clean on every display.

        Click “Open System Settings”, then turn on Tuck under Privacy & Security → Accessibility.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsDriver.promptForTrust()
            SettingsDriver.openAccessibilitySettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
