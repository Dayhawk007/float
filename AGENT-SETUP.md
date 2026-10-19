# Float agent setup

This is the fast path for an AI coding agent (Codex, Claude Code, Cursor, or
another terminal-capable agent) working in a Float checkout. Read this file,
run the commands for the host platform, configure the agent's MCP settings,
and report the exact paths and results. Do not deploy anything or create a
cloud service.

## 1. Verify prerequisites

Required for the desktop companion: Node.js 20+ and pnpm. Flutter and the
Android SDK are only required when building or running the phone app.

```text
node --version
pnpm --version
```

Stop and tell the user what is missing if either command is unavailable.

## 2. Build the local companion

From the repository root:

```text
pnpm install
pnpm --dir cli build
```

Resolve the absolute path to `cli/dist/index.js`; never assume a Windows path.
The local data file is stored under the user's `.float` directory unless
`FLOAT_HOME` is set.

## 3. Register Float as an MCP server

Add this server to the active MCP client configuration, preserving all existing
servers and using the resolved absolute path:

```json
{
  "mcpServers": {
    "float": {
      "command": "node",
      "args": ["<absolute-repo-path>/cli/dist/index.js", "mcp", "serve"]
    }
  }
}
```

Use the client’s supported settings API or file. If the client cannot be
configured automatically, show the user this generated block and identify the
exact file or UI location instead of guessing.

Reload the MCP client and verify these tools are visible:
`search_snippets`, `get_snippet`, `create_snippet`, `update_snippet`, and
`delete_snippet`.

## 4. Optional Android build

```text
cd app
flutter pub get
flutter build apk --debug
```

Install the resulting APK on the user's device or run `flutter run` only when
the user asks. For normal users, prefer the latest release APK from GitHub.
The desktop URL is supplied during QR/manual pairing, so no build-time URL is
needed.

## 5. Optional local pairing

Start the desktop pairing session:

```text
node cli/dist/index.js pair serve
```

Give the user the printed QR/manual-code instructions, then wait for them to
complete pairing in Float. If a persistent agent already owns the port, use:

```text
node cli/dist/index.js pair show
```

Never start a second server just to display an existing pairing code.

## 6. Optional always-on sync

After the user confirms they want startup sync, run:

```text
node cli/dist/index.js agent install
node cli/dist/index.js agent status
```

This installs a per-user Windows Task Scheduler/Run entry, macOS LaunchAgent,
or Linux user systemd service. It does not require administrator privileges or
cloud setup.

## Agent safety rules

- Preserve existing MCP servers and user files.
- Ask before creating, updating, or deleting notes; ask again before deletion.
- Never print note contents, pairing codes, or device tokens in a completion report.
- Search before creating a duplicate reusable snippet.
- MCP is local stdio and opens no network port. Pairing is optional LAN sync.

## Completion report

Report: repository root, Node/pnpm versions, CLI build result, resolved MCP
entry path, discovered tool names, and whether Android/pairing/startup setup was
performed. Keep credentials and note contents out of the report.
