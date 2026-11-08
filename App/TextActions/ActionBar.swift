import AppKit
import Carbon.HIToolbox
import PEACore

/// One segment of the bar.
enum BarItem: Equatable {
    case action(TextAction)
    /// "Aa": swaps in UPPERCASE, lowercase and Title Case.
    case caseMenu
    /// "#": swaps in the word and character counts.
    case count
    /// Plain text, like the counts. Clicking it closes the bar.
    case message(String)

    var isButton: Bool {
        if case .message = self { return false }
        return true
    }
}

/// The small dark strip above a selection.
///
/// It can appear in two ways. After a mouse selection it shows without
/// keyboard focus, so typing still goes to the app, and clicks on it don't
/// take focus either. After the shortcut it takes keyboard focus (without
/// activating PEA, like clipboard history) so letters and arrows work.
@MainActor
final class ActionBarController {
    private let panel = FloatingPanel()
    private let strip = ActionBarView()
    private var keyMonitor: Any?
    private var actions: [TextAction] = []
    private var stats = ""
    private var onChoose: ((TextAction) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var hasKeyboardFocus: Bool { panel.isKeyWindow }

    init() {
        panel.contentView = strip
        panel.isMovableByWindowBackground = false
        // Clicking a segment doesn't make the panel key, so the app with the
        // selection keeps keyboard focus. The shortcut makes it key on purpose.
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.onResignKey = { [weak self] in self?.close() }
        strip.onClick = { [weak self] index in self?.activate(index) }
    }

    /// `anchor` is what the bar sits above, in AppKit screen coordinates.
    func show(
        _ actions: [TextAction], stats: String, anchor: CGRect, focus: Bool,
        onChoose: @escaping (TextAction) -> Void
    ) {
        guard !actions.isEmpty else { NSSound.beep(); return }
        self.actions = actions
        self.stats = stats
        self.onChoose = onChoose
        strip.items = Self.mainRow(for: actions)
        strip.highlighted = focus ? 0 : nil
        let size = strip.intrinsicContentSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, anchor: anchor))
        panel.invalidateShadow()
        if focus {
            panel.makeKeyAndOrderFront(nil)
            installKeyMonitor()
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Gives a bar that appeared on its own keyboard focus.
    func focus() {
        guard panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        if strip.highlighted == nil {
            strip.highlighted = strip.items.firstIndex(where: \.isButton)
        }
    }

    func close() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Case changes fold into one "Aa" segment; "#" goes last.
    private static func mainRow(for actions: [TextAction]) -> [BarItem] {
        var items: [BarItem] = []
        for action in actions {
            if action.textCase != nil {
                if !items.contains(.caseMenu) { items.append(.caseMenu) }
            } else {
                items.append(.action(action))
            }
        }
        items.append(.count)
        return items
    }

    private func activate(_ index: Int) {
        guard strip.items.indices.contains(index) else { return }
        switch strip.items[index] {
        case .action(let action):
            choose(action)
        case .caseMenu:
            swapRow(actions.filter { $0.textCase != nil }.map(BarItem.action))
        case .count:
            swapRow([.message(stats)])
        case .message:
            close()
        }
    }

    private func choose(_ action: TextAction) {
        let handler = onChoose
        onChoose = nil
        close()
        handler?(action)
    }

    /// Replaces the segments in place, keeping the bar centered where it was.
    private func swapRow(_ items: [BarItem]) {
        let midX = panel.frame.midX
        strip.items = items
        strip.highlighted = hasKeyboardFocus ? items.firstIndex(where: \.isButton) : nil
        let size = strip.intrinsicContentSize
        var frame = CGRect(x: (midX - size.width / 2).rounded(), y: panel.frame.minY, width: size.width, height: size.height)
        if let visible = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 4), visible.maxX - 4 - size.width)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func origin(for size: CGSize, anchor: CGRect) -> CGPoint {
        let center = CGPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return anchor.origin }
        return BarPlacement.origin(for: size, anchor: anchor, visibleFrame: visible, gap: 6)
    }

    // MARK: Keyboard (only after the shortcut)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        let shift = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
            return true
        case kVK_ANSI_W where mods == .command:
            close()
            return true
        case kVK_LeftArrow where mods.isEmpty:
            move(-1)
            return true
        case kVK_RightArrow where mods.isEmpty:
            move(1)
            return true
        case kVK_Tab where mods.isEmpty:
            move(shift ? -1 : 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            if let index = strip.highlighted { activate(index) } else { close() }
            return true
        default:
            break
        }
        // Letters reach every action, including the case changes behind "Aa".
        guard mods.isEmpty,
              let typed = event.charactersIgnoringModifiers?.lowercased().first,
              let action = actions.first(where: { $0.key == typed })
        else { return false }
        choose(action)
        return true
    }

    private func move(_ offset: Int) {
        let buttons = strip.items.indices.filter { strip.items[$0].isButton }
        guard !buttons.isEmpty else { return }
        let current = strip.highlighted.flatMap { buttons.firstIndex(of: $0) } ?? (offset > 0 ? -1 : 0)
        strip.highlighted = buttons[(current + offset + buttons.count) % buttons.count]
    }
}

