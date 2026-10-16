# Float CLI

The CLI is local-first. It stores snippets in `%USERPROFILE%\\.float\\snippets.json` on Windows by default, or in the directory specified by `FLOAT_HOME`.

```powershell
pnpm --dir cli build
node cli/dist/index.js create --title "Portfolio" --body "https://example.com" --tags job,link --pin
node cli/dist/index.js search portfolio --json
node cli/dist/index.js mcp serve
```

## Local account API

The account-sync foundation runs locally during development. Start it from the repository root with `pnpm server:dev`, then register the CLI against it:

```powershell
node cli/dist/index.js auth register --api http://127.0.0.1:8787 --email you@example.com --password a-long-development-password
```

After sign-in, normal CLI commands and `float mcp serve` use the authenticated account store. This is a local development API only; do not expose it to a network or use it for real accounts until TLS, production storage, rate limiting, email verification, and a security review are in place.

To configure a compatible MCP client after building, invoke `node` with the absolute path to `cli/dist/index.js` and arguments `mcp serve`. The server uses stdio only; it does not listen on a network port or send any data to the cloud.
