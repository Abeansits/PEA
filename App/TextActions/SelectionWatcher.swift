import AppKit

/// Watches the mouse in other apps for gestures that usually select text:
/// a drag, a double or triple click, a shift-click. It also reports what
/// should hide a bar that appeared on its own: a click, a key, a scroll,
/// another app coming to the front.
///
/// Global monitors see events going to other apps only, so clicks on PEA's
/// own bar never reach it. Mouse events need no permission; key events need
/// Accessibility, which reading the selection needs anyway.
@MainActor
final class SelectionWatcher {
    /// Both points in AppKit screen coordinates: where the gesture began and ended.
    var onSelectionGesture: ((_ start: CGPoint, _ end: CGPoint) -> Void)?
    var onInterruption: (() -> Void)?

    private var monitor: Any?
    private var appObserver: NSObjectProtocol?
    private var downPoint: CGPoint?
    private var dragged = false
    private var pending: Task<Void, Never>?

    /// Gives the app time to finish updating its selection after the mouse comes up.
    private static let settle: Duration = .milliseconds(120)
    /// Smaller moves are a shaky click, not a drag.
    private static let dragThreshold: CGFloat = 5

    func start() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        pending?.cancel()
        pending = nil
        downPoint = nil
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            downPoint = location
            dragged = false
            interrupt()
        case .leftMouseDragged:
            if let downPoint, hypot(location.x - downPoint.x, location.y - downPoint.y) >= Self.dragThreshold {
                dragged = true
            }
        case .leftMouseUp:
            guard let start = downPoint else { return }
            downPoint = nil
            guard dragged || event.clickCount >= 2 || event.modifierFlags.contains(.shift) else { return }
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled else { return }
                self?.onSelectionGesture?(start, location)
            }
        default:
            interrupt()
        }
    }

    private func interrupt() {
        pending?.cancel()
        pending = nil
        onInterruption?()
    }
}
