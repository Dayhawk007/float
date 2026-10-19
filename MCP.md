# Float MCP companion

Float exposes the desktop note store to an agent through a local MCP server. The transport is stdio: the agent starts Float as a child process, and no network port or account is involved.

Build the CLI first:

```powershell
pnpm --dir cli build
```

The server command is:

```text
node E:\Development\float\cli\dist\index.js mcp serve
```

## Client configuration

Add a server named `float` to the MCP configuration for the agent. The shape is the same across clients, although each client stores it in a different settings file.

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

For Codex, add the server in its MCP/local tools settings. For Claude Desktop, put the entry in its `claude_desktop_config.json`. For Cursor, add the same entry under MCP servers in Cursor Settings. Keep the path absolute on Windows.

## Agent workflow

Give the agent a short instruction such as: “Use Float for reusable context. Search before creating a note; create a concise note only when it is likely to be reused, and include a useful title and group.” The agent can then:

1. call `search_snippets` before answering or creating duplicate context;
2. call `get_snippet` when it needs the full body of a candidate note;
3. call `create_snippet` for a new reusable URL, template, answer, or workflow note;
4. call `update_snippet` when the user asks it to revise or pin an existing note;
5. call `delete_snippet` only when the user explicitly asks to permanently delete a note.

The MCP tools write to the same local store used by the CLI. If the Android phone is paired and `float pair serve` is running, the next foreground sync pulls those changes to the phone and refreshes the floating overlay.

Deletes are recorded as sync tombstones. This prevents a stale paired device from re-uploading a note after it was deleted through MCP or the CLI; updated Android clients consume those tombstones and remove the local copy as well.

## Safety boundary

MCP access is local and explicit. The agent can only read or change Float snippets through the five registered tools. Deletion is permanent and requires an explicit user request. It does not receive clipboard history automatically, cannot access the Android overlay directly, and cannot reach a hosted service.
