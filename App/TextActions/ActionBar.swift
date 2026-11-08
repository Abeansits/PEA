import AppKit
import Carbon.HIToolbox
import PEACore
import SwiftUI

/// The small bar of buttons next to a selection. It takes keyboard focus
/// without activating PEA (the same `FloatingPanel` as clipboard history),
/// so the app with the selection stays frontmost.
@MainActor
final class ActionBarController {
    private let panel = FloatingPanel()
    private let model: ActionBarModel
    private let host: NSHostingView<ActionBarView>
    private var keyMonitor: Any?
    private var onChoose: ((TextAction) -> Void)?

    var isVisible: Bool { panel.isVisible }

    init() {
        let model = ActionBarModel()
        self.model = model
        host = NSHostingView(rootView: ActionBarView(model: model, actions: [], stats: ""))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.layer?.cornerRadius = ActionBarView.cornerRadius
        host.layer?.masksToBounds = true
        panel.contentView = host
        panel.isMovableByWindowBackground = false
        panel.onResignKey = { [weak self] in self?.close() }
        model.choose = { [weak self] action in self?.choose(action) }
    }

    /// `anchor` is the selection's frame in AppKit screen coordinates. Nil
    /// puts the bar above the mouse pointer.
    func show(_ actions: [TextAction], stats: String, anchor: CGRect?, onChoose: @escaping (TextAction) -> Void) {
        guard !actions.isEmpty else { NSSound.beep(); return }
        self.onChoose = onChoose
        model.selection = 0
        model.actions = actions
        host.rootView = ActionBarView(model: model, actions: actions, stats: stats)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, anchor: anchor))
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func choose(_ action: TextAction) {
        let handler = onChoose
        onChoose = nil
        close()
        handler?(action)
    }

    private func origin(for size: CGSize, anchor: CGRect?) -> CGPoint {
        let target: CGRect
        if let anchor {
            target = anchor
        } else {
            // The I-beam pointer reaches about 10 pt above and below its hot spot.
            let mouse = NSEvent.mouseLocation
            target = CGRect(x: mouse.x, y: mouse.y - 10, width: 0, height: 20)
        }
        let center = CGPoint(x: target.midX, y: target.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(target) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return target.origin }
        return BarPlacement.origin(for: size, anchor: target, visibleFrame: visible)
    }

    // MARK: Keyboard

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
            if model.actions.indices.contains(model.selection) {
                choose(model.actions[model.selection])
            }
            return true
        default:
            break
        }
        guard mods.isEmpty,
              let typed = event.charactersIgnoringModifiers?.lowercased().first,
              let action = model.actions.first(where: { $0.key == typed })
        else { return false }
        choose(action)
        return true
    }

    private func move(_ offset: Int) {
        guard !model.actions.isEmpty else { return }
        model.selection = (model.selection + offset + model.actions.count) % model.actions.count
    }
}

@MainActor
final class ActionBarModel: ObservableObject {
    @Published var selection = 0
    var actions: [TextAction] = []
    var choose: (TextAction) -> Void = { _ in }
}

struct ActionBarView: View {
    static let cornerRadius: CGFloat = 10

    @ObservedObject var model: ActionBarModel
    let actions: [TextAction]
    let stats: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                ActionButton(action: action, isSelected: index == model.selection) {
                    model.choose(action)
                }
            }
            if !stats.isEmpty {
                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)
                Text(stats)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 6)
            }
        }
        .padding(4)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}

private struct ActionButton: View {
    let action: TextAction
    let isSelected: Bool
    let run: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 4) {
                if let symbol = action.symbol {
                    Image(systemName: symbol)
                }
                Text(action.title)
                Text(String(action.key).uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (hovered ? Color.primary.opacity(0.08) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(action.menuTitle)
    }
}

extension TextAction {
    /// SF Symbol on the bar's button. The case buttons show their label only.
    var symbol: String? {
        switch self {
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .search: "magnifyingglass"
        case .openLink: "arrow.up.right.square"
        case .addToStack: "square.stack.3d.up"
        case .uppercase, .lowercase, .titleCase: nil
        }
    }
}
