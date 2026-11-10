import AppKit
import Combine
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
    private let watcher = SelectionWatcher()
    private let accessibilitySwitch = AccessibilitySwitch()
    private var isReading = false
    private var cancellables: Set<AnyCancellable> = []
    /// Where the last plain click left the insertion point. A second click
    /// on the same spot shows Paste and Select All, like tapping the cursor
    /// on iOS.
    private var lastCaret: Caret?
    /// The last plain click, to tell when someone is trying the cursor
    /// strip (a second click on the same spot) and log why it didn't show.
    private var lastClick: (point: CGPoint, time: Date)?

    /// A selection taller than this spans lines; the bar then goes by the
    /// pointer instead of above the whole block.
    private static let singleLineHeight: CGFloat = 40

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

    /// Called by the host after launch. Watches mouse selections while
    /// "Show when you select text" is on.
    func start() {
        watcher.onSelectionGesture = { [weak self] start, end in
            self?.handleSelectionGesture(start: start, end: end)
        }
        watcher.onPlainClick = { [weak self] point in
            self?.handlePlainClick(at: point)
        }
        watcher.onInterruption = { [weak self] in self?.bar.close() }
        prefs.$textActionsShowOnSelect
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                if on {
                    self.watcher.start()
                } else {
                    self.watcher.stop()
                    self.bar.close()
                }
            }
            .store(in: &cancellables)
        Publishers.CombineLatest(prefs.$textActionsShowOnSelect, prefs.$textActionsSwitchOnApps)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                if on {
                    self.accessibilitySwitch.start()
                } else {
                    self.accessibilitySwitch.stop()
                }
            }
            .store(in: &cancellables)
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

    /// The shortcut: focuses a bar that appeared on its own, closes a
    /// focused one, or reads the selection and opens one with focus.
    private func toggleBar() {
        if bar.isVisible {
            if bar.hasKeyboardFocus {
                bar.close()
            } else {
                bar.focus()
            }
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
            present(selection, anchor: selection.bounds ?? Self.pointerAnchor(NSEvent.mouseLocation), focus: true)
        }
    }

    /// A drag, double-click or shift-click just ended in another app. Quiet
    /// on purpose: most of those aren't text selections, so nothing beeps.
    private func handleSelectionGesture(start: CGPoint, end: CGPoint) {
        lastCaret = nil
        guard prefs.textActionsShowOnSelect, !bar.isVisible, !isReading else { return }
        guard let selection = reader.readMouseSelection(startingAt: start) else {
            Log.textActions.debug("No strip after a selection: \(self.reader.diagnose(at: start), privacy: .public)")
            return
        }
        let anchor: CGRect
        if let bounds = selection.bounds, bounds.height <= Self.singleLineHeight {
            anchor = bounds
        } else {
            anchor = Self.pointerAnchor(end)
        }
        present(selection, anchor: anchor, focus: false)
    }

    /// A click that didn't select anything. The first one on a spot only
    /// remembers the insertion point; a second one there (after a pause, or
    /// it would be a double-click) shows the strip. The click after that
    /// hides it again and starts over.
    private func handlePlainClick(at point: CGPoint) {
        guard prefs.textActionsShowOnSelect, !bar.isVisible, !isReading else { return }
        let previous = lastClick
        lastClick = (point, Date())
        let isRetry = previous.map { hypot($0.point.x - point.x, $0.point.y - point.y) < 6 && -$0.time.timeIntervalSinceNow < 3 } ?? false
        guard let caret = reader.readCaret(clickedAt: point) else {
            if isRetry {
                Log.textActions.debug("No cursor found on a second click: \(self.reader.diagnose(at: point), privacy: .public)")
            }
            lastCaret = nil
            return
        }
        guard let last = lastCaret, caret.isSamePlace(as: last) else {
            if isRetry, lastCaret != nil {
                Log.textActions.debug("Second click didn't match the first cursor: \(self.reader.diagnose(at: point), privacy: .public)")
            }
            lastCaret = caret
            return
        }
        lastCaret = nil
        let anchor = caret.bounds ?? Self.pointerAnchor(point)
        // Checks the types only: reading a Universal Clipboard item would block.
        let canPaste = NSPasteboard.general.availableType(from: [.string]) != nil
        bar.show(TextAction.availableAtCaret(canPaste: canPaste), stats: nil, anchor: anchor, focus: false) { [weak self] action in
            self?.perform(action, on: "")
        }
    }

    private func present(_ selection: TextSelection, anchor: CGRect, focus: Bool) {
        // Checks the types only: reading a Universal Clipboard item would block.
        let canPaste = NSPasteboard.general.availableType(from: [.string]) != nil
        bar.show(
            TextAction.available(for: selection.text, canPaste: canPaste, isEditable: selection.isEditable),
            stats: TextStats(selection.text).summary,
            anchor: anchor,
            focus: focus
        ) { [weak self] action in
            self?.perform(action, on: selection.text)
        }
    }

    /// The I-beam pointer reaches about 10 pt above and below its hot spot.
    private static func pointerAnchor(_ point: CGPoint) -> CGRect {
        CGRect(x: point.x, y: point.y - 10, width: 0, height: 20)
    }

    private func perform(_ action: TextAction, on text: String) {
        switch action {
        case .cut:
            afterFocusReturns { Paster.cut() }
        case .copy:
            // A real ⌘C keeps the app's formatting and is recorded like any copy.
            afterFocusReturns { Paster.copy() }
        case .paste:
            afterFocusReturns { Paster.paste() }
        case .selectAll:
            afterFocusReturns { Paster.selectAll() }
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
