# Float Client Design System

This document is the source of truth for client-side visual and interaction decisions. Read it before changing Android, overlay, or future client UI. If a proposed UI change conflicts with this document, update this document in the same commit and explain the intent in the build journal.

## Design intent

Float should feel calm, immediate, and lightweight: a quiet utility that is ready when needed and visually absent when it is not. The interface favors useful hierarchy over decoration, with a modern monochrome palette and very little visual weight.

## Visual language

- Use the monochrome palette defined in `app/lib/float_theme.dart`.
  - Warm white (`paper`) is the main canvas.
  - Near-black (`ink`) is reserved for primary actions, active states, and high-contrast surfaces.
  - Muted ink is for supporting copy.
  - Fine neutral lines define boundaries.
- Do not introduce brand colors, gradients, colored status badges, or decorative illustrations without deliberately revising this system.
- Prefer flat surfaces, hairline borders, and contrast over shadows. Elevation should normally be zero.
- Use rounded corners sparingly and consistently: 14–18 px for controls/cards, 20–22 px for modal or overlay panels, and a circle for the compact handle.
- Keep labels compact. Uppercase with subtle letter spacing is appropriate for small utility labels, not long-form body text.

## Layout and hierarchy

- Preserve generous whitespace and a clear primary action. A screen should not feel like a dashboard.
- Keep the main app's content horizontally aligned on a simple 20 px rhythm.
- Use one strong visual priority per view: an action, a current note, or a small set of pinned notes.
- Keep secondary, ephemeral collections (such as clipboard history) out of the main note list; reveal them from a compact adjacent icon in a focused modal.
- Treat note groups as practical navigation, not visual decoration: let people choose an existing group or type a new one in the editor, show them as compact text chips in both the main app and overlay, and retain quiet section labels in the overlay list. Search must span title, content, and group.
- For long utility lists, retain a visible scrollbar and use a compact “show more” control instead of rendering an unbounded feed.
- Pinned content may use an inverted near-black surface to signal its elevated usefulness; ordinary content remains light.
- Make pinning visible at both decision points: a direct pin control on each note card and a clearly labeled toggle in the note editor that explains its floating-overlay effect.
- Empty states should be brief, practical, and local-first in tone. They should guide the next action without adding decoration.

## Motion and interaction

- Motion must clarify a state change: opening/collapsing, search results changing, a note becoming pinned, or a setting toggling.
- Use short transitions (about 180 ms) with `easeOutCubic` for arrivals and a restrained ease-in for exits.
- Avoid looping animation, bouncy physics, lengthy page transitions, or motion that competes with note retrieval.
- Preserve native-feeling Android interaction feedback, but do not add ripples, shadows, or haptics solely for ornament.
- The floating handle must stay easy to see and touch. Dragging snaps horizontally to an edge; tapping expands it; the expanded panel must remain easy to dismiss.
- The compact handle remains borderless and shadowless. On dark content, use a substantial white internal glyph/cue rather than an outer stroke to retain visibility.

## Accessibility and readability

- Keep text and interactive controls at accessible contrast against their surfaces.
- Do not rely on color alone for pinned, enabled, or selected states; include an icon, label, or structural cue.
- Retain clear tooltips and semantic labels for icon-only controls.
- Keep touch targets comfortable even when the visible icon is compact.
- Respect system text scaling and avoid fixed-height text containers that truncate essential content.

## Implementation rules

- Reuse `FloatTheme` tokens instead of hard-coding colors in client widgets.
- Apply the system to both the Flutter app and the Android floating overlay; neither surface should drift into a separate style.
- Prefer standard Flutter Material components styled with theme tokens over large visual dependencies.
- Add or update widget tests when visible labels, empty states, or user flows change.
- Validate UI work with `flutter analyze`, `flutter test`, and an Android debug build when Android/overlay code is involved.

## Change checklist

Before completing a client-side UI change, confirm:

1. It uses the monochrome token set and low-elevation treatment.
2. It preserves a clear primary action and a lightweight visual footprint.
3. Any animation is brief, stateful, and purposeful.
4. Main app and overlay styling remain coherent.
5. This document and `BUILDING.md` were updated if the design direction changed.
