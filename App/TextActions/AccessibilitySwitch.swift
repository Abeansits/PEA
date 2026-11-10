import AppKit
import ApplicationServices

/// Chromium browsers and Electron apps keep their Accessibility tree off
/// until an assistive app asks for it, so they report no selection to PEA.
/// This asks the way screen readers do, once per app process:
///
/// - Electron apps: `AXManualAccessibility`, which Electron added for
///   exactly this.
/// - Chromium browsers: `AXEnhancedUserInterface` as well, the flag
///   VoiceOver sets. It costs them some CPU, and some window tools animate
///   badly while it's on; PEA's own window mover turns it off for each move.
///
/// Turning the setting off turns the flags off again in the apps PEA
/// switched on.
@MainActor
final class AccessibilitySwitch {
    private enum Kind { case chromium, electron }

    private var switchedOn: [pid_t: Kind] = [:]
    private var observers: [NSObjectProtocol] = []

    /// Bundle ids of Chromium browsers. Electron apps are found by their framework.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta", "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    var isRunning: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app { self?.switchOn(app) }
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app { self?.switchedOn[app.processIdentifier] = nil }
            }
        })
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            switchOn(frontmost)
        }
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        for (pid, kind) in switchedOn {
            set(pid, kind, on: false)
        }
        switchedOn.removeAll()
    }

    private func switchOn(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard switchedOn[pid] == nil, AXIsProcessTrusted(), let kind = Self.kind(of: app) else { return }
        switchedOn[pid] = kind
        set(pid, kind, on: true)
        Log.textActions.debug("Switched on Accessibility in \(app.bundleIdentifier ?? "?", privacy: .public)")
    }

    private func set(_ pid: pid_t, _ kind: Kind, on: Bool) {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let value = on ? kCFBooleanTrue! : kCFBooleanFalse!
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, value)
        if kind == .chromium {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, value)
        }
    }

    private static func kind(of app: NSRunningApplication) -> Kind? {
        if let id = app.bundleIdentifier, chromiumBrowsers.contains(id) { return .chromium }
        guard let bundle = app.bundleURL else { return nil }
        let electron = bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: electron.path) ? .electron : nil
    }
}
