import Cocoa
import SwiftUI

/// "Choose Icons to Tuck": the same app list System Settings shows, with a
/// checkbox per app.
@MainActor
final class ChooserModel: ObservableObject {
    struct Entry: Identifiable {
        let name: String
        var tucked: Bool
        /// Switched off in System Settings by hand (not by Tuck).
        var hiddenBySystem: Bool
        var id: String { name }
    }

    @Published var entries: [Entry] = []
    @Published var status = "Loading the menu bar app list…"
    weak var controller: TuckController?

    func reload() {
        guard let controller else { return }
        guard SettingsDriver.isTrusted else {
            status = "Tuck needs Accessibility access to read and flip the menu bar switches."
            entries = []
            return
        }
        status = "Loading the menu bar app list…"
        controller.driver.withAppRows { [weak self] rows in
            guard let self else { return }
            let tucked = Set(Preferences.tuckedApps)
            self.entries = rows.map { Entry(name: $0.name, tucked: tucked.contains($0.name), hiddenBySystem: !$0.isOn && !tucked.contains($0.name)) }
            self.status = rows.isEmpty
                ? "Couldn't read System Settings → Menu Bar. Open it once, then click Refresh."
                : "Checked apps disappear from the menu bar on every display. Click ‹ in the menu bar to peek."
        }
    }

    func setTucked(_ name: String, _ tucked: Bool) {
        var list = Preferences.tuckedApps
        if tucked { if !list.contains(name) { list.append(name) } } else { list.removeAll { $0 == name } }
        Preferences.tuckedApps = list
        if let i = entries.firstIndex(where: { $0.name == name }) { entries[i].tucked = tucked }
        controller?.didChangeTucked(name: name, tucked: tucked)
    }
}

struct ChooserView: View {
    @ObservedObject var model: ChooserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose icons to tuck away")
                .font(.title3.weight(.semibold))
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(model.entries) { entry in
                    HStack {
                        Toggle(entry.name, isOn: Binding(
                            get: { entry.tucked },
                            set: { model.setTucked(entry.name, $0) }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        if entry.hiddenBySystem {
                            Text("hidden in System Settings")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(minHeight: 340)
            HStack {
                Button("Refresh") { model.reload() }
                Spacer()
                Link("Support on Ko-fi ♥", destination: TuckController.supportURL)
                    .font(.callout)
                if !SettingsDriver.isTrusted {
                    Button("Grant Accessibility Access…") {
                        SettingsDriver.promptForTrust()
                        SettingsDriver.openAccessibilitySettings()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

@MainActor
final class ChooserWindowController: NSWindowController {
    private let model = ChooserModel()

    init(controller: TuckController) {
        model.controller = controller
        let host = NSHostingController(rootView: ChooserView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "Tuck"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        model.reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        model.reload()
    }
}
