# Architecture -- vivijure-ios

## Status

**Skeleton.** Shared kit + app shell scaffolding only. No store release.

## Targets

| Layer | Role |
|-------|------|
| `VivijureKit` | HTTP + models for studio CONTRACT (and later control-plane admin if needed) |
| App shell | SwiftUI UI projecting `GET /api/modules` capabilities |

## Backends

- **Self-host / CF studio:** `vivijure-cf` or `vivijure-local` HTTPS + `Authorization: Bearer <token>`
- **Hosted tenants:** `https://<slug>.studio.vivijure.com` with tenant API token from control plane
- **Control plane:** account/provision UI stays web-first; native enroll is future work

Wire shapes: host `docs/CONTRACT.md`. Do not invent routes here.
