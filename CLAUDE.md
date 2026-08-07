# CLAUDE.md -- vivijure-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client for Vivijure Studio** -- native app interface to the same panel API as
`vivijure-cf` / `vivijure-local`. Shared Swift package (`VivijureKit`) plus a SwiftUI shell
(to be expanded under `App/`).

**Status: skeleton (pre-0.1).** No App Store release. Trust package/tag when a version is cut.

## Related

| Repo | Role |
|------|------|
| [vivijure-cf](https://github.com/skyphusion-labs/vivijure-cf) | Cloudflare studio host + CONTRACT |
| [vivijure-local](https://github.com/skyphusion-labs/vivijure-local) | Self-host studio (API parity) |
| [vivijure-control-plane](https://github.com/skyphusion-labs/vivijure-control-plane) | Hosted multi-tenant provisioner |
| [vivijure-mcp](https://github.com/skyphusion-labs/vivijure-mcp) | Agent MCP door to the same API |
| [vivijure-android](https://github.com/skyphusion-labs/vivijure-android) | Sibling Android app |
| [vivijure-core](https://github.com/skyphusion-labs/vivijure-core) | Shared orchestration types |

## Layout

- `Sources/VivijureKit` -- API clients + models
- `Tests/VivijureKitTests` -- XCTest
- `App/` -- SwiftUI shell (scaffold)
- `docs/` -- architecture notes

## Commands

```bash
swift test
# later: xcodegen generate && xcodebuild ...
```

## Contract rules

- Auth: `Authorization: Bearer <STUDIO_API_TOKEN>` (or tenant token on hosted)
- Branch on `GET /api/modules` for capability UI (registry projection)
- Film spend path: preflight → bundle → submit film → poll (mirror panel / MCP)
- Never a plaintext secret in a tracked file
- AGPL-3.0-only; no em-dashes / en-dashes in prose

## Conventions

- Conventional Commits
- Aviation-grade `main` (org rulesets)
- Prefer parity with vivijure-android kit + shell
