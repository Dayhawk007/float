# Float Build Journal

This file is the running local-development record for Float. It is intentionally kept in the repository so product scope, implementation decisions, and unfinished work remain visible to future contributors and AI clients.

For every client-side change that affects UI or interaction, follow `DESIGN.md` and update it in the same commit if the design direction changes. For every cross-process or cross-device change, follow `DEBUGGING.md` and add privacy-safe diagnostics to both endpoints in the same commit.

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
- The paired phone polls the local agent every five seconds while paired and signals the active overlay after a pull, so desktop-created notes appear without restarting or manually rereading.
- Overlay permission failures explain Android's Display over other apps path and can open the app-specific system settings screen.
- Notes receive lightweight inferred presentation context (LinkedIn, link, template, code, or note) without changing the portable snippet schema.
- Opt-in clipboard shelf. Clipboard collection is disabled by default; when enabled, recent text pastes are kept in a capped local shelf and are only promoted to permanent notes when the user explicitly saves them.
- Account-free paired-device sync foundation: `float pair serve` creates a ten-minute QR credential plus an eight-digit manual code, issues a per-device token, and serves the desktop's local snippet store only while explicitly running on the local network. The Android app can scan the QR, enter the printed agent URL and code, stores its token in Android secure storage, and performs foreground last-write-wins sync.
- Pairing and sync emit structured, privacy-safe diagnostics to Android `FloatPair` logs and the local agent terminal. They record stage, origin, status, count, elapsed time, and error type, never tokens or note contents.

### Explicitly not implemented

- Accounts, authentication, hosted API, cloud database, deployment, analytics, crash reporting, background sync, and mDNS discovery.
- iOS, desktop GUI, browser extension, or remote MCP transport.
- Automatic promotion of every clipboard change into a permanent note.

## Next work

1. Test pairing and foreground sync on physical Android devices and common OEM variants.
2. Add mDNS discovery for paired agents on trusted LANs.
3. Add user-controlled retention limits and deletion controls for clipboard-history entries.
4. Replace `shared_preferences` with a transactional local database before the data model grows to tags, lists, and export/import.
