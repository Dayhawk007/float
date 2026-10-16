# Float — Product Requirements Document

**Status:** Draft for review  
**Platforms:** Android app plus desktop CLI/MCP companion (first release)  
**Product type:** Open-source floating notes and cross-device clipboard

## 1. Summary

Float gives people a small, persistent workspace that stays available above other Android apps. It is designed for situations where information must be referenced or pasted repeatedly without constantly switching apps: job applications, form filling, social-media publishing, cold outreach, research, and similar workflows.

The product combines:

- Lightweight floating notes that can be minimized and expanded on demand.
- A structured, reusable clipboard rather than a single overwrite-only clipboard entry.
- Optional cross-device sync, so content created on a computer can be used from a phone and vice versa.
- A local-first, community-operated foundation with no AI dependency or AI operating costs.
- A CLI and optional Model Context Protocol (MCP) companion for desktop and developer workflows, letting user-authorized clients such as Codex or Claude search and manage saved material.

## 2. Problem

Android users routinely copy information between apps, but the system clipboard only holds the latest item and requires context switching to retrieve it. Existing note apps are too heavy for quick reference, while generic clipboard managers are often not organized around active workflows or cross-device handoff.

People need a fast way to keep answers, links, templates, identifiers, drafts, and other snippets immediately accessible without obscuring the app they are currently using.

## 3. Product Goals

1. Make frequently used information accessible in two taps or fewer while another app is open.
2. Let a user collect, organize, copy, and reuse snippets with almost no setup.
3. Support safe cross-device handoff without requiring an AI subscription or a paid backend.
4. Keep the overlay subtle, reliable, and respectful of screen space.
5. Build a viable open-source Android release quickly, with a clean path to community contribution.

## 4. Non-goals for v1

- iOS, desktop-native, browser-extension, and web-client applications.
- A desktop graphical companion or always-on-top desktop overlay in the first release; the CLI/MCP companion is the desktop surface.
- Built-in generative AI, paid AI APIs, or automatic content generation.
- Team workspaces, shared editing, real-time collaboration, or enterprise administration.
- Full document editing, rich-text layout, or a general project-management product.
- Automatic capture of sensitive fields such as passwords, payment details, or OTPs.

## 5. Target Users and Core Jobs

| User | Situation | Job to be done |
| --- | --- | --- |
| Job seeker | Completing applications across portals | Keep answers, portfolio links, salary notes, and cover-letter variants ready to paste. |
| Creator/marketer | Posting or replying across platforms | Reuse captions, hashtags, links, and response templates. |
| Freelancer/salesperson | Writing outreach or filling CRM data | Quickly retrieve personalized templates and client details. |
| Student/researcher | Reading while collecting references | Hold quotes, links, and short notes without interrupting reading. |
| Power user | Moving work between PC and mobile | Capture on one device and retrieve on the other. |
| Developer/AI-assisted worker | Working in a terminal or with Codex/Claude | Retrieve approved snippets and save reusable output without manually retyping it. |

## 6. Product Principles

- **Instant before exhaustive:** the most useful item should be easy to reach before every feature is configured.
- **Small footprint:** Float should feel like a helpful layer, not a permanent visual obstruction.
- **Local-first:** core note and clipboard functionality must work offline.
- **User control:** overlays, sync, data retention, and AI-client access are all opt-in.
- **Privacy by default:** minimize collection, expose clear deletion controls, and never read or transmit clipboard contents silently.
- **Open community:** publish the Android app and server/MCP components under a permissive open-source license to be selected before launch.

## 7. User Experience

### 7.1 Floating control

After a user grants Android's overlay permission, Float displays a movable, compact edge handle or bubble. It must:

- Snap to either screen edge and remember its position.
- Be collapsed by default after setup.
- Offer a hide/pause control in the bubble menu and a persistent notification action to restore it.
- Avoid covering taps in the underlying app unless the user expands Float.
- Respect Android system restrictions and explain when an overlay cannot be shown on a given screen.

### 7.2 Expanded panel

Tapping the control opens a compact panel with:

- A search field.
- Pinned and recently used snippets.
- Quick-copy actions.
- A create button for a new snippet.
- A route to the full library.

The panel should dismiss when the user taps outside it or returns to the underlying app. It should open quickly enough to feel like a system utility.

### 7.3 Snippet library

The full-screen app is the management surface. It includes:

- Lists and folders/tags for organization.
- Pinning, editing, deleting, duplicating, and sorting snippets.
- Search across title, content, tags, and list name.
- Recent items and favorites.
- Import/export and sync settings.

