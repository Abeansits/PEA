import AppKit
import ApplicationServices
import PEACore

/// What text actions need from the clipboard tool. Pasteboard changes PEA
/// makes on its own must not land in history.
@MainActor
protocol ClipboardAccess: AnyObject {
    /// Stop recording copies until `resumeRecording()`.
    func suspendRecording()
    /// Count whatever is on the pasteboard now as seen, then record again.
    func resumeRecording()
    /// Push onto the paste stack (and into history), like a copy would.
    /// False when the text is too large or blank.
    @discardableResult
    func addToStack(_ text: String) -> Bool
}

/// Text selected in the frontmost app.
struct TextSelection {
    let text: String
    /// Where the selection is on screen, in AppKit coordinates (y grows up
    /// from the bottom of the main screen). Nil when the app doesn't say.
    let bounds: CGRect?
    /// Whether the text can be changed in place. Nil when unknown (read with ⌘C).
    let isEditable: Bool?
}

/// Reads the frontmost app's selection, and pastes over it.
///
/// Accessibility (`AXSelectedText`) comes first: it doesn't touch the
/// clipboard, and it says where the selection is. Many browsers and Electron
/// apps don't answer it, so the fallback is a synthetic ⌘C. The clipboard is
/// put back right after, and neither change is recorded in history.
@MainActor
final class SelectionReader {
    private weak var clipboard: ClipboardAccess?
    private let pasteboard = NSPasteboard.general

    /// How long ⌘C gets to change the pasteboard before the selection counts as empty.
    private static let copyTimeout: Duration = .milliseconds(400)
    /// How long the app gets to read the pasteboard after ⌘V before the old
    /// clipboard comes back. Apps read it while handling the keystroke.
    private static let pasteSettle: Duration = .milliseconds(500)
    /// Marks PEA's short-lived pasteboard contents so other clipboard tools skip them too.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    nonisolated static var canReadDirectly: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings.
    nonisolated static func requestDirectReading() {
        // The value of kAXTrustedCheckOptionPrompt.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    init(clipboard: ClipboardAccess) {
        self.clipboard = clipboard
    }

    /// Nil when nothing is selected, the selection is only whitespace, or a
    /// password manager marked it concealed.
    func read() async -> TextSelection? {
        if let found = focusedSelection() { return found.selection }
        return await readWithCopy()
    }

    /// After a mouse gesture that usually selects text. Accessibility only:
    /// a ⌘C after every drag would copy files in Finder and shapes in
    /// drawing apps. `start` is where the gesture began, in AppKit
    /// coordinates. It must be inside the focused text element, so dragging
    /// a window by its title bar doesn't bring up an old selection.
    func readMouseSelection(startingAt start: CGPoint) -> TextSelection? {
        guard let found = focusedSelection() else { return nil }
        if let frame = Self.frame(of: found.element),
           let mainHeight = NSScreen.screens.first?.frame.height {
            let point = CGPoint(x: start.x, y: mainHeight - start.y)
            guard frame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        }
        return found.selection
    }

    /// Pastes `text` over the selection through the clipboard, which works
    /// in every app and leaves one undo step there. Then the clipboard
    /// comes back. Call it once the app has keyboard focus again.
    func replaceSelection(with text: String) async {
        clipboard?.suspendRecording()
        defer { clipboard?.resumeRecording() }
        let saved = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: Self.transientType)
        let written = pasteboard.changeCount
        Paster.paste()
        try? await Task.sleep(for: Self.pasteSettle)
        // Something else wrote to the pasteboard meanwhile: leave it.
        if pasteboard.changeCount == written {
            saved.restore(to: pasteboard)
        }
    }

    // MARK: Accessibility

    private struct FocusedSelection {
        let element: AXUIElement
        let selection: TextSelection
    }

    private func focusedSelection() -> FocusedSelection? {
        guard Self.canReadDirectly,
              let app = NSWorkspace.shared.frontmostApplication,
              // Asking our own process from the main thread would block it.
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app shouldn't freeze PEA. The timeout is per element.
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let focused = Self.copyElement(appElement, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.5)
        // An empty answer isn't trusted: browsers often report "" for a
        // selection in a web page. The ⌘C fallback settles it.
        guard let text = Self.copy(focused, kAXSelectedTextAttribute) as? String,
              !text.allSatisfy(\.isWhitespace)
        else { return nil }
        let selection = TextSelection(
            text: text,
            bounds: Self.selectionBounds(in: focused),
            isEditable: Self.isSettable(focused, kAXSelectedTextAttribute) || Self.isSettable(focused, kAXValueAttribute)
        )
        return FocusedSelection(element: focused, selection: selection)
    }

    /// The element's frame in Accessibility coordinates (y grows down from
    /// the top of the main screen).
    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = copy(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              let extent = copy(element, kAXSizeAttribute), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(extent as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private static func selectionBounds(in element: AXUIElement) -> CGRect? {
        guard let range = copy(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(range) == AXValueGetTypeID()
        else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value
        )
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0,
              // screens[0] holds the menu bar; both coordinate systems start there.
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        let bounds = WindowLayout.flipped(rect, mainScreenHeight: mainHeight)
        // Some apps answer with a rectangle that's on no screen.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(bounds) }) else { return nil }
        return bounds
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: ⌘C

    private func readWithCopy() async -> TextSelection? {
        clipboard?.suspendRecording()
        defer { clipboard?.resumeRecording() }
        let saved = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        Paster.copy()

        let deadline = ContinuousClock.now + Self.copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
        // Nothing selected: most apps leave the pasteboard alone.
        guard pasteboard.changeCount != before else { return nil }
        // The change count moves on clearContents; give the app a moment to finish writing.
        try? await Task.sleep(for: .milliseconds(30))

        let types = pasteboard.types?.map(\.rawValue) ?? []
        let text = SecretDetector.shouldIgnore(pasteboardTypes: types) ? nil : pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)
        guard let text, !text.allSatisfy(\.isWhitespace) else { return nil }
        return TextSelection(text: text, bounds: nil, isEditable: nil)
    }
}

/// Every item and type on the pasteboard, so it can be put back as it was.
private struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]
    private let canRestore: Bool

    private static let remoteClipboardType = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")

    init(_ pasteboard: NSPasteboard) {
        // Universal Clipboard from another device: reading it blocks while
        // it downloads. That one isn't saved, so it isn't restored either.
        if pasteboard.types?.contains(Self.remoteClipboardType) == true {
            items = []
            canRestore = false
            return
        }
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        canRestore = true
    }

    func restore(to pasteboard: NSPasteboard) {
        guard canRestore else { return }
        pasteboard.clearContents()
        let restored = items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
