# Implementation log

## Environment and scope

- Reference: Apple Stickies 10.3, installed on macOS 26.5. The reference note uses a thin coloured title strip, small square controls, and a plain coloured editing surface.
- Deployment target: macOS 13 or newer. Only the current development Mac is verified so far.
- Full Xcode is not installed. Use a Swift package that opens in Xcode, the installed Command Line Tools, and an app-bundling script. This replaces the plan's initial Xcode-project choice without introducing dependencies.
- App name: Phelsuma (repository name).
- Keep the data format and recovery engine independent of AppKit.
- No cloud APIs, dependency downloads, analytics, or network requests.

## Portions

1. Commit the agreed plan.
2. Build the Markdown codec, file store, conflict copies, and local recovery with deterministic tests.
3. Build and test Markdown editing commands and local layout persistence.
4. Add the AppKit windows, menus, application lifecycle, and app packaging.
5. Exercise the assembled app, add regression tests for findings, and document verification limits.

## Implemented reference behaviour checklist

Checked items indicate implemented functionality, not exhaustive live verification of every menu command. The validation sections below distinguish tested interactions from outstanding checks.

- [x] Compact coloured windows and native resizing.
- [x] File: New Note, Close/Delete, Import Text, Export Text, Print.
- [x] Native Edit menu, selection/navigation, undo/redo, plain-text paste.
- [x] Markdown adaptations of Bold and Italic; unsupported rich-text commands omitted.
- [x] Six note colours.
- [x] Collapse/expand, zoom, float on top, translucency.
- [x] Arrange notes and use current appearance as default.
- [x] Search in a note and across notes.
- [x] Local frame and collapsed-state restoration.
- [x] Recover deleted notes and previous versions.

Actual keyboard parity and visual differences will be recorded after UI verification. Font-family selection and image/attachment commands are intentionally outside the Markdown-only scope.

## Portion 1 validation: file storage

`scripts/test.sh`: 13 tests passed. Covers byte-preserving Markdown round trips, malformed files, duplicate identities, safe failures, idle saves, incoming changes, same-size/same-date edits, conflict-copy persistence, deletion recovery, and delayed handoff between two folders. Fixed URL normalization after a failing malformed-file test. The test script supplies the framework/runtime paths omitted by this Command Line Tools installation.

## Portion 2 validation: editing and layout

`scripts/test.sh`: 17 tests passed. Added UTF-16-safe Markdown toggling, list continuation/termination and indentation, and local layout persistence with off-screen recovery. A native window's layout file is independent of its Markdown document.

## Portion 3 validation: native note components

`scripts/test.sh`: 19 tests passed, including AppKit text-view tests for highlighting and external reload selection. Added the native note-window controller with local collapse, float, translucency, zoom, and editor callbacks. Application menus and lifecycle are the next portion. Sandboxed tests cannot contact the system spelling service; this does not fail the editor tests.

## Portion 4 validation: assembled app

`scripts/test.sh`: 20 tests passed. `scripts/build-app.sh` produced an ad-hoc-signed `.app`. Through the native UI, verified new note creation, Unicode text, list continuation, Command-B, Command-Z, collapse/expand, Find and matching, delete confirmation, recovery preview, and restoration as a new note. File inspection confirmed Markdown punctuation and undo were saved as plain text. Fixed recovery deduplication across timestamp serialization and reserved Option-Command-F for Float on Top; Find and Replace uses Option-Command-R.

The UI tool took more than 20 minutes to return from the first Phelsuma launch; subsequent interactions completed normally. This is not the app build time.


## Portion 5 validation: hardening

`scripts/test.sh`: 27 tests passed. Added cases for deletion immediately before saving, renamed files, rapid edits, unrelated files, protected recovery retention, malformed incoming metadata, and the known check/write race. Fixed an outdent selection that could exceed the shortened text when selecting a whole list line, and guarded folder selection when local recovery initialization fails.

### Still outstanding

- Real iCloud handoff and conflicts on two Macs (only one Mac is available here).
- Other supported macOS versions, input-method composition with non-Latin input, and physical multi-monitor changes.
- Exhaustive Stickies shortcut parity and pixel-level appearance review. The current app uses its own small title-bar buttons and Markdown-adapted menus; macOS supplies its current system tiling menu automatically, but those actions have not been exhaustively tested. Selection-to-note Services are not yet included.
- Developer ID signing/notarization for distribution beyond local use.

The optimized build succeeded. Relaunch verification confirmed saved text and folded state survived quitting; the temporary UI verification note was deleted through the app's recoverable deletion flow. The welcome note remains. No real two-Mac cloud test was performed.
