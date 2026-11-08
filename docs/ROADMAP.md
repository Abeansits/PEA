# PEA roadmap

PEA (Personal Everything App) is one menu bar app holding the small Mac tools I use every day, rebuilt so they're private and have no dependencies.

## Rules for every tool

- **macOS only.** AppKit and SwiftUI, public APIs, no third-party packages.
- **One app.** One menu bar icon, one Settings window with a tab per tool.
- **Off means off.** A tool that's switched off registers no shortcuts. Its menu items still run. Clipboard's shortcut switch is separate from Pause recording.
- **Private.** Nothing leaves the Mac except your own iCloud sync. No analytics.
- **Tested core.** Logic that doesn't need the OS goes in `PEACore` with unit tests; `App/<Tool>/` holds the OS glue.

## Tools

| # | Tool | Replaces | Status |
|---|---|---|---|
| 1 | Clipboard | PCP (this app's old self) | Shipped |
| 2 | Windows | Magnet | Shipped. [Spec](specs/windows.md) |
| 3 | Text actions | PopClip | v1 built, needs testing on a real Mac. [Spec](specs/text-actions.md) |

### 1. Clipboard

History, paste stack, secret filtering, iCloud sync. See the [README](../README.md#clipboard).

Next, in order:

1. **Sync without CloudKit.** CloudKit needs a paid Apple Developer membership. An optional encrypted copy of the history file in a folder you pick (iCloud Drive or any synced folder) would cover a free account.
2. **Pin a few clips** so the history limit and "forget after" can't drop them.

Left out on purpose: Universal Clipboard recording, image and file history, snippet expansion, any sync server that isn't yours.

### 2. Windows

Snap the focused window to halves, quarters, thirds or full screen from the keyboard. [Spec](specs/windows.md).

- **v1 (shipped):** Magnet's default shortcuts, a Move Window menu, Restore, move to next/previous display.
- **v2:** drag a window to a screen edge to snap it, with a preview; rebind each shortcut.

### 3. Text actions

Select text and get a small bar of actions next to it, like PopClip. [Spec](specs/text-actions.md).

- **v1 (built):** ⌃⌥A opens the bar for the current selection. Actions: copy, paste over the selection, search the web, open as a link, push to the PEA paste stack, UPPERCASE / lowercase / Title Case. The bar shows word and character counts. A Text Actions menu has the same actions.
- **Reading the selection:** Accessibility's `AXSelectedText` first. Where an app doesn't answer (many browsers and Electron apps), a synthetic ⌘C with clipboard recording suspended, and the old clipboard put back.
- **v2:** show the bar automatically after a mouse selection; ask Electron apps for Accessibility directly; more actions.

## Adding a tool

1. Write a short spec in `docs/specs/<tool>.md`: goal, non-goals, shortcuts, permissions, test plan.
2. Put the pure logic in `Core/Sources/PEACore/` with tests.
3. Put the OS code in `App/<Tool>/` as a `PEATool`, then add that value to `PEAHost`'s tool list. The list order is the Settings tab order and the status-menu order. A nil `statusMenuTitle` puts items on the root menu; a title puts them in a submenu. See the [architecture](architecture.md).
4. Add its shortcut switch to `Preferences`, default on. Off registers no shortcuts; the menu items still run.
5. Add it to this table and to the README.