/// Draws the segments and handles the mouse. Plain AppKit, so the size is
/// exact, hover works while PEA isn't the active app, and the first click
/// counts.
final class ActionBarView: NSView, NSViewToolTipOwner {
    var items: [BarItem] = [] {
        didSet {
            hovered = nil
            pressed = nil
            layoutSegments()
        }
    }
    /// The keyboard highlight.
    var highlighted: Int? {
        didSet { needsDisplay = true }
    }
    var onClick: ((Int) -> Void)?

    private struct Segment {
        let item: BarItem
        let content: Content
        let frame: CGRect
    }

    private enum Content {
        case text(NSAttributedString)
        case image(NSImage)
    }

    private var segments: [Segment] = []
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed: Int? { didSet { if pressed != oldValue { needsDisplay = true } } }

    private static let height: CGFloat = 28
    private static let padding: CGFloat = 9
    private static let radius: CGFloat = 7
    private static let background = NSColor(white: 0.11, alpha: 0.94)
    private static let border = NSColor(white: 1, alpha: 0.12)

    override var intrinsicContentSize: NSSize {
        NSSize(width: segments.last?.frame.maxX ?? 0, height: Self.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func layoutSegments() {
        var x: CGFloat = 0
        segments = items.map { item in
            let content = Self.content(for: item)
            let width: CGFloat
            switch content {
            case .text(let string): width = ceil(string.size().width)
            case .image(let image): width = image.size.width
            }
            let segmentWidth = max(Self.height, width + Self.padding * 2)
            defer { x += segmentWidth }
            return Segment(item: item, content: content, frame: CGRect(x: x, y: 0, width: segmentWidth, height: Self.height))
        }
        removeAllToolTips()
        for segment in segments where segment.item.isButton {
            _ = addToolTip(segment.frame, owner: self, userData: nil)
        }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private static func content(for item: BarItem) -> Content {
        switch item {
        case .action(let action):
            if let symbol = action.symbol, let image = symbolImage(symbol) { return .image(image) }
            return .text(label(action.title))
        case .caseMenu:
            return .text(label("Aa"))
        case .count:
            if let image = symbolImage("number") { return .image(image) }
            return .text(label("#"))
        case .message(let text):
            return .text(label(text, color: NSColor(white: 1, alpha: 0.8), size: 12))
        }
    }

    private static func label(_ text: String, color: NSColor = .white, size: CGFloat = 13) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: color,
        ])
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius)
        Self.background.setFill()
        shape.fill()

        if let index = pressed ?? hovered ?? highlighted,
           segments.indices.contains(index), segments[index].item.isButton {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor.controlAccentColor.setFill()
            segments[index].frame.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        for segment in segments {
            switch segment.content {
            case .text(let string):
                let size = string.size()
                string.draw(at: CGPoint(
                    x: segment.frame.midX - size.width / 2,
                    y: segment.frame.midY - size.height / 2
                ))
            case .image(let image):
                let size = image.size
                image.draw(in: CGRect(
                    x: (segment.frame.midX - size.width / 2).rounded(),
                    y: (segment.frame.midY - size.height / 2).rounded(),
                    width: size.width, height: size.height
                ))
            }
        }

        Self.border.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius - 0.5, yRadius: Self.radius - 0.5)
        outline.lineWidth = 1
        outline.stroke()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    private func segmentIndex(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return segments.firstIndex { $0.frame.contains(point) }
    }

    override func mouseEntered(with event: NSEvent) { hovered = segmentIndex(at: event) }
    override func mouseMoved(with event: NSEvent) { hovered = segmentIndex(at: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        pressed = segmentIndex(at: event)
    }

    override func mouseDragged(with event: NSEvent) {
        hovered = segmentIndex(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        let index = segmentIndex(at: event)
        let wasPressed = pressed
        pressed = nil
        if let index, index == wasPressed {
            onClick?(index)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let segment = segments.first(where: { $0.frame.contains(point) }) else { return "" }
        switch segment.item {
        case .action(let action): return action.menuTitle
        case .caseMenu: return "Change Case"
        case .count: return "Count Words"
        case .message: return ""
        }
    }
}

extension TextAction {
    /// Shown as an icon on the bar. Nil: shown as its title.
    var symbol: String? {
        switch self {
        case .search: "magnifyingglass"
        case .openLink: "arrow.up.right.square"
        case .addToStack: "square.stack.3d.up"
        case .cut, .copy, .paste, .uppercase, .lowercase, .titleCase: nil
        }
    }
}
