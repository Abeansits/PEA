# Text actions: a small PopClip

Status: v1.1 built: the bar shows on selection and is a compact dark strip. Not yet tried on a real Mac. (v1, shortcut only with a large bar, was tried and worked, but was too big and needed the shortcut.)

## Goal

Select text in any app and get a small strip of actions right above it, so a new Mac doesn't need PopClip.

## Not in v1

- Extensions, custom actions, or scripts.
- Translation, dictionary lookup, spelling, anything that needs a network service.
- Actions on images or files.
- A per-app list of apps where the bar shouldn't appear.

## Showing the bar

1. **On selection** (default on). A mouse gesture that usually selects text — a drag, a double or triple click, a shift-click — shows the bar 0.12 s after the button comes up, if the app reports a selection through Accessibility. The bar doesn't take keyboard focus: typing still goes to the app. A click anywhere else, a key press, a scroll, or another app coming to the front hides it. Switch it off in Settings → Text Actions.
2. **Clicking the cursor again** (same switch). With nothing selected, click in editable text to place the insertion point, pause, then click the same spot again: a strip with **Paste** (when the clipboard has text) and **Select All** appears above the cursor, like tapping the cursor on iOS. Clicking an empty spot past the end of a line puts the cursor at the line's end, so two clicks there are enough to paste on a new line. The next click hides the strip and starts over. A click within the double-click interval is a double-click and selects a word instead. Single clicks that move the cursor somewhere new stay quiet.
3. **⌃⌥A** reads the selection in any app (with ⌘C as the fallback) and opens the bar *with* keyboard focus. Pressed while a bar is showing on its own, it gives that bar focus. Pressed again, it closes it. The shortcut can be changed or switched off; Settings beeps at keys another PEA shortcut holds. On shared keys Clipboard wins, then Windows, then Text Actions.

## The bar

A dark rounded strip, 28 pt tall, in light and dark mode alike. Segments are icons or short words, with no key hints and no counts:

| Segment | What it does | Shown when |
|---|---|---|
| 🔍 | searches the web with the engine picked in Settings (DuckDuckGo by default) | always |
| Cut | sends ⌘X | the text is editable |
| Select All | sends ⌘A | only on the cursor strip |
| Copy | sends ⌘C, so formatting is kept and the copy is recorded like any other | always |
| Paste | sends ⌘V: the clipboard replaces the selection | editable, and the clipboard has text |
| ↗ | opens a web or email address | the selection is one |
| Stack | pushes the selection onto the paste stack, as if it had been copied (icon) | always |
| Aa | swaps the segments for ABC, abc, Abc: UPPERCASE, lowercase, Title Case | editable |
| # | swaps the segments for the word and character counts (and lines, when more than one) | always |

"Editable" is what Accessibility says: the focused element's selected text or value can be set. Terminal, web pages and other read-only text get only 🔍 Copy (↗) Stack #. After ⌘C, editability is unknown and every segment is offered.

