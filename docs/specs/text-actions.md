# Text actions: a small PopClip

Status: v1 built. Not yet tried on a real Mac.

## Goal

Select text in any app, press one shortcut, and get a small bar of actions next to the selection, so a new Mac doesn't need PopClip.

## Not in v1

- Showing the bar on its own after a mouse selection. v1 waits for the shortcut.
- Extensions, custom actions, or scripts.
- Translation, dictionary lookup, spelling, anything that needs a network service.
- Actions on images or files.

## Shortcut

| Keys | Action |
|---|---|
| ⌃⌥A | show the bar for the current selection; press again to close it |

⌃⌥A sits next to the window shortcuts on a letter they leave free. It can be changed in Settings → Text Actions, and switched off there. Settings beeps at a shortcut another PEA shortcut already holds (the clipboard ones and the ⌃⌥ letters of Windows). If one is left on the same keys anyway, Clipboard wins, then Windows, then Text Actions.

## The bar

| Button | Key | What it does |
|---|---|---|
| Copy | C | sends ⌘C to the app, so formatting is kept and the copy is recorded like any other |
| Paste | V | sends ⌘V: the clipboard replaces the selection. Shown only when the clipboard has text |
| Search | S | opens the selection in the browser with the search engine picked in Settings (DuckDuckGo by default) |
| Open | O | opens a web or email address. Shown only when the selection is one |
| Stack | A | pushes the selection onto the paste stack, as if it had been copied |
| ABC / abc / Abc | U / L / T | replaces the selection with its UPPERCASE, lowercase or Title Case version |

After the buttons, the bar shows the word and character counts, plus the line count when there's more than one line.

- **Keys.** The letters run an action straight away. ← → (or Tab) move the highlight and ↩ or Space runs it. Esc, ⌘W, a click elsewhere, or the shortcut again closes the bar. The letters stay the same when a button is hidden.
- **Where.** Centered above the selection, or below it when there's no room above, always inside the screen. If the app doesn't say where the selection is, the bar opens above the mouse pointer.
- **Focus.** The bar takes keyboard focus without activating PEA, like clipboard history, so the app with the selection stays frontmost and gets the keystrokes afterwards.

### Details

- **Title Case** puts each word's first letter in upper case and the rest in lower case, the way macOS's Transformations → Capitalize does: `hello WORLD` → `Hello World`, `don't` → `Don't`, `well-known` → `Well-Known`. Small words (a, of, the) aren't kept lower case.
- **Counts.** A word is a run of non-space characters that holds a letter or digit, so `—` isn't one. Text without spaces between words (Chinese, Japanese) counts as one word. Characters are what a person sees (`👍🏽` is one).
- **Links.** `https://…`, `http://…` and `mailto:` addresses open. So do bare hosts that start with `www.` or end in a common domain (`example.com/path`), which get `https://`, and bare email addresses, which get `mailto:`. File names like `README.md` don't count. Other schemes (`file:`, app links) are never opened: selected text shouldn't launch programs. Surrounding quotes, brackets and a trailing period are ignored.
- **Search** turns whitespace and line breaks into single spaces, cuts the query at 500 characters, and percent-encodes it so `c++` reaches the engine as typed.
- **Stack** follows the clipboard's secret rules: a password-like selection is kept in memory only, or not at all. Pause Recording and the ignore list don't apply, because this is an explicit request, not a background copy. Selections over 512 KB beep.

## Reading the selection

1. **Accessibility first.** PEA asks the frontmost app's focused element for `AXSelectedText`, and for `AXBoundsForRange` of the selected range to place the bar. This leaves the clipboard alone. It should work in native apps such as TextEdit, Notes, Mail and Xcode; which others answer is part of the test plan.
2. **⌘C otherwise.** Many browsers and Electron apps (Chrome, VS Code, Slack) don't answer, or answer with an empty string. Then PEA saves the clipboard, sends ⌘C, waits up to 0.4 s for the pasteboard to change, reads the text, and puts the saved clipboard back, every item and type. Clipboard history stops recording for that time, so neither change is recorded.
3. **Nothing selected** (no answer and no pasteboard change): PEA beeps.

Edge cases that follow from ⌘C:

