# Float MCP agent setup

This file is an agent-readable runbook. An MCP-capable agent can read it and
perform the setup for the current checkout instead of requiring a user to copy
commands by hand.

## Goal

Register Float as an MCP server named `float`, using the local CLI in this
checkout. The server uses local stdio transport and must be started by the
agent as a child process.

## Agent procedure

1. Resolve the repository root from this file's location. Do not assume that
   the path is `E:\Development\float`.
2. Check that Node.js 20 or newer and pnpm are available.
3. Run `pnpm install` at the repository root if dependencies are missing.
4. Run `pnpm --dir cli build`.
5. Construct the absolute path to `<repo>/cli/dist/index.js`.
6. Add the server definition below to the MCP configuration supported by the
   current agent. Preserve existing servers and formatting.
7. Reload the MCP client and verify that the server exposes these tools:
   `search_snippets`, `get_snippet`, `create_snippet`, `update_snippet`, and
   `delete_snippet`.
8. If the client cannot be configured programmatically, show the generated
   definition and identify the exact settings file or UI location; do not
   guess or overwrite an unrelated configuration file.

## Canonical server definition

Use the absolute, platform-native path. On Windows, escape backslashes when
writing JSON.

```json
{
  "mcpServers": {
    "float": {
      "command": "node",
      "args": [
        "<absolute-repo-path>/cli/dist/index.js",
        "mcp",
        "serve"
      ]
    }
  }
}
```

The equivalent process invocation is:

```text
node <absolute-repo-path>/cli/dist/index.js mcp serve
```

## Operating rules for the agent

- Search Float before creating duplicate reusable context.
- Ask before creating or updating notes unless the user has already requested
  that write.
- Ask for explicit confirmation before calling `delete_snippet`; deletion is
  permanent and there is no recycle bin.
- Store only reusable snippets, URLs, templates, answers, or workflows.
- Never treat Float as a source of clipboard history unless the user explicitly
  asks for a saved snippet.

## Data and security boundary

Float stores data locally in `%USERPROFILE%\\.float\\snippets.json` on Windows
and the equivalent user-local directory on other platforms. `FLOAT_HOME` may
override the data directory. The MCP server opens no network port and sends no
data to a hosted service. The optional Android pairing agent is separate.

## Completion report

After setup, report the resolved CLI path, the client configuration target, the
build result, and the discovered tool names. Do not print note contents or
credentials.