- **Mouse.** The segment under the pointer is highlighted in the accent color. A click runs it, and the first click counts even though PEA isn't the active app. Clicking the counts closes the bar.
- **Keys** (after ⌃⌥A only, when the bar has focus). ← → or Tab move the highlight; ↩ or Space runs it. Letters run actions straight away: S search, X cut, C copy, V paste, O open, A stack, U / L / T case. Esc or ⌘W closes.
- **Where.** Centered 6 pt above a single-line selection, or above the pointer when the selection spans lines (or the app doesn't say where it is). Below when there's no room above; always inside the screen. Swapping segments keeps the bar centered where it was.

### Details

- **Title Case** puts each word's first letter in upper case and the rest in lower case, the way macOS's Transformations → Capitalize does: `hello WORLD` → `Hello World`, `don't` → `Don't`, `well-known` → `Well-Known`. Small words (a, of, the) aren't kept lower case.
- **Counts.** A word is a run of non-space characters that holds a letter or digit, so `—` isn't one. Text without spaces between words (Chinese, Japanese) counts as one word. Characters are what a person sees (`👍🏽` is one).
- **Links.** `https://…`, `http://…` and `mailto:` addresses open. So do bare hosts that start with `www.` or end in a common domain (`example.com/path`), which get `https://`, and bare email addresses, which get `mailto:`. File names like `README.md` don't count. Other schemes (`file:`, app links) are never opened: selected text shouldn't launch programs. Surrounding quotes, brackets and a trailing period are ignored.
- **Search** turns whitespace and line breaks into single spaces, cuts the query at 500 characters, and percent-encodes it so `c++` reaches the engine as typed.
- **Stack** follows the clipboard's secret rules: a password-like selection is kept in memory only, or not at all. Pause Recording and the ignore list don't apply, because this is an explicit request, not a background copy. Selections over 512 KB beep.

## Reading the selection

**After a mouse gesture: Accessibility only.** PEA asks the frontmost app's focused element for `AXSelectedText`. Two guards keep the bar from appearing when nothing was selected:

- The gesture must start inside the focused element's frame (`AXPosition` + `AXSize`, with 4 pt of slack), so dragging a window by its title bar doesn't bring up an older selection in it. If the app doesn't report a frame, the check is skipped.
- Empty or whitespace-only selections don't count.

No ⌘C here: one after every drag would copy files in Finder and shapes in drawing apps. So the bar appears on its own only in apps that answer: native apps such as TextEdit, Notes, Mail and Xcode; which others do is part of the test plan. Chrome and Electron apps (VS Code, Slack) don't answer by default, so use ⌃⌥A there.

**After a plain click: the insertion point.** PEA reads the focused element's `AXSelectedTextRange`. It counts only when the element is editable, the range is empty, and the click was inside the element. The element (compared with `CFEqual`) and the character offset are remembered; the next plain click compares against them. Mouse reads use a 0.25 s Accessibility timeout, because every click in every app asks.

**After ⌃⌥A: Accessibility, then ⌘C.** If the app doesn't answer, or answers with an empty string, PEA saves the clipboard, sends ⌘C, waits up to 0.4 s for the pasteboard to change, reads the text, and puts the saved clipboard back, every item and type. Clipboard history stops recording for that time, so neither change is recorded. No pasteboard change means nothing was selected: a beep.

Edge cases that follow from ⌘C:

- Apps that copy the whole line when nothing is selected (VS Code) give the bar that line.
- A selection a password manager marks as concealed is treated as no selection.
- If the clipboard holds a Universal Clipboard item from another device, PEA can't save it (reading it blocks while it downloads), so after a ⌘C read the clipboard holds the selection instead.

`AXSelectedTextRange` and `AXBoundsForRange` place the bar; `AXSelectedText` and `AXValue` being settable mark the text as editable.

### Replacing the selection

Case changes paste over the selection: PEA saves the clipboard, writes the new text (marked `org.nspasteboard.TransientType` so other clipboard tools skip it), sends ⌘V, waits 0.5 s, and puts the saved clipboard back unless something else changed it meanwhile. History doesn't record any of it. Pasting rather than setting `AXSelectedText` works in every app and leaves one ⌘Z step in the app's own undo.

## Menu

The menu bar menu has a **Text Actions** submenu: Show Actions for Selection, then Search the Web, Open Link, Add to Paste Stack, Make UPPERCASE, Make lowercase, Make Title Case. Each reads the selection when chosen. They work with the shortcut off. Cut, Copy and Paste are left out: the app's Edit menu has them.

## Permissions

- **Accessibility** (`AXIsProcessTrusted`, the one Windows uses) for reading the selection directly, and for the key presses that hide a bar. Without it the bar never appears on its own, and ⌃⌥A goes through ⌘C with the bar at the pointer.
- **Posting keystrokes** (`CGPreflightPostEventAccess`, the one pasting uses) for ⌘X, ⌘C and ⌘V.
- Watching mouse clicks in other apps (`NSEvent.addGlobalMonitorForEvents`) needs no permission.

PEA doesn't prompt for either at launch. Settings → Text Actions shows both with an Allow… button. The keystroke prompt appears once per launch the first time one is needed, as it does for pasting.

## How it's built

| File | Job |
|---|---|
| `Core/Sources/PEACore/TextActions.swift` | Pure logic: `TextAction` (with `editsText` and `available(for:canPaste:isEditable:)`), `TextCase`, `TextStats`, `LinkDetector`, `SearchEngine`, `BarPlacement`. Tested in `TextActionsTests.swift`. |
| `App/TextActions/SelectionWatcher.swift` | A global mouse/key/scroll monitor: reports selection gestures and what interrupts them. |
| `App/TextActions/SelectionReader.swift` | Accessibility reads (with the frame check for mouse gestures), the ⌘C fallback, pasting over the selection, saving and restoring the clipboard. Declares `ClipboardAccess`. |
| `App/TextActions/ActionBar.swift` | `ActionBarController` (the panel, focus modes, segment swaps, keys) and `ActionBarView`, a plain `NSView` that draws the strip and tracks the mouse. |
| `App/TextActions/TextActionTool.swift` | The `PEATool`: hot key, menu, `start()` for the watcher, running the actions. |
| `App/TextActions/TextActionSettingsView.swift` | The Text Actions tab in Settings. |

Details that matter:

- **Not stealing focus.** The bar is a `FloatingPanel` (non-activating) with `becomesKeyOnlyIfNeeded`, so clicks on it don't make it key; `ActionBarView.acceptsFirstMouse` is true so the first click runs the segment. Only ⌃⌥A calls `makeKeyAndOrderFront`.
- **Hover while inactive.** The tracking area uses `.activeAlways`, and the panel accepts mouse-moved events, because PEA is never the active app while the bar is up.
- **Why AppKit, not SwiftUI.** Exact size for the panel, reliable hover and first click in a non-key panel of an inactive app.
- `ClipboardTool` implements `ClipboardAccess`. `PEAHost.start()` calls `textActions.start()` after `clipboard.start()`.

## Test plan (on a Mac)

1. TextEdit: drag across a word. A small dark strip appears just above it: 🔍 Cut Copy Paste Stack Aa #. Typing replaces the word as usual and the strip disappears.
2. Double-click a word, click Aa, then ABC: the word turns upper case, ⌘Z undoes it, and ⇧⌘C shows no new history entry.
3. Select a sentence on a web page in Safari. If the strip appears, it has only 🔍 Copy Stack # (no Cut, Paste or Aa). Click #: the counts replace the segments.
4. Drag a TextEdit window by its title bar while text in it is selected: no strip.
4a. TextEdit: click past the end of a line, pause, click there again: Paste · Select All appear above the cursor. Paste puts the clipboard there. Click once more: the strip goes away. Click somewhere new once: nothing.
5. Drag files in Finder, draw in Preview's markup, drag a slider: no strip, and the clipboard is unchanged.
6. Chrome or Slack: dragging shows nothing. ⌃⌥A shows the bar at the pointer, with keyboard focus; ⌘V afterwards still pastes what was on the clipboard before.
7. With a strip showing on its own, press ⌃⌥A: it takes focus and ← → move the highlight. Press ⌃⌥A again: it closes.
8. Select `example.com`: ↗ appears and opens https://example.com. `README.md`: no ↗.
9. Switch "Show when you select text" off: dragging shows nothing; ⌃⌥A still works.
10. Turn Accessibility off for PEA: nothing appears on selection; ⌃⌥A still works through ⌘C.

## Open questions

1. Is 0.12 s after the mouse comes up enough for every app to have updated its selection? Is 0.5 s long enough before the clipboard comes back after a case change?
2. Should the strip skip some apps by default (code editors, Terminal), or wait for a per-app list?
3. Should Title Case leave small words (a, of, the) and all-caps words (NASA) alone?

## Later

- Show on selection in Chrome and Electron apps: turn on `AXManualAccessibility` for Electron apps, and consider a ⌘C read after drags in known browsers.
- A per-app off switch.
- More actions: sentence case, trim whitespace, wrap in quotes, a calculator for selected math, dictionary lookup.
