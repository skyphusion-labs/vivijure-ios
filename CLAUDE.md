# CLAUDE.md -- vivijure-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client for Vivijure Studio** -- the **mobile-friendly frontend to the Storyboard
Planner**. Product mandate (Conrad): **everything possible on the vivijure planner website must be
possible in this app** against the same studio host and API token. Not a viewer-only companion.

Shared Swift package (`VivijureKit`) plus a SwiftUI shell under `App/`.

**Status: skeleton (pre-0.1).** No App Store release. Trust package/tag when a version is cut.

## Parity authority

| Source | Use for |
|--------|---------|
| Host `docs/CONTRACT.md` | Routes, status codes, JSON bodies |
| Host `public/planner.html` + `planner-*.js` | Planner stages and UX gates |
| Host `public/cast.html`, `settings.html`, `modules.html` | Supporting studio pages |
| This repo `docs/PARITY.md` | Checklist of web → iOS gaps |

Do not invent API shapes. Prefer registry projection from `GET /api/modules` for models, hooks, and
quality tiers (same rule as the web panel).

## Related

| Repo | Role |
|------|------|
| [vivijure-cf](https://github.com/skyphusion-labs/vivijure-cf) | Cloudflare studio host + CONTRACT + planner UI |
| [vivijure-local](https://github.com/skyphusion-labs/vivijure-local) | Self-host studio (API parity) |
| [vivijure-control-plane](https://github.com/skyphusion-labs/vivijure-control-plane) | Hosted multi-tenant provisioner (token source) |
| [vivijure-mcp](https://github.com/skyphusion-labs/vivijure-mcp) | Agent MCP door to the same API |
| [vivijure-android](https://github.com/skyphusion-labs/vivijure-android) | Sibling Android app |
| [vivijure-core](https://github.com/skyphusion-labs/vivijure-core) | Shared orchestration types |

## Layout

- `Sources/VivijureKit` -- API clients + models
- `Tests/VivijureKitTests` -- XCTest
- `App/` -- SwiftUI shell (scaffold → stepped planner)
- `docs/PARITY.md` -- website parity checklist
- `docs/ARCHITECTURE.md` -- product + layers

## Implementation order (suggested)

1. Auth: store Bearer token, `whoami`, `GET /api/modules`
2. Projects + plan/refine + storyboard edit
3. Cast library + planner cast bindings + preflight + bundle
4. Audio (upload, score-bed poll, analyze)
5. Render submit/poll + history + artifacts
6. Settings / modules config

## Commands

```bash
swift test
# later: xcodegen generate && xcodebuild ...
```

## Contract rules

- Auth: `Authorization: Bearer <STUDIO_API_TOKEN>` (or tenant token on hosted)
- Branch UI on `GET /api/modules` (registry projection)
- Film / render spend: preflight → bundle → submit → poll (mirror panel)
- Never a plaintext secret in a tracked file
- AGPL-3.0-only; no em-dashes / en-dashes in prose
- Prefer parity with vivijure-android kit + shell when that lane is active

## Conventions

- Conventional Commits
- Aviation-grade `main` (org rulesets)
- Update `docs/PARITY.md` when a web-equivalent feature lands
