# Product Scope

## Problem

CLI coding agents are powerful, but they pull attention away from the editor and terminal. Developers need a lightweight control surface to monitor work, approve actions, answer questions, and return to the right session quickly.

## Target User

- macOS developers using terminal-based coding agents daily
- Users running more than one agent or more than one terminal session
- Users who care about low latency and native behavior

## MVP Goal

Deliver a native macOS companion that proves the end-to-end loop:

1. Receive local agent events
2. Render live session state in a notch or floating top bar
3. Handle permission approval and question answering
4. Bring the user back to the correct terminal session

## Supported Boundary

For now, the product boundary is fixed to these four surfaces only:

- `Codex`
- `Claude Code`
- `Terminal.app`
- `Ghostty`

Anything else is explicitly out of scope until the user chooses to expand the boundary.

## v0.1 Scope

- One real agent integration only: `Codex`
- One real terminal verification target pair: `Terminal.app` and `Ghostty`
- `Claude Code` remains in product scope, but not in implementation scope yet
- Mock event source first, then replace with real hooks
- One active permission request at a time
- Basic session list and detail panel
- External-display fallback bar for machines without a notch

## Deferred

- Multi-agent support from day one
- Expanding support to more terminal apps
- Expanding support to more code agents
- Pixel-perfect terminal split targeting across many terminal apps
- Sound packs, themes, and onboarding polish
- Analytics, accounts, sync, or cloud features

## Success Criteria

- A local mock event can appear in the overlay within one second
- Approval and answer actions round-trip back to the source process
- The app can restore focus to the owning terminal window reliably
- Idle resource usage remains low enough for all-day background use
