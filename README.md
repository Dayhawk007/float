# Float

Float is a local-first Android notes/clipboard utility with a desktop CLI and local stdio MCP companion. It currently contains the local development foundation only: no accounts, deployments, cloud services, or sync are configured.

## Project layout

- `app/` — Flutter Android application with local snippet CRUD, pinning, search, and device-local persistence.
- `cli/` — TypeScript CLI plus the local stdio MCP server.
- `PRD.md` — product scope and phased roadmap.
- `DESIGN.md` — required client-side design and interaction system.

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
node cli/dist/index.js create --title "Availability" --body "I can start immediately." --tags jobs,forms --pin
node cli/dist/index.js search availability --json
```

The CLI persists to `%USERPROFILE%\\.float\\snippets.json` by default. Set `FLOAT_HOME` to use an isolated local data directory.

### MCP server

Build the CLI, then configure a compatible client to launch:

```text
command: node
args: ["E:\\Development\\float\\cli\\dist\\index.js", "mcp", "serve"]
```

The MCP server is local stdio only. It exposes `search_snippets`, `get_snippet`, `create_snippet`, and `update_snippet`; it neither opens a network port nor sends data to a cloud service.

## Validation

```powershell
pnpm --dir cli build
cd app; flutter test
```