## 8. Functional Requirements

### 8.1 Snippets and notes (MVP)

- Users can create, edit, duplicate, archive, restore, and permanently delete plain-text snippets.
- A snippet contains: ID, title, body, tags, list/folder, pinned status, created time, updated time, and last-used time.
- Users can copy a snippet body to the Android clipboard from the expanded panel, library, notification, or share target.
- Users can create a snippet from selected text or shared content through Android's Share sheet.
- Users can pin a small set of high-value snippets to the floating panel.
- The app stores content locally and supports use without a network connection.

### 8.2 Clipboard history (MVP, opt-in)

- Users can explicitly enable clipboard history during onboarding or later in settings.
- When enabled, Float saves newly copied **text** items as a local history entry.
- Users can pause history, clear all history, delete individual entries, and set a retention limit.
- Float must not capture clipboard content from password managers or fields flagged by Android as sensitive when the platform provides that signal.
- Clipboard monitoring and privacy implications must be plainly explained before enabling it.

### 8.3 Organization and retrieval (MVP)

- Users can assign multiple tags and one list/folder to a snippet.
- Search returns results while the user types.
- The overlay's default view prioritizes pinned items, then recently copied/used items.
- A user can reorder pinned items.

### 8.4 Cross-device sync (v1.1)

- Sync is optional and disabled by default.
- A user signs in using a low-friction account mechanism selected during technical design (for example, GitHub OAuth or magic link).
- The app syncs user-authored snippets, organization metadata, and user-selected clipboard-history entries; it must not automatically sync all clipboard history.
- Changes sync in the background when available and resolve conflicts predictably. The initial policy is last-write-wins with an in-app conflict/history record for text changed on multiple devices.
- Users can disconnect a device, erase cloud data, export their data, and continue using the local app.

### 8.5 CLI and MCP companion (first release)

Float ships an optional companion command-line interface and MCP server. Both operate against the user's local Float data by default; optional sync makes the same data available across authorized devices.

#### CLI requirements

- The CLI is installable independently of the Android app and can use a local data store or a signed-in synced account.
- It supports non-interactive commands suitable for shells and scripts: `float search`, `float get`, `float create`, `float update`, `float copy`, `float list`, `float export`, and `float sync`.
- Output defaults to readable text and supports a machine-readable JSON option.
- `float copy` writes only the explicitly selected snippet to the system clipboard.
- Commands that create, update, or delete data print the affected item and require explicit arguments; destructive bulk actions require confirmation unless a deliberate non-interactive flag is provided.
- The CLI stores tokens in OS-secure credential storage where available and must support sign-out, token revocation, and local-data deletion.

#### MCP requirements

The MCP server is launched through the Float CLI (for example, `float mcp serve`) or an equivalent documented local command and can be configured in a compatible client.

Minimum MCP tools:

- `search_snippets(query, tags?, list?)`
- `get_snippet(id)`
- `create_snippet(title, body, tags?, list?)`
- `update_snippet(id, fields)`
- `copy_snippet_to_clipboard(id)` where the connected runtime allows it

Requirements:

- Each client must be explicitly authorized by the user.
- The server exposes only the user's Float data and never other desktop or phone data.
- The initial MCP transport is local stdio. Remote MCP access is deferred until an authenticated, encrypted, revocable-token design has been reviewed.
- Mutating tools use a clear user-configurable consent policy; a safe default requires confirmation for deletion and can require it for writes.

## 9. Technical Direction

### Android app

- Flutter for fast Android delivery and a future cross-platform option, while retaining Android-specific integrations through platform channels.
- Local persistence using SQLite/Drift or an equivalent mature Flutter database layer.
- Android foreground service and `TYPE_APPLICATION_OVERLAY` only where required for the user-enabled floating UI.
- Android Share Target integration for incoming text and links.
- Encrypted local storage for account tokens and sync credentials.

### CLI and MCP companion

- Build the companion as a small cross-platform command-line application, with a stable command and JSON contract that can be scripted.
- Keep the local snippet schema and sync client shared conceptually with the Android app; do not require a GUI desktop application.
- Use standard input/output for the local MCP transport, avoiding a permanently open network port in the first release.
- Package for Windows first, then add macOS and Linux distribution once the command contract is stable.

### Sync service

- Start with a small API and managed database suitable for a free-tier deployment; Vercel can host API endpoints, but persistence and background-sync constraints must be validated before committing to it.
- Keep the API stateless and the data model simple: user, device, snippet, tag, list, sync revision, and revoked token.
- Do not make the server a dependency for basic local notes/clipboard operation.

