import AppKit
import PEACore
import SwiftUI

@MainActor
final class TextActionTool: NSObject, PEATool {
    let id = "textActions"
    let title = "Text Actions"
    let settingsSymbol = "character.cursor.ibeam"
    let statusMenuTitle: String? = "Text Actions"

    private let prefs: Preferences
    private weak var clipboard: ClipboardAccess?
    private let reader: SelectionReader
    private let bar = ActionBarController()
    private var isReading = false

    /// Grouped the way the menu shows them. Copy and Paste are left out: the
    /// app's own Edit menu has them.
    private static let menuGroups: [[TextAction]] = [
        [.search, .openLink, .addToStack],
        [.uppercase, .lowercase, .titleCase],
    ]

    init(prefs: Preferences, clipboard: ClipboardAccess) {
        self.prefs = prefs
        self.clipboard = clipboard
        self.reader = SelectionReader(clipboard: clipboard)
        super.init()
    }

    func settingsView() -> AnyView {
        AnyView(TextActionSettingsView(prefs: prefs))
    }

    func installHotKeys(into center: HotKeyCenter) {
        guard prefs.textActionShortcutsEnabled else { return }
        let shortcut = prefs.textActionShortcut
        center.register(shortcut.character, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.toggleBar()
        }
    }

    func menuItems() -> [NSMenuItem] {
        let shortcut = prefs.textActionShortcut
        let show = NSMenuItem(
            title: "Show Actions for Selection",
            action: #selector(showBarFromMenu),
            keyEquivalent: prefs.textActionShortcutsEnabled ? shortcut.key : ""
        )
        show.keyEquivalentModifierMask = shortcut.modifierFlags
        show.target = self
        var items = [show]
        for group in Self.menuGroups {
            items.append(.separator())
            for action in group {
                let item = NSMenuItem(title: action.menuTitle, action: #selector(runFromMenu(_:)), keyEquivalent: "")
                item.representedObject = action.rawValue
                item.target = self
                items.append(item)
            }
        }
        return items
    }

    // MARK: Bar

    private func toggleBar() {
        if bar.isVisible {
            bar.close()
        } else {
            showBar()
        }
    }

    private func showBar() {
        guard !isReading else { return }
        isReading = true
        Task {
            let selection = await reader.read()
            isReading = false
            guard let selection else {
                NSSound.beep()
                return
            }
            // Checks the types only: reading a Universal Clipboard item would block.
            let canPaste = NSPasteboard.general.availableType(from: [.string]) != nil
            bar.show(
                TextAction.available(for: selection.text, canPaste: canPaste),
                stats: TextStats(selection.text).summary,
                anchor: selection.bounds
            ) { [weak self] action in
                self?.perform(action, on: selection.text)
            }
        }
    }

    private func perform(_ action: TextAction, on text: String) {
        switch action {
        case .copy:
            // A real ⌘C keeps the app's formatting and is recorded like any copy.
            afterFocusReturns { Paster.copy() }
        case .paste:
            afterFocusReturns { Paster.paste() }
        case .search:
            open(prefs.searchEngine.url(for: text))
        case .openLink:
            open(LinkDetector.url(in: text))
        case .addToStack:
            if clipboard?.addToStack(text) != true { NSSound.beep() }
        case .uppercase, .lowercase, .titleCase:
            guard let textCase = action.textCase else { return }
            let changed = textCase.apply(to: text)
            guard changed != text else { return }
            afterFocusReturns { [reader] in
                Task { await reader.replaceSelection(with: changed) }
            }
        }
    }

    private func open(_ url: URL?) {
        guard let url else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The bar had keyboard focus. Give the app a moment to get it back
    /// before sending it keystrokes.
    private func afterFocusReturns(_ work: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            work()
        }
    }

    // MARK: Menu

    @objc private func showBarFromMenu() {
        // Let the menu close and focus return to the previous app first.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            showBar()
        }
    }

    @objc private func runFromMenu(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? String).flatMap(TextAction.init(rawValue:)) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard let selection = await reader.read() else {
                NSSound.beep()
                return
            }
            perform(action, on: selection.text)
        }
    }
}
