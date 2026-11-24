# Vivijure iOS

This file is the guide for any coding agent and any contributor. Follow it.

## What this project is

This repo is the AGPL iOS client for Vivijure Studio. It is the mobile frontend for the Storyboard Planner.

Anything the planner website can do must be possible in this app. The app uses the same studio host and the same API token. It is not a viewer-only companion.

The shared package is `VivijureKit`. The SwiftUI shell is under `App/`.

The kit covers core planner CONTRACT routes. The shell has onboarding plus Planner, Cast, Modules, and Settings. There is no App Store release yet. See [README.md](README.md) for status. Do not freeze a version in this file.

## Parity

| Source | Use for |
|--------|---------|
| Host `docs/CONTRACT.md` | Routes, status codes, JSON bodies |
| Host `public/planner.html` and `planner-*.js` | Planner stages and UX gates |
| Host `public/cast.html`, `settings.html`, `modules.html` | Other studio pages |
| This repo [docs/PARITY.md](docs/PARITY.md) | Web gaps on iOS |

Do not invent an API shape. Prefer `GET /api/modules` for models, hooks, and quality tiers. The web panel uses the same rule.

## Related repos

| Repo | Role |
|------|------|
| [vivijure-cf](https://github.com/skyphusion-labs/vivijure-cf) | Cloudflare studio host, CONTRACT, planner UI |
| [vivijure-local](https://github.com/skyphusion-labs/vivijure-local) | Self-host studio (API parity) |
| [vivijure-control-plane](https://github.com/skyphusion-labs/vivijure-control-plane) | Reference hosted provisioner (token source) |
| [vivijure-mcp](https://github.com/skyphusion-labs/vivijure-mcp) | Agent MCP door to the same API |
| [vivijure-android](https://github.com/skyphusion-labs/vivijure-android) | Sibling Android app |
| [vivijure-core](https://github.com/skyphusion-labs/vivijure-core) | Shared orchestration types |

## Layout

- `Sources/VivijureKit` -- API clients and models
- `Tests/VivijureKitTests` -- XCTest
- `App/` -- SwiftUI shell
- [docs/PARITY.md](docs/PARITY.md) -- website parity checklist
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) -- product and layers

## Suggested order

1. Auth: store the Bearer token, call `whoami`, call `GET /api/modules`.
2. Projects, plan, refine, and storyboard edit.
3. Cast library, planner cast bindings, preflight, and bundle.
4. Audio: upload, score-bed poll, and analyze.
5. Render submit, poll, history, and artifacts.
6. Settings and module config.

## Commands

```bash
swift test
xcodegen generate
xcodebuild -project Vivijure.xcodeproj -scheme Vivijure \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The app build matches `.github/workflows/ci.yml`. It needs xcodegen.

## Contract

Send `Authorization: Bearer <STUDIO_API_TOKEN>`, or a tenant token on a hosted studio. Branch the UI on `GET /api/modules`.

Film and render spend follows preflight, then bundle, then submit, then poll. Mirror the panel.

Do not put a secret in a tracked file. The license is AGPL-3.0-only.

Prefer parity with the vivijure-android kit and shell.

Update [docs/PARITY.md](docs/PARITY.md) when a web-equivalent feature lands.

Open a pull request to `main`. Use a Conventional Commit. The body says why.

## Docs

Write Simplified Technical English. Use short sentences. Put one idea in each sentence. Use the active present tense. Use plain words. Use the same word every time.

Do not use an em dash (U+2014). Do not use an en dash (U+2013). Use a comma, a semicolon, parentheses, or two hyphens (`--`).

State the limit next to the capability. Do not turn a measured result into a promise.
