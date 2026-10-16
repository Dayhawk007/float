# Float Build Journal

This file is the running local-development record for Float. It is intentionally kept in the repository so product scope, implementation decisions, and unfinished work remain visible to future contributors and AI clients.

## Current local milestone

### Implemented

- Flutter Android app with local snippet create, edit, pin, search, and delete flows.
- Device-local snippet persistence through `shared_preferences`.
- TypeScript CLI with a local JSON store and a local stdio MCP server.
- Android package ID: `com.dayhawk.floatnotes`.
- Native Android floating-overlay permission and foreground-service wiring.
- A draggable side handle that expands to pinned notes only when the user taps it; Android owns bounded dragging without auto-snapping, while Flutter receives ordinary taps, and pin/unpin changes refresh an active overlay.
- The overlay dependency is vendored locally with strict Android `WindowManager` bounds, so drag and resize keep the handle fully visible on the display.
- Releasing the compact handle snaps it to the nearest vertical screen edge; its native touch listener emits an explicit tap event to expand the notes panel.
- The Android app and floating panel use a monochrome, low-elevation visual language: warm-white surfaces, near-black controls, fine borders, compact labels, and restrained state transitions.
- The overlay reloads its isolated local-preferences cache when notes change, so new pins appear without restarting; the handle has no elevation/shadow.
- Opt-in clipboard watcher. Clipboard collection is disabled by default and remains local to the device.

### Explicitly not implemented

- Accounts, authentication, hosted API, cloud database, sync, deployment, analytics, and crash reporting.
- iOS, desktop GUI, browser extension, or remote MCP transport.
- Clipboard history that is enabled without the user’s explicit in-app choice.

## Next work

1. Test the overlay and clipboard listener on physical Android devices and common OEM variants.
2. Add user-controlled retention limits and deletion controls for clipboard-history entries.
3. Replace `shared_preferences` with a transactional local database before the data model grows to tags, lists, and export/import.
4. Add Android Share Target intake and a clear overlay onboarding screen.
