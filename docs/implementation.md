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

## Reference behaviour checklist

- [ ] Compact coloured windows and native resizing.
- [ ] File: New Note, Close/Delete, Import Text, Export Text, Print.
- [ ] Native Edit menu, selection/navigation, undo/redo, plain-text paste.
- [ ] Markdown adaptations of Bold and Italic; unsupported rich-text commands omitted.
- [ ] Six note colours.
- [ ] Collapse/expand, zoom, float on top, translucency.
- [ ] Arrange notes and use current appearance as default.
- [ ] Search in a note and across notes.
- [ ] Local frame and collapsed-state restoration.
- [ ] Recover deleted notes and previous versions.

Actual keyboard parity and visual differences will be recorded after UI verification. Font-family selection and image/attachment commands are intentionally outside the Markdown-only scope.

## Portion 1 validation: file storage

`scripts/test.sh`: 13 tests passed. Covers byte-preserving Markdown round trips, malformed files, duplicate identities, safe failures, idle saves, incoming changes, same-size/same-date edits, conflict-copy persistence, deletion recovery, and delayed handoff between two folders. Fixed URL normalization after a failing malformed-file test. The test script supplies the framework/runtime paths omitted by this Command Line Tools installation.

## Portion 2 validation: editing and layout

`scripts/test.sh`: 17 tests passed. Added UTF-16-safe Markdown toggling, list continuation/termination and indentation, and local layout persistence with off-screen recovery. A native window's layout file is independent of its Markdown document.

## Portion 3 validation: native note components

`scripts/test.sh`: 19 tests passed, including AppKit text-view tests for highlighting and external reload selection. Added the native note-window controller with local collapse, float, translucency, zoom, and editor callbacks. Application menus and lifecycle are the next portion. Sandboxed tests cannot contact the system spelling service; this does not fail the editor tests.
