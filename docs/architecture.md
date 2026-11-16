# PEA architecture

This is the contract for the in-process shell. The host currently ships three tools. Adding another one follows [the roadmap](ROADMAP.md#adding-a-tool).

PEA is one AppKit process. `main.swift` sets `NSApplication` activation policy `.accessory` (menu bar only, no Dock icon), installs `AppDelegate`, and turns `SIGTERM` into `NSApp.terminate(nil)` so a quit from `make install` still runs `applicationWillTerminate`. Tools are types in that process. They are not plugins, bundles, XPC services, or scripts.

## Public identity

The product, the menu-bar app, the Xcode target, and `PRODUCT_NAME` are PEA. The Swift package is `PEACore`. XcodeGen writes `PEA.xcodeproj`, which `.gitignore` ignores. Do not commit it. The GitHub repository is `Abeansits/PEA`.

## Shipped tools

The host's tool list is exactly this, in this order:

1. Clipboard
2. Windows
3. Text Actions

Clipboard is history, the paste stack, secret filtering, and iCloud sync. Windows is the Magnet-style mover. Text Actions is the PopClip-shaped tool: a bar of actions for the selected text. Its behavior is in [docs/specs/text-actions.md](specs/text-actions.md).

## `PEATool`

`App/Shell/PEATool.swift`. One `@MainActor` protocol, `PEATool: AnyObject`. No associated types. The host stores `[any PEATool]`.

```swift
@MainActor
protocol PEATool: AnyObject {
    var id: String { get }
    var title: String { get }
    /// SF Symbol name on the Settings toolbar tab.
    var settingsSymbol: String { get }
    /// Non-nil: this tool's items go in a status-menu submenu with this title.
    /// Nil: the items sit on the root status menu.
    var statusMenuTitle: String? { get }
    func settingsView() -> AnyView
    /// Register this tool's Carbon hot keys. Register nothing when its own shortcut switch is off.
    /// Must not call `HotKeyCenter.unregisterAll()`.
    func installHotKeys(into center: HotKeyCenter)
    /// Items for the status menu. The tool sets `target` on each actionable item.
    /// Rebuild every call; do not cache them.
    func menuItems() -> [NSMenuItem]
}
```

Nothing else goes on the protocol. Startup, quit, remote notifications, and the status-item text are clipboard work. The host calls them on the concrete `ClipboardTool`, not through `PEATool`. The one other lifecycle call is `TextActionTool.start()`, also on the concrete type.

| Tool | Type | `id` | `title` | `settingsSymbol` | `statusMenuTitle` |
|---|---|---|---|---|---|
| Clipboard | `ClipboardTool` | `clipboard` | `Clipboard` | `doc.on.clipboard` | `nil` |
| Windows | `WindowTool` | `windows` | `Windows` | `rectangle.split.2x1` | `Move Window` |
| Text Actions | `TextActionTool` | `textActions` | `Text Actions` | `character.cursor.ibeam` | `Text Actions` |

All three are `@MainActor final class …: NSObject, PEATool`, so they can be `NSMenuItem` targets. They live in the app target, not in `PEACore`.

## `PEAHost`

`App/Shell/PEAHost.swift`. `@MainActor final class PEAHost: NSObject, NSMenuDelegate`.

The host owns the tool list. It creates the tools with `Preferences.shared` (the type's `init` is private; do not construct another `Preferences`). `TextActionTool` also gets the clipboard tool, as a `ClipboardAccess` (see [Text Actions and the clipboard](#text-actions-and-the-clipboard)):

```swift
let clipboard: ClipboardTool
let windows: WindowTool
let textActions: TextActionTool
let tools: [any PEATool]   // [clipboard, windows, textActions]
let hotKeys = HotKeyCenter()
```

`tools` is that array literal. Do not sort it, do not load it from a plist, and do not discover tools by scanning the bundle.

`AppDelegate` owns the process: the status item, application lifecycle, and this host. It does not construct window actions or paste commands. It does not reference `HistoryModel`, `CloudSync`, `PasteboardMonitor`, `StackPanelController`, `Paster`, `WindowManager`, `WindowAction`, `WindowShortcut`, `SelectionReader`, or `ActionBarController`.

What the host does:

- `start()` calls `clipboard.start()`, then `textActions.start()` (which starts the mouse-selection watcher while `textActionsShowOnSelect` is on), then `bindHotKeys()`, then starts observing preferences.
- `prepareForTermination()` calls `clipboard.prepareForTermination()` only. Windows has nothing to save.
- `handleRemoteNotification()` calls `clipboard.handleRemoteNotification()` only.
- `bindHotKeys()` is the only caller of `hotKeys.unregisterAll()`. If `prefs.isCapturingShortcut` is true, it returns after that. Otherwise it calls `clipboard.installHotKeys(into:)`, then `windows.installHotKeys(into:)`, then `textActions.installHotKeys(into:)`.
- `menuNeedsUpdate(_:)` rebuilds the status menu. `AppDelegate` sets the status item's menu delegate to the host.

`HotKeyCenter.unregisterAll()` does not reset `nextID`. `reregisterAll()` installs in sorted id order, so the first `register` after each `unregisterAll` keeps the lower id. Carbon `RegisterEventHotKey` gives the first registration the key. Tools are installed in tool-list order for that reason: on shared keys Clipboard beats Windows, and both beat Text Actions. Tools register only their own keys. `ShortcutField` takes a `reserved` list and beeps at a shortcut another PEA shortcut holds, so the overlap takes effort.

Rebind on the next main-queue turn after `Preferences.objectWillChange` or `prefs.$isCapturingShortcut`, because `@Published` fires before the new value is stored. `receive(on: RunLoop.main)`, then `bindHotKeys()`. `ShortcutField` in `App/Shortcut.swift` sets `isCapturingShortcut`. While it is true, every global shortcut, including Windows, stays unregistered.

## Status menu

`menuNeedsUpdate` builds this, top to bottom:

1. Every tool whose `statusMenuTitle` is nil, in tool-list order. Today that is only Clipboard: append `clipboard.menuItems()` directly, including the separator the tool returns.
2. A separator.
3. Every tool whose `statusMenuTitle` is non-nil, in tool-list order. The parent item's title is `statusMenuTitle`, its action is nil, and its submenu is that tool's `menuItems()`.
4. A separator.
5. `Settings…` (`keyEquivalent` `","`, target `AppDelegate`) and `Quit PEA` (`keyEquivalent` `"q"`, target `AppDelegate`).

The host does not retarget tool items. Separators stay separators.

Clipboard's `menuItems()`:

| Item | Action | Enabled when | Key equivalent |
|---|---|---|---|
| Show History | `StackPanelController.show()` (not `toggle`) | always | `historyShortcut` |
| Paste Next | `pasteAndPop()` after 0.15 s | stack is non-empty; title uses `preview(maxLength: 48)` when there is a next item | `pasteShortcut` |
| Paste Next with Style | `pasteAndPop(rich: true)` after 0.15 s | stack non-empty, next item `hasRichText`, and `pasteShortcut.addingOption() != pasteShortcut` | `pasteShortcut.addingOption()` |
| Clear Stack | `model.clearStack()` | stack non-empty | none |
| separator | | | |
| Pause Recording | `recordingPaused.toggle()`, checkmark follows the flag | always | none |
| Clear History… | the existing `NSAlert` (iCloud wording when `syncEnabled`) | always | none |

The show-history hot key calls `StackPanelController.toggle()`. The menu item calls `show()`. Keep the 0.15 s menu delay and the 0.05 s history-panel delay.

When `clipboardShortcutsEnabled` is false, those three items stay in the menu and keep their actions. Their `keyEquivalent` is `""`. Still assign `keyEquivalentModifierMask` from the shortcut, as Windows does when its shortcuts are off.

Windows' `menuItems()`: `WindowShortcut.groups` in order, a separator between groups, `representedObject` = `action.rawValue`, action calls `WindowManager.perform`. `keyEquivalent` is `shortcut.keyEquivalent` when `windowShortcutsEnabled` is true and `""` otherwise.

Text Actions' `menuItems()`: Show Actions for Selection (`keyEquivalent` from `textActionShortcut` when `textActionShortcutsEnabled`, `""` otherwise, modifier mask always assigned), then two groups after separators: Search the Web, Open Link, Add to Paste Stack; Make UPPERCASE, Make lowercase, Make Title Case. Each waits 0.15 s for the menu to close, then reads the selection. `representedObject` is `TextAction.rawValue`.

## Status item

The status item is the SF Symbol `paperclip`, accessibility description `PEA`, `imagePosition` `.imageLeading`. A generic template icon is not a substitute: the button title is the paste-stack count (`" \(count)"` when the stack is non-empty, otherwise `""`).

`ClipboardTool.statusAppearance()` returns the title, the tooltip, and `appearsDisabled`. Tooltip text is `"Next: \(next.preview(maxLength: 80))"` or `"Nothing waiting to paste"`. `appearsDisabled` follows `recordingPaused`. The symbol is shell policy, not a `PEATool` property. `AppDelegate` applies the appearance to the button. `ClipboardTool.onStatusChange` fires when `HistoryModel.$history`, `pasteOrder`, or `recordingPaused` changes. `AppDelegate` sets that callback before `host.start()`.

## Lifecycle

`AppDelegate.applicationDidFinishLaunching`: create the status item, wire `onStatusChange`, call `host.start()`, then `NSApp.registerForRemoteNotifications()`. Registration is on the delegate because it is an `NSApp` call.

`ClipboardTool.start()`:

- `model.onDelta` enqueues into `CloudSync`.
- `PasteboardMonitor.onCopy` records through the same `handleCopy` rules (`recordingPaused`, `ignoredApps`, `SecretDetector`, `secretHandling`, `secretTTL`).
- `monitor.start()`.
- If `syncEnabled`, `sync.start()`.
- If `!Paster.canPostEvents && !prefs.didPromptForAccessibility`, set the flag and call `Paster.requestAccess()`.
- Observe `syncEnabled`, `historyLimit` (drop-first, deduped, 500 ms debounce, `setCapacity`), `forgetAfterDays` (purge on the next turn), `recordingPaused`, and `pasteOrder`.

`applicationWillTerminate` calls `host.prepareForTermination()`, which calls `model.saveNow()` and then `sync.saveMetadataNow()`, in that order.

`application(_:didReceiveRemoteNotification:)` calls `host.handleRemoteNotification()`, which calls `CloudSync.syncNow()`. `syncNow()` already no-ops when the engine is nil.

The window Accessibility prompt lives inside `WindowManager.perform` (once a launch, then beep). Do not prompt for it at launch.

## Settings

The settings window is the toolbar-tab window in `App/Shell/SettingsWindow.swift`.

```swift
enum SettingsWindow {
    static func make(tools: [any PEATool]) -> NSWindow
}
```

It is an `NSTabViewController` with `tabStyle` `.toolbar`, `styleMask` `[.titled, .closable]`, `toolbarStyle` `.preference`, `isReleasedWhenClosed` false, centered. Each tab is an `NSHostingController` with `sizingOptions` `.preferredContentSize`, the tool's `title`, and `NSImage(systemSymbolName: tool.settingsSymbol)`.

Tab order is `tools`, then General. General is not a `PEATool`. Its symbol is `gearshape`, its label is `General`, and its view is `GeneralSettingsView` in `App/Shell/GeneralSettingsView.swift` (launch at login via `SMAppService.mainApp`, and the About block that reads `CFBundleShortVersionString`).

`AppDelegate` holds the `NSWindow?` and builds it lazily with `SettingsWindow.make(tools: host.tools)`. It does not construct a clipboard or windows view itself.

`ClipboardSettingsView` and the private `IgnoredAppsEditor` live in `App/Clipboard/ClipboardSettingsView.swift`. The tool's `settingsView()` returns `AnyView` of that view, observing `Preferences` and `CloudSync`, with the clear-history alert invoked through a closure the tool supplies.

The Clipboard Shortcuts section starts with:

```swift
Toggle("Clipboard shortcuts", isOn: $prefs.clipboardShortcutsEnabled)
```

Its footer says the menu bar's history and paste items work with the shortcuts off. Pause recording stays in the History section. It is not this switch.

`WindowSettingsView` is in `App/Windows/WindowSettingsView.swift`. `WindowTool.settingsView()` wraps it.

## Preferences

`App/Preferences.swift` is the only `ObservableObject` and the only `UserDefaults` facade. Tools add keys there. Do not split defaults across files, and do not give a tool its own `UserDefaults` suite.

Text Actions adds `textActionsShowOnSelect` (default `true`: show the bar after a mouse selection or a second click on the cursor), `textActionsSwitchOnApps` (default `true`: turn on Accessibility in Chromium browsers and Electron apps), `textActionShortcutsEnabled` (default `true`, parallel to the other two switches), `textActionShortcut` (an `AppShortcut` stored as JSON like the clipboard shortcuts, default `.textActions` = ⌃⌥A), and `searchEngine` (a `SearchEngine` raw value, default `duckDuckGo`).

Every tool has its own shortcut switch: `clipboardShortcutsEnabled`, `windowShortcutsEnabled`, and `textActionShortcutsEnabled`. Each is a `@Published` bool whose `didSet` writes it, registered with a default of `true` and read in `init` with `defaults.bool(forKey:)`. A new key follows the same pattern, so a settings domain that predates it gets the default. Do not rename existing keys; that would reset them. Pause recording (`recordingPaused`) is not a shortcut switch.

## Hot keys per tool

`ClipboardTool.installHotKeys` returns immediately when `clipboardShortcutsEnabled` is false. Otherwise it registers, in this order:

1. `historyShortcut` → `panel.toggle()`
2. `pasteShortcut` → `pasteAndPop()`
3. `pasteShortcut.addingOption()`, only when that differs from `pasteShortcut` → `pasteAndPop(rich: true)`

`WindowTool.installHotKeys` returns immediately when `windowShortcutsEnabled` is false. Otherwise it registers `WindowShortcut.all` in order, each calling `windows.perform(shortcut.action)`.

`TextActionTool.installHotKeys` returns immediately when `textActionShortcutsEnabled` is false. Otherwise it registers `textActionShortcut`, which toggles the action bar.

## Text Actions and the clipboard

Text Actions reads a selection with ⌘C when Accessibility doesn't answer, and changes case by pasting over the selection. Both write the general pasteboard. Those writes must not land in history, so the tool talks to the clipboard through one small protocol, declared in `App/TextActions/SelectionReader.swift`:

```swift
@MainActor
protocol ClipboardAccess: AnyObject {
    func suspendRecording()
    func resumeRecording()
    @discardableResult func addToStack(_ text: String) -> Bool
}
```

`ClipboardTool` implements it in an extension. `suspendRecording()` polls once (so a real copy from the last half second is kept), then calls `PasteboardMonitor.suspend()`, which makes `poll()` return early. `resumeRecording()` calls `resume()`, which marks the current change count as seen. Suspensions nest. `addToStack` records through the same secret rules as a copy, but ignores Pause Recording and the ignore list, and refuses text over `PasteboardMonitor.maxBytes`.

`TextActionTool` holds the clipboard weakly and never sees `HistoryModel` or `PasteboardMonitor`. `Paster` gained `copy()` next to `paste()`; both post through the same keystroke code.

`HotKeyCenter`, `HotKey`, and `KeyboardLayout` are in `App/HotKeys.swift`. `AppShortcut` and `ShortcutField` are in `App/Shortcut.swift`.

## Clipboard and Windows code

`ClipboardTool` owns `HistoryModel`, `CloudSync`, `PasteboardMonitor`, `StackPanelController`, and every paste path (`handleCopy`, `pasteAndPop`, `pick`). Those types live in `App/Clipboard/`. History is stored in `HistoryModel.supportDirectory`, `~/Library/Application Support/PEA`.

`WindowTool` owns `WindowManager` and the menu actions. `WindowManager`, `WindowShortcuts`, and `WindowSettingsView` are in `App/Windows/`.

## Two-line history list preview

`ClipItem.listPreview` is in `Core/Sources/PEACore/ClipItem.swift`. `testListPreviewKeepsTwoLines` covers it. `Row` in `App/Clipboard/StackPanel.swift` draws it.

`ClipItem.listPreview(maxLines: Int = 2) -> String`:

- A sensitive item returns `preview()` and does not show its text.
- Normalize line breaks before splitting: replace `\r\n` with `\n`, then `\r` with `\n`, then U+2028 and U+2029 with `\n`. Do it in that order.
- Split on `\n`, keeping empty subsequences. Each piece: tabs become spaces, then trim `.whitespaces`. Drop empty pieces.
- Keep at most `maxLines` pieces. A further non-empty piece does not become a third line. Append `…` (U+2026, not three periods) to the last kept line.
- Join kept lines with `\n`. If none remain, return `preview()`.
- This is display-only. Do not rewrite `text`.

`preview` is for the menu and the tooltip. The status item and Paste Next call `preview`, not `listPreview`.

`Row` in `StackPanel.swift` draws every item, sensitive or not, from `listPreview()`. Split that string on `\n` and put each piece in its own `Text` with `lineLimit(1)` and `truncationMode(.tail)`. The column frame is `minWidth: 0`, `maxWidth: .infinity`, `alignment: .leading`. Do not use one `Text` with `lineLimit(2)` or `fixedSize`: that sizes the row to the unwrapped string, then the wrapped lines paint over the next row.

`testListPreviewKeepsTwoLines` sits next to `testPreviewCollapsesWhitespaceAndMasksSecrets` and checks:

- `"  hello\n\n  world\t!  "` → `"hello\nworld !"`
- `"a\r\nb\rc"` → `"a\nb…"`
- `"only"` → `"only"`
- sensitive `"secret\nline"` equals that item's `preview()`

## Version

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `project.yml`. `Config/Info.plist` reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Do not hard-code them there.

1.2.0 added Text Actions. 1.1.0 added the tool shell and the clipboard shortcut switch. `project.yml` `sources` is the whole `App` directory, so a new folder under `App/` needs no source entry. There is one app target. Do not add another.

## CI and local proof

`.github/workflows/ci.yml` has two jobs. `build`, on `macos-15`, runs after checkout:

1. `cd Core && swift test`
2. `brew install xcodegen && xcodegen generate`
3. Unsigned Debug `xcodebuild` of `PEA.xcodeproj` / scheme `PEA`, `-derivedDataPath build`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGN_ENTITLEMENTS=` empty
4. `make install PREFIX="$RUNNER_TEMP/Applications" OPEN=0`

`core-linux` runs on `ubuntu-24.04` (`setup-swift@v2` rejects the 26.04 image that `ubuntu-latest` now points to). It checks out, runs `swift-actions/setup-swift@v2` with `swift-version: "6.0"`, then `cd Core && swift test`. It does not install XcodeGen and it does not build the app. The job exists so `PEACore` stays free of AppKit, UIKit, and CloudKit. `Core/Package.swift` is `swift-tools-version:5.9` and `platforms: [.macOS(.v14)]`. Do not bump the tools version to turn on the Swift 6 language mode. Swift 6.0 is the toolchain. If that job fails on a Core concurrency error, fix it in `Core/` without an AppKit import. Do not drop the job.

`WindowLayout.swift` keeps its `canImport(CoreGraphics)` branch so Linux Foundation still builds.

Local proof is `make test`, then `xcodegen generate`, then an unsigned Debug build:

```sh
make test
xcodegen generate
xcodebuild -project PEA.xcodeproj -scheme PEA -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= build
```

`make install` quits a running PEA and replaces `~/Applications/PEA.app`. `make unsigned` is a Release build. Neither is the local proof. CI runs `make install` in a scratch prefix.

## Keeping the docs current

When a tool's shortcuts, settings, or behavior change, update its README section, its row and section in `docs/ROADMAP.md`, and its spec in `docs/specs/`. A new folder goes in the README's layout tree. The roadmap's "Off means off" rule and the README's Clipboard paragraph both say that a switched-off tool registers no shortcuts, that its menu items still run, and that Pause recording is a separate switch. Keep them saying it.

## Where the shell lives

- `App/Shell/PEATool.swift` — the protocol
- `App/Shell/PEAHost.swift` — tool list, hot keys, status menu
- `App/Shell/SettingsWindow.swift` — `make(tools:)`
- `App/Shell/GeneralSettingsView.swift`
- `App/Clipboard/ClipboardTool.swift`
- `App/Clipboard/ClipboardSettingsView.swift` — `ClipboardSettingsView` and private `IgnoredAppsEditor`
- `App/Windows/WindowTool.swift`
- `App/TextActions/TextActionTool.swift`
- `App/TextActions/SelectionReader.swift` — also declares `ClipboardAccess`
- `App/TextActions/ActionBar.swift` — `ActionBarController` and the AppKit `ActionBarView`
- `App/TextActions/SelectionWatcher.swift`
- `App/TextActions/AccessibilitySwitch.swift`
- `App/TextActions/TextActionSettingsView.swift`

These are at `App/`. They are shell services, not tools: `HotKeys.swift`, `Shortcut.swift`, `Preferences.swift`, `Log.swift`, `main.swift`, `AppDelegate.swift`.