#### Local development implementation

- The repository contains a local TypeScript account API used to develop the shared account contract before any deployment.
- It provides password registration/login, opaque bearer sessions, and user-scoped snippet CRUD. Android keeps a local cache and synchronizes while the app is open; the CLI and its stdio MCP server use the same account store after sign-in.
- This implementation is not production-ready: it uses a local JSON database and local HTTP for emulator development. TLS, a production database, secure CLI credential storage, email verification, rate limiting, password reset, device/session management, deletion tombstones, and an independent security review are required before any hosted release.

### Open-source delivery

- Separate the repository into `app/`, `cli/`, `server/`, `mcp/`, shared schema/package modules as appropriate, and `docs/` when implementation starts.
- Publish a contribution guide, privacy policy, threat model, and reproducible local-development instructions before public launch.

## 10. Privacy and Security Requirements

- No advertising SDKs, behavioral analytics, or sale of user data.
- Anonymous, opt-in telemetry only if it is ever introduced; the app must remain usable when telemetry is disabled.
- All sync traffic uses HTTPS; credentials are stored only in platform-secure storage.
- The server stores the minimum data needed for synchronization.
- Before launch, decide whether end-to-end encryption is feasible. If it is deferred, document exactly what is encrypted in transit and at rest, who can access server data, and the threat model.
- Offer data export and account/data deletion from within the app.

## 11. Success Metrics

Initial metrics should be privacy-preserving and optional where possible:

- Overlay activation and successful snippet-copy rate.
- Median time from opening Float to copying an item.
- Weekly active users who use Float in at least two separate apps.
- Seven-day and 30-day retention.
- Sync success rate and conflict/error rate after sync launches.
- Crash-free session rate and overlay-permission failure rate.

## 12. Release Plan

### Milestone 0 — Validation and design

- Confirm Android overlay behavior and permission UX on supported Android versions.
- Create interaction wireframes and accessibility review.
- Decide license, repository structure, backend choice, and authentication approach.

### Milestone 1 — Local Android MVP

- Flutter app, onboarding, overlay permission flow, floating control, panel, local snippet CRUD, search, pinning, and Share Target intake.
- Opt-in text clipboard history with retention and clear controls.
- Manual export/import in a documented portable format.

### Milestone 1.5 — Local CLI and MCP companion

- Implement the local data model, CLI search/create/update/copy/export commands, and JSON output.
- Implement the local stdio MCP server with least-privilege read/write tools and client setup documentation for Codex and Claude.
- Add end-to-end tests proving that a note created by the CLI is visible to the MCP server and vice versa.

### Milestone 2 — Private beta

- Test across common OEM Android variants and screen sizes.
- Fix overlay lifecycle, battery, accessibility, and privacy issues.
- Gather qualitative feedback from job seekers, creators, and power users.

### Milestone 3 — Optional sync

- Account linking, device management, cloud backup, conflict handling, and deletion/export flows.

### Milestone 4 — MCP and public launch

- Publish the CLI reference, MCP server/client instructions, permissions model, examples for Codex/Claude, and security review.
- Open-source release, contribution workflow, issue templates, and Play Store launch preparation.

## 13. Acceptance Criteria for MVP

1. A new Android user can grant overlay permission, create a note, pin it, open Float over another app, and copy that note in under two minutes.
2. Float works entirely offline for creating, searching, and copying snippets.
3. The overlay can be moved, collapsed, hidden, and restored without blocking normal use of the underlying app.
4. Clipboard history is off by default and can be enabled, paused, limited, and cleared by the user.
5. A user can receive text or a link through Android Share and save it as a snippet.
6. A user can export all locally stored data and delete individual or all local items.
7. The app presents an understandable privacy explanation before any clipboard monitoring is activated.
8. A desktop user can install the CLI, create and search local snippets, and receive JSON output for automation without creating an account.
9. A user can configure the local MCP server in a supported client and search, read, create, and update only their Float snippets.

## 14. Open Decisions

- Which open-source license best matches the community-governance intent: MIT, Apache-2.0, GPLv3, or another option?
- Is Vercel plus a managed database sufficient for sync latency, background behavior, and cost, or should the sync service use a different host?
- Which account option has the least friction while remaining privacy-respecting?
- What local and cloud encryption model is feasible for the first public version?
- Which Android versions and OEMs make up the explicit support matrix?
- Should the first release store only plain text, or also URLs, images, and files as distinct snippet types?
