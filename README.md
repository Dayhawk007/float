# Float

Float is a local-first Android notes and clipboard utility with a desktop CLI and local stdio MCP companion. It has no accounts, deployments, or cloud services: optional sync is directly between a paired phone and the user’s computer on a trusted local network.

## What it includes

- A lightweight Android note library with groups, search, pinned notes, and pagination.
- A required floating handle for copying pinned notes over other apps, with system overlay permission requested on first use.
- An opt-in, device-local clipboard shelf for saving useful pastes as notes.
- A TypeScript CLI and local MCP server so AI tools can search, create, update, and delete notes.
- QR or manual-code pairing between the phone and a persistent local desktop agent.

## Project layout

- `app/` — Flutter Android application with local snippet CRUD, pinning, search, and device-local persistence.
- `cli/` — TypeScript CLI, persistent paired-device agent, and local stdio MCP server.
- `packages/` — local Flutter overlay dependency.

## Run locally

### Android app

```powershell
cd app
flutter pub get
flutter run
```

### CLI

```powershell
pnpm install
pnpm --dir cli build
node cli/dist/index.js create --title "Availability" --body "I can start immediately." --group "Job profile information" --pin
node cli/dist/index.js search availability --json
```

The CLI persists to `%USERPROFILE%\\.float\\snippets.json` by default. Set `FLOAT_HOME` to use an isolated local data directory.

### Keep the local agent available

To make paired-device sync available after sign-in without manually starting a terminal, install the per-user agent once:

```powershell
node cli/dist/index.js agent install
node cli/dist/index.js agent status
```

It uses Task Scheduler or the Windows Run key on Windows, a LaunchAgent on macOS, and a user-level systemd service on Linux. The background agent serves only devices that have already been paired.

### Pair an Android device locally

On the same trusted Wi-Fi network, run:

```powershell
node cli/dist/index.js pair serve
```

The CLI prints a one-time pairing URI, terminal QR code, and an eight-digit manual code. In Float, choose the link icon, scan the QR code, or enter the printed local-agent URL and manual code. Pairing credentials expire after ten minutes; after pairing, the phone holds a device token in Android secure storage and syncs only while the local agent is running and reachable. This is peer-to-peer local development: it creates no account and sends no data to a hosted service.

If the pairing server is already running and its terminal is unavailable, use `node cli/dist/index.js pair show`. It contacts that existing local process over loopback and reprints the active QR and manual code without starting a second server or opening another port.

If the persistent `float agent serve` process already owns the default port, `float pair serve` opens a ten-minute pairing session on that same process and prints its QR. It does not start a second agent or interrupt already-paired devices.

If the computer or agent restarts, paired-device token hashes are restored from `%USERPROFILE%\\.float\\paired-devices.json`, while the phone retains its token in Android secure storage. Float retries foreground sync automatically. If the PC obtains a new LAN address, Android discovers the local agent again by its stable identity.

### Pairing diagnostics

Keep the `float pair serve` terminal open during pairing. It prints `[float-agent]` request events with the request ID, route, status, and safe failure reason. Android emits matching `FloatPair` events to `adb logcat`; use `adb logcat | Select-String FloatPair` on Windows. The agent prefers physical Wi-Fi/Ethernet interfaces over virtual adapters; if needed, explicitly pass `--url http://YOUR_PC_WIFI_IP:8787`. These logs deliberately omit pairing codes, tokens, and note contents.

### MCP server

Build the CLI, then configure Codex, Claude Desktop, Cursor, or another MCP-compatible client to launch:

```text
command: node
args: ["E:\\Development\\float\\cli\\dist\\index.js", "mcp", "serve"]
```

The MCP server is local stdio only. It exposes `search_snippets`, `get_snippet`, `create_snippet`, `update_snippet`, and `delete_snippet`; it neither opens a network port nor sends data to a cloud service. An AI client can use those tools to create and organize notes, and the paired Android device syncs them from the local agent.

### Clipboard shelf

Clipboard history is opt-in. When enabled, Float keeps the latest 20 text pastes it can observe while the app is open, and reads the current clipboard when Float opens, in a local “Latest pastes” shelf. Tapping a paste copies it again; the bookmark action saves it as a normal Float note. Clipboard entries are not silently converted into notes and are not synced unless explicitly saved. Android prevents ordinary apps from continuously reading clipboard data while they are in the background; full background history would require a user-enabled keyboard or accessibility-service design and is intentionally out of scope.

## Privacy

Notes, device tokens, clipboard history, pairing credentials, and local agent state stay on your devices. Pairing QR credentials expire after ten minutes and are kept in the running agent’s memory; the short-lived local pairing descriptor stores only a loopback address and expiry. No account or hosted backend is required.

## Validation

```powershell
pnpm --dir cli build
cd app; flutter test
```

## License

Float is available under the [MIT License](LICENSE).
