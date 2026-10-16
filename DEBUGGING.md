# Float Debugging Rules

This file is mandatory guidance for every feature that crosses a process or device boundary: Android-to-agent sync, CLI/MCP interactions, platform channels, and future local-network discovery.

## Required instrumentation

- Log a structured event at the start and completion of every request on both sides.
- Include the operation, request ID where available, endpoint origin (never a credential-bearing URL), HTTP status, result count when useful, elapsed time, and error type.
- Emit Android client diagnostics through the `FloatPair` log category so they are visible in `adb logcat`; emit local-agent diagnostics to its terminal with the `[float-agent]` prefix.
- Convert transport failures into actionable user messages: whether the agent is reachable, whether the pairing credential expired or was rejected, and the next recovery action.
- Test the success path and at least one rejected or unavailable-peer path before completing a networked feature.

## Never log

- Pairing QR values, manual pairing codes, bearer/device tokens, passwords, or full authorization headers.
- Snippet titles, bodies, clipboard contents, or complete request/response bodies.
- Data that would let someone reconstruct a user's notes from logs.

When an existing feature is changed, add missing logs to both endpoints in the same change. This rule takes precedence over convenience while debugging.
