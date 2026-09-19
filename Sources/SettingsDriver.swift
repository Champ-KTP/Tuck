import Cocoa
import ApplicationServices

/// Drives the per-app switches in System Settings → Menu Bar through the
/// Accessibility API. Those switches are Apple's own way of hiding a menu bar
/// item on macOS 26+: the item is removed outright (no overflow « button),
/// the change applies immediately to a running app, and it is the same on
/// every display.
@MainActor
final class SettingsDriver {
    static let settingsBundleID = "com.apple.systempreferences"
    static let menuBarPaneURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    struct Row: Identifiable {
        let name: String
        let isOn: Bool
        fileprivate let toggle: AXUIElement
        fileprivate let labelElement: AXUIElement
        var id: String { name }
    }

    private(set) var launchedByUs = false
    /// Debug: how the last row lookup was satisfied.
    private(set) var lastPath = ""
    /// Switch elements remembered from the last scan. They stay valid while
    /// System Settings keeps the pane alive, even with its window hidden, so
    /// later changes can press them directly instead of re-opening the pane.
    private var cachedToggles: [String: (label: AXUIElement, toggle: AXUIElement)] = [:]

    /// Forget the remembered switches (the app list in System Settings may
    /// have changed, e.g. a new menu bar app was installed).
    func invalidateCache() { cachedToggles.removeAll() }

    /// Fast path: flips the given apps using remembered switches. Returns
    /// false (and forgets the cache) if any switch is no longer reachable.
    func fastSet(names: [String], on: Bool) -> Bool {
        guard !names.isEmpty, names.allSatisfy({ cachedToggles[$0] != nil }) else { return false }
        // Validate everything first so a half-applied change never happens.
        var current: [String: Bool] = [:]
        for name in names {
            // The label next to the switch must still read this app's name;
            // if the list was rebuilt the element could belong to another row.
            guard let entry = cachedToggles[name], label(entry.label) == name,
                  let value = numberValue(entry.toggle) else {
                cachedToggles.removeAll()
                return false
            }
            current[name] = value != 0
        }
        for name in names where current[name] != on {
            guard let toggle = cachedToggles[name]?.toggle,
                  AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success else {
                cachedToggles.removeAll()
                return false
            }
        }
        lastPath = "cached"
        return true
    }

    // MARK: - Accessibility permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Public

    /// Makes the Menu Bar pane available (launching System Settings in the
    /// background if needed) and calls back with the app rows it lists.
    /// Rows for Tuck itself and the pane's general options are excluded.
    func withAppRows(timeout: TimeInterval = 8, _ completion: @escaping @MainActor ([Row]) -> Void) {
        // Fast path: System Settings is already showing the pane.
        let existing = appRows()
        if !existing.isEmpty {
            lastPath = "scan"
            completion(existing)
            return
        }
        lastPath = "open"

        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).isEmpty
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // A hidden window never lays out its rows; hide it again once read.
        config.hides = false
        NSWorkspace.shared.open(Self.menuBarPaneURL, configuration: config) { _, _ in }
        if !wasRunning { launchedByUs = true }

        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            let rows = self.appRows()
            if !rows.isEmpty {
                self.hideWindow()
                completion(rows)
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { poll() }
            } else {
                self.hideWindow()
                completion([])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
    }

    /// Flips one app's switch if needed. Returns false if the row is missing.
    @discardableResult
    func set(_ rows: [Row], name: String, on: Bool) -> Bool {
        guard let row = rows.first(where: { $0.name == name }) else { return false }
        if row.isOn == on { return true }
        return AXUIElementPerformAction(row.toggle, kAXPressAction as CFString) == .success
    }

    func hideWindow() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first?.hide()
    }

    func quitIfLaunchedByUs() {
        guard launchedByUs else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first?.terminate()
        launchedByUs = false
    }

    // MARK: - Reading the pane

    /// The per-app section of the pane: one group whose children run
    /// label, switch, label, switch, … Pair each switch with the label before it.
    private func appRows() -> [Row] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first else { return [] }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 1.0)
        var best: [Row] = []
        for window in children(of: appEl) {
            for group in descendants(of: window, maxDepth: 16) where role(group) == "AXGroup" {
                let kids = children(of: group)
                var rows: [Row] = []
                var lastLabel: (String, AXUIElement)?
                for kid in kids {
                    let r = role(kid)
                    if r == "AXStaticText" {
                        lastLabel = label(kid).map { ($0, kid) }
                    } else if r == "AXCheckBox" && subrole(kid) == "AXSwitch", let (name, labelEl) = lastLabel {
                        rows.append(Row(name: name, isOn: (numberValue(kid) ?? 0) != 0, toggle: kid, labelElement: labelEl))
                        lastLabel = nil
                    }
                }
                // The app section is the only group with several switches and
                // always lists Tuck itself.
                if rows.count >= 2, rows.contains(where: { $0.name == "Tuck" }), rows.count > best.count {
                    best = rows
                }
            }
        }
        if !best.isEmpty {
            cachedToggles = Dictionary(best.map { ($0.name, (label: $0.labelElement, toggle: $0.toggle)) }, uniquingKeysWith: { first, _ in first })
        }
        return best.filter { $0.name != "Tuck" }
    }

    // MARK: - AX helpers

    private func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
    private func role(_ el: AXUIElement) -> String { attribute(el, kAXRoleAttribute) as? String ?? "" }
    private func subrole(_ el: AXUIElement) -> String { attribute(el, kAXSubroleAttribute) as? String ?? "" }
    private func numberValue(_ el: AXUIElement) -> Int? { (attribute(el, kAXValueAttribute) as? NSNumber)?.intValue }
    private func label(_ el: AXUIElement) -> String? {
        if let v = attribute(el, kAXValueAttribute) as? String, !v.isEmpty { return v }
        if let t = attribute(el, kAXTitleAttribute) as? String, !t.isEmpty { return t }
        if let d = attribute(el, kAXDescriptionAttribute) as? String, !d.isEmpty { return d }
        return nil
    }
    private func children(of el: AXUIElement) -> [AXUIElement] {
        attribute(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private func descendants(of el: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        guard maxDepth > 0 else { return [] }
        var out: [AXUIElement] = []
        for c in children(of: el) {
            out.append(c)
            out.append(contentsOf: descendants(of: c, maxDepth: maxDepth - 1))
        }
        return out
    }
}
