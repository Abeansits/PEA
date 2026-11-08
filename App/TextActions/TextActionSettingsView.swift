import AppKit
import PEACore
import SwiftUI

struct TextActionSettingsView: View {
    @ObservedObject var prefs: Preferences

    @State private var canReadDirectly = SelectionReader.canReadDirectly
    @State private var canPostKeys = Paster.canPostEvents

    /// Keys another PEA shortcut already holds.
    private var reserved: [AppShortcut] {
        [prefs.historyShortcut, prefs.pasteShortcut, prefs.pasteShortcut.addingOption()]
            + WindowShortcut.letterShortcuts
    }

    var body: some View {
        Form {
            Section {
                Toggle("Text action shortcut", isOn: $prefs.textActionShortcutsEnabled)
                ShortcutField(title: "Show actions for the selection", shortcut: $prefs.textActionShortcut, reserved: reserved) {
                    prefs.isCapturingShortcut = $0
                }
                Text("Select text in any app, then press the shortcut. Click the shortcut to type a new one. It needs ⌘, ⌥, or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("The menu bar's Text Actions menu works with the shortcut off.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(TextAction.allCases, id: \.self) { action in
                    LabeledContent(action.menuTitle) {
                        Text(String(action.key).uppercased())
                            .font(.body.monospaced())
                    }
                }
                LabeledContent("Pick with the keyboard", value: "← →  ↩")
                LabeledContent("Close", value: "esc")
            } header: {
                Text("In the bar")
            } footer: {
                Text("Open Link shows up when the selection is a web or email address. Paste shows up when the clipboard has text. Case changes paste over the selection, so ⌘Z undoes them, and your clipboard is put back afterwards.")
                    .foregroundStyle(.secondary)
            }

            Section("Search") {
                Picker("Search with", selection: $prefs.searchEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
            }

            Section {
                LabeledContent("Reading selections") {
                    status(canReadDirectly) {
                        SelectionReader.requestDirectReading()
                        Paster.openAccessibilitySettings()
                    }
                }
                LabeledContent("Copy and paste keystrokes") {
                    status(canPostKeys) {
                        Paster.requestAccess()
                        Paster.openAccessibilitySettings()
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("With Accessibility allowed, PEA reads the selection directly and puts the bar next to it. Apps that don't answer (many browsers and Electron apps) get a ⌘C instead, and the bar opens at the pointer. PEA puts your clipboard back right after, and that copy never lands in history.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            canReadDirectly = SelectionReader.canReadDirectly
            canPostKeys = Paster.canPostEvents
        }
    }

    private func status(_ allowed: Bool, allow: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(allowed ? .green : .orange)
            Text(allowed ? "Allowed" : "Needs permission")
            if !allowed {
                Button("Allow…", action: allow)
            }
        }
    }
}
