# Float

Float is a local-first Android notes/clipboard utility with a desktop CLI and local stdio MCP companion. It has no accounts, deployments, or cloud services; optional sync is directly between a paired phone and an explicitly started local CLI agent.

## Project layout

- `app/` — Flutter Android application with local snippet CRUD, pinning, search, and device-local persistence.
- `cli/` — TypeScript CLI plus the local stdio MCP server.
- `PRD.md` — product scope and phased roadmap.
- `DESIGN.md` — required client-side design and interaction system.
- `MCP.md` — local MCP setup for Codex, Claude Desktop, and Cursor.
- `MCP-AGENT-SETUP.md` — agent-readable dynamic setup runbook for any MCP client.

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

### Pair an Android device locally

On the same trusted Wi-Fi network, run:

```powershell
node cli/dist/index.js pair serve
```

The CLI prints a one-time pairing URI, terminal QR code, and an eight-digit manual code. In Float, choose the link icon, scan the QR code, or enter the printed local-agent URL and manual code. Pairing credentials expire after ten minutes; after pairing, the phone holds a device token in Android secure storage and syncs only while the local agent is running and reachable. This is peer-to-peer local development: it creates no account and sends no data to a hosted service.

If the computer or `float pair serve` restarts, simply run the same command again from the same Float data directory. The agent restores paired-device token hashes from `%USERPROFILE%\\.float\\paired-devices.json`, while the phone retains its token in Android secure storage. Float retries its foreground sync automatically, so a restarted agent on the same address resumes without scanning a new QR code. A changed PC LAN address still requires local discovery or an updated pairing address; that is a future mDNS feature.

### Pairing diagnostics

Keep the `float pair serve` terminal open during pairing. It prints `[float-agent]` request events with the request ID, route, status, and safe failure reason. Android emits matching `FloatPair` events to `adb logcat`; use `adb logcat | Select-String FloatPair` on Windows. The agent prefers physical Wi-Fi/Ethernet interfaces over virtual adapters; if needed, explicitly pass `--url http://YOUR_PC_WIFI_IP:8787`. These logs deliberately omit pairing codes, tokens, and note contents.

### MCP server

See [MCP.md](MCP.md) for Codex, Claude Desktop, and Cursor setup plus the recommended agent workflow. For an agent-driven setup, give the agent [MCP-AGENT-SETUP.md](MCP-AGENT-SETUP.md) and ask it to follow the runbook.

Build the CLI, then configure a compatible client to launch:

```text
command: node
args: ["E:\\Development\\float\\cli\\dist\\index.js", "mcp", "serve"]
```

The MCP server is local stdio only. It exposes `search_snippets`, `get_snippet`, `create_snippet`, and `update_snippet`; it neither opens a network port nor sends data to a cloud service. The optional paired-device agent is separate and only opens a LAN port while `float pair serve` is running.

### Clipboard shelf

Clipboard history is opt-in. When enabled, Float keeps the latest 20 text pastes it can observe while the app is open, and reads the current clipboard when Float opens, in a local “Latest pastes” shelf. Tapping a paste copies it again; the bookmark action saves it as a normal Float note. Clipboard entries are not silently converted into notes and are not synced unless explicitly saved. Android prevents ordinary apps from continuously reading clipboard data while they are in the background; full background history would require a user-enabled keyboard or accessibility-service design and is intentionally out of scope.

## Validation

```powershell
pnpm --dir cli build
cd app; flutter test
```
