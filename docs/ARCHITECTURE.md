# Architecture -- vivijure-ios

## Product

**Vivijure for iOS is the mobile-friendly frontend to the Storyboard Planner.**

It is not a reduced "viewer" and not a different product. If the web planner can plan, cast,
bundle, audio, render, and manage history against a studio, the iOS app must be able to do the
same. Supporting studio pages (Cast library, Modules, Settings) are in scope for the same reason:
the website exposes them next to the planner.

Parity checklist: [PARITY.md](PARITY.md).

## Status

**0.1 WIP.** Kit + shell track the web planner CONTRACT end to end (including expert overrides,
per-shot cloud/hybrid maps, poll resume). No App Store release yet.

## Layers

| Layer | Role |
|-------|------|
| `VivijureKit` | HTTP + models for studio CONTRACT (Bearer token). Grow until every planner route the web uses is callable. |
| App shell (`App/`) | SwiftUI: stepped planner UX (Plan / Cast & Bundle / Audio / Render / History) + Cast / Modules / Settings tabs. |
| Session store | Keychain (token) + durable planner state (resume session, like web `localStorage`). |

## Backends

| Deploy | Base URL | Auth |
|--------|----------|------|
| Self-host CF | operator studio hostname | `Authorization: Bearer <STUDIO_API_TOKEN>` |
| Self-host local | `https://…` or tunnel to `vivijure-local` | same |
| Hosted tenant | `https://<slug>.studio.vivijure.com` | tenant API token from control plane |

Wire shapes: **host** `docs/CONTRACT.md`. Do not invent routes. Prefer the same film spend path the
panel and MCP use once sound-door reconciliation settles (see vivijure-mcp PARITY for door notes).

## UX principles (mobile)

- **One step at a time** (match web stepper), not a single endless scroll of desktop density.
- **Registry-driven controls:** populate models, quality tiers, and module config from
  `GET /api/modules`, same as the web panel.
- **Long jobs:** background-friendly poll + local notification when a render finishes (web uses
  browser notifications + optional email pref).
- **Large media:** upload images/audio via multipart or raw body helpers; preview artifacts with
  short-lived URLs.
- **Fail closed** when the host is missing a hook: disable or hide, do not fake success.

## Related stack

- Studio hosts: `vivijure-cf`, `vivijure-local`
- Agent door (same API): `vivijure-mcp`
- Sibling native: `vivijure-android` (same product mandate when that lane opens)
- Hosted multi-tenant: `vivijure-control-plane` (token source for hosted studios)
