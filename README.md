# Float

> Clipboard on steroids—without the gym membership.

Float is a lightweight, local-first shelf for the words you reuse. It keeps useful notes, templates, links, and recent pastes one tap away on Android, then gives your desktop CLI and AI tools the same private library through a local MCP server.

## Why Float exists

Float started with a very ordinary frustration: filling out forms meant hunting through clipboard history, scattered notes, old chats, and open tabs for the one paragraph or URL I needed to paste again. Float turns that scavenger hunt into a small, searchable shelf that stays close while you work.

No account. No hosted backend. No mystery sync. Pair your phone with your computer on a trusted local network and keep the useful bits moving between your devices.

## See it in action

<p align="center">
  <img src="docs/screenshots/float-main.png" alt="Float main screen and pairing dialog" width="190" />
  <img src="docs/screenshots/float-overlay.png" alt="Float overlay with searchable pinned notes" width="190" />
  <img src="docs/screenshots/float-groups.png" alt="Float notes organized into groups" width="190" />
  <img src="docs/screenshots/float-pairing.png" alt="Float local device pairing dialog" width="190" />
</p>

## What you get

- **A calm Android shelf** — groups, search, pins, pagination, and a monochromatic UI for notes that are meant to be reused.
- **A floating handle** — tap the always-available edge handle over another app to open pinned notes and copy one with a single tap.
- **A clipboard shelf** — opt in to keep recent text pastes locally, then save only the useful ones as normal notes.
- **A desktop companion** — the TypeScript CLI stores your notes locally, runs the paired-device agent, and exposes a local stdio MCP server.
- **Agent-ready context** — Codex, Claude Desktop, Cursor, and other MCP clients can search, create, update, and delete Float notes.
- **Private pairing** — QR code or an eight-digit code, with no accounts and no cloud dependency.

## Project layout

```text
app/       Flutter Android application
cli/       TypeScript CLI, local agent, and MCP server
packages/  Local Flutter overlay dependency
docs/      Public screenshots and project documentation
```

## Quick start

### Prerequisites

- Node.js 20+
- pnpm
- Flutter SDK and Android SDK (for the Android client)
- An Android device or emulator

### Build the local tools

```powershell
pnpm install
pnpm --dir cli build
```

The CLI stores data in `%USERPROFILE%\\.float\\snippets.json` by default. Set `FLOAT_HOME` to use an isolated local data directory.

Create and search a note:

```powershell
node cli/dist/index.js create --title "Availability" --body "I can start immediately." --group "Job profile information" --pin
node cli/dist/index.js search availability --json
```

### Run the Android client

```powershell
cd app
flutter pub get
flutter run
```

For a real device, pass the desktop agent URL without editing source:

```powershell
flutter run --dart-define=FLOAT_AGENT_URL=http://YOUR_PC_WIFI_IP:8787
```

### Pair the phone and computer

On the computer, start a ten-minute pairing session:

```powershell
node cli/dist/index.js pair serve
```

Float prints a QR code and an eight-digit manual code. In the Android app, tap the link icon, scan the QR, or enter the local-agent URL and code manually. If an agent is already running, reprint its active pairing details without starting another server:

```powershell
node cli/dist/index.js pair show
```

Pairing is local-only. The phone retains its token securely, while the agent restores token hashes from `%USERPROFILE%\\.float\\paired-devices.json`, so a desktop restart does not require pairing again.

### Keep sync available after login

Install the per-user background agent once:

```powershell
node cli/dist/index.js agent install
node cli/dist/index.js agent status
```

This uses Task Scheduler/Run key on Windows, a LaunchAgent on macOS, and a user-level systemd service on Linux. It does not deploy anything to the cloud.

## MCP: give your AI assistant a private shelf

Float’s MCP server runs over local stdio, so an agent can use your notes without opening a network port. Build the CLI first, then add this server entry to Codex, Claude Desktop, Cursor, or another MCP-compatible client:

```json
{
  "mcpServers": {
    "float": {
      "command": "node",
      "args": ["E:\\Development\\float\\cli\\dist\\index.js", "mcp", "serve"]
    }
  }
}
```

Available tools are `search_snippets`, `get_snippet`, `create_snippet`, `update_snippet`, and `delete_snippet`. A useful agent workflow is: search before asking the user to repeat context, create a note when the user explicitly asks to remember something, and update the existing note when improving it. See [MCP.md](MCP.md) for client-specific guidance and [MCP-AGENT-SETUP.md](MCP-AGENT-SETUP.md) for an agent-readable setup runbook.

When a phone is paired and the local agent is reachable, the Android client pulls the latest notes during foreground sync. MCP itself remains local stdio; it does not send note contents to a hosted service.

## Clipboard shelf

Clipboard history is opt-in. While Float is open, it keeps the latest 20 text pastes in a separate “Latest pastes” modal. Tapping an item copies it again; tapping **+** saves it as a normal Float note. Clipboard entries are never silently turned into notes or synced unless you choose to save them. Android limits background clipboard access for ordinary apps, so continuous background history is intentionally out of scope.

## Release build

Build a distributable Android APK locally:

```powershell
cd app
flutter build apk --release
```

The artifact is written to `app/build/app/outputs/flutter-apk/app-release.apk`. GitHub releases are published from the CLI and include this APK as an asset.

## Privacy and diagnostics

Notes, clipboard entries, pairing credentials, and agent state stay on your devices. Pairing credentials expire after ten minutes. For troubleshooting, keep the agent terminal open and inspect `[float-agent]` events; Android pairing events are available with:

```powershell
adb logcat | Select-String FloatPair
```

## Validation

```powershell
pnpm --dir cli build
cd app
flutter test
flutter build apk --release
```

## License

Float is available under the [MIT License](LICENSE).
