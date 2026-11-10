import os

/// Unified logging. Clipboard contents are never logged.
enum Log {
    static let app = Logger(subsystem: "PEA", category: "app")
    static let sync = Logger(subsystem: "PEA", category: "sync")
    /// Why a selection or cursor click showed no strip. Roles and lengths
    /// only, never the text.
    static let textActions = Logger(subsystem: "PEA", category: "textActions")
}
