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
- Opt-in clipboard shelf. Clipboard collection is disabled by default; when enabled, recent text observed while Float is open plus the current clipboard on launch are kept in a capped local shelf and are only promoted to permanent notes when the user explicitly saves them. Android does not permit a normal background app to observe every clipboard change.
- Clipboard history is accessed through a compact icon beside its setting and opens in a modal; the main note list and floating overlay remain focused on saved notes. Each paste uses a plus action to save it as a note.
- Main notes and overlay notes use visible scrollbars plus compact pages (20 notes in the app, 5 in the overlay) to keep each surface responsive and legible.
- A paired device remains authorized after `float pair serve` restarts: token hashes are restored from the local agent registry, Android retains its device token, and sync requests time out after five seconds so the foreground retry loop can recover.
- A persistent desktop agent can be installed per user with `float agent install`. It uses Task Scheduler on Windows, a LaunchAgent on macOS, or a user-level systemd service on Linux; it starts at sign-in and only serves devices that have already been paired.
- Paired agents have a stable local identity and advertise `_float._tcp.local` on the trusted LAN. If the desktop receives a new LAN IP, Android searches for that identity after a sync failure, verifies it through the health endpoint, persists the recovered URL, and retries sync. Tokens and note contents are never advertised.
- Account-free paired-device sync foundation: `float pair serve` creates a ten-minute QR credential plus an eight-digit manual code, issues a per-device token, and serves the desktop's local snippet store only while explicitly running on the local network. The Android app can scan the QR, enter the printed agent URL and code, stores its token in Android secure storage, and performs foreground last-write-wins sync.
- Pairing and sync emit structured, privacy-safe diagnostics to Android `FloatPair` logs and the local agent terminal. They record stage, origin, status, count, elapsed time, and error type, never tokens or note contents.
- Notes carry a portable `group` field (default: `General`). The Android editor supports groups such as Jobs, Cold posting, Profile, and Preferences; the main list navigates them with chips, the overlay searches and sections pinned notes by group, and CLI/MCP/sync preserve the same field.

### Explicitly not implemented

- Accounts, hosted API, cloud database, deployment, analytics, crash reporting, and background sync.
- iOS, desktop GUI, browser extension, or remote MCP transport.
- Automatic promotion of every clipboard change into a permanent note.

## Next work

1. Test auto-start and mDNS recovery on physical Android devices and common OEM variants.
2. Add user-controlled retention limits and deletion controls for clipboard-history entries.
3. Replace `shared_preferences` with a transactional local database before the data model grows to tags, lists, and export/import.
