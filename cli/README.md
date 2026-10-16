# Float CLI

The CLI is local-first. It stores snippets in `%USERPROFILE%\\.float\\snippets.json` on Windows by default, or in the directory specified by `FLOAT_HOME`.

```powershell
pnpm --dir cli build
node cli/dist/index.js create --title "Portfolio" --body "https://example.com" --tags job,link --pin
node cli/dist/index.js search portfolio --json
node cli/dist/index.js mcp serve
```

To configure a compatible MCP client after building, invoke `node` with the absolute path to `cli/dist/index.js` and arguments `mcp serve`. The server uses stdio only; it does not listen on a network port or send any data to the cloud.