- Apps that copy the whole line when nothing is selected (VS Code) give the bar that line.
- A selection a password manager marks as concealed is treated as no selection.
- If the clipboard holds a Universal Clipboard item from another device, PEA can't save it (reading it blocks while it downloads), so after a ⌘C read the clipboard holds the selection instead.

### Replacing the selection

Case changes paste over the selection: PEA saves the clipboard, writes the new text (marked `org.nspasteboard.TransientType` so other clipboard tools skip it), sends ⌘V, waits 0.5 s, and puts the saved clipboard back unless something else changed it meanwhile. History doesn't record any of it. Pasting rather than setting `AXSelectedText` works in every app and leaves one ⌘Z step in the app's own undo.

## Menu

The menu bar menu has a **Text Actions** submenu: Show Actions for Selection, then Search the Web, Open Link, Add to Paste Stack, Make UPPERCASE, Make lowercase, Make Title Case. Each reads the selection when chosen. They work with the shortcut off. Copy and Paste are left out: the app's Edit menu has them.

## Permissions

- **Accessibility** (`AXIsProcessTrusted`, the one Windows uses) for reading the selection directly. Without it every read goes through ⌘C, and the bar opens at the pointer.
- **Posting keystrokes** (`CGPreflightPostEventAccess`, the one pasting uses) for ⌘C and ⌘V.

PEA doesn't prompt for either at launch. Settings → Text Actions shows both with an Allow… button. The keystroke prompt appears once per launch the first time one is needed, as it does for pasting.

## How it's built

| File | Job |
|---|---|
| `Core/Sources/PEACore/TextActions.swift` | Pure logic: `TextAction`, `TextCase`, `TextStats`, `LinkDetector`, `SearchEngine`, `BarPlacement`. Tested in `TextActionsTests.swift`. |
| `App/TextActions/SelectionReader.swift` | Accessibility read, the ⌘C fallback, pasting over the selection, saving and restoring the clipboard. Declares `ClipboardAccess`. |
| `App/TextActions/ActionBar.swift` | The bar: a `FloatingPanel` with a SwiftUI row of buttons, and its keys. |
| `App/TextActions/TextActionTool.swift` | The `PEATool`: hot key, menu, running the actions. |
| `App/TextActions/TextActionSettingsView.swift` | The Text Actions tab in Settings. |

`ClipboardTool` implements `ClipboardAccess` (`suspendRecording`, `resumeRecording`, `addToStack`). `PEAHost` hands it to `TextActionTool`. `PasteboardMonitor.suspend()` makes `poll()` a no-op until `resume()`, which also marks the current pasteboard as seen.

## Test plan (on a Mac)

1. TextEdit: select a word, ⌃⌥A. The bar appears right above it with Copy, Search, Stack, ABC, abc, Abc and the counts. Press U: the word turns upper case, ⌘Z undoes it, and ⇧⌘C shows no new history entry.
2. Copy something, then select other text and press ⌃⌥A, V: the selection is replaced by the clipboard.
3. Chrome or Slack: select text, ⌃⌥A. The bar appears at the pointer. Afterwards ⌘V still pastes what was on the clipboard before, and history has no new entry.
4. Select `example.com` and press O: the browser opens https://example.com. Select `README.md`: no Open button.
5. Press S on `c++ templates`: the search shows `c++ templates`, not `c templates`.
6. Press A on a selection, then ⇧⌘V somewhere else: it pastes.
7. Nothing selected, ⌃⌥A: a beep, and the clipboard is unchanged.
8. Turn Accessibility off for PEA: step 1 still works, with the bar at the pointer.
9. Switch the shortcut off: ⌃⌥A reaches the frontmost app again, and the menu's Text Actions items still work.
10. Change the shortcut in Settings to ⌃⌥C: it beeps, because Windows' Center holds it.

## Open questions

1. Is 0.5 s long enough before the clipboard comes back after a case change, in slow apps?
2. Should Title Case leave small words (a, of, the) and words that are already all caps (NASA) alone?

## v2

- Show the bar after a mouse selection, PopClip-style, with a per-app off switch.
- Turn on `AXManualAccessibility` for Electron apps so they answer directly instead of through ⌘C.
- More actions: sentence case, trim whitespace, wrap in quotes, a calculator for selected math, dictionary lookup.
