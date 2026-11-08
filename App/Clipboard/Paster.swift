import AppKit
import CoreGraphics

/// Sends ⌘V (and ⌘C and ⌘X, for text actions) to the frontmost app.
///
/// Those keystrokes need the PostEvent privilege (`CGPreflightPostEventAccess`).
/// It appears in the same Settings list as Accessibility, called Device
/// Control and Data Access on macOS 27. `AXIsProcessTrusted` is a different
/// check: it stays false for an ad-hoc app after that list is already on,
/// and prompting from it asks again on every paste.
enum Paster {
    private static var didRequestPostAccess = false

    static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Shows the system prompt that leads to System Settings.
    static func requestAccess() {
        didRequestPostAccess = true
        _ = CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The text is on the clipboard either way, so a manual ⌘V still works.
    /// A missing grant prompts at most once per launch; the keystroke is
    /// posted anyway, because macOS delivers it once that dialog is dismissed.
    @discardableResult
    static func paste() -> Bool {
        postCommandKey("v")
    }

    /// Sends ⌘C, for reading a selection the app won't hand over through
    /// Accessibility. Same permission and prompt as `paste()`.
    @discardableResult
    static func copy() -> Bool {
        postCommandKey("c")
    }

    /// Sends ⌘X, for the text actions bar's Cut.
    @discardableResult
    static func cut() -> Bool {
        postCommandKey("x")
    }

    private static func postCommandKey(_ character: Character) -> Bool {
        if !canPostEvents, !didRequestPostAccess {
            requestAccess()
        }
        guard let key = KeyboardLayout.keyCode(for: character) ?? KeyboardLayout.ansiKeyCode(for: character) else {
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        // Ignore the user's still-held ⇧ etc. while our keystroke goes through.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        return canPostEvents
    }
}
