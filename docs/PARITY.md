# vivijure-ios -- planner website parity

**Product mandate:** Vivijure for iOS is a **mobile-friendly frontend to the Storyboard Planner**.
Everything a human can do on the studio web planner (`planner` page and its supporting studio
pages) must be possible in this app against the same host CONTRACT.

Authority for routes and JSON shapes: host **`docs/CONTRACT.md`** (`vivijure-cf` /
`vivijure-local`). Authority for web UX stages: host **`public/planner.html`** + related
`public/cast.html`, `settings.html`, `modules.html`.

This file is the living checklist. A feature is **done** only when the native path works end to
end against a live studio (not when a stub exists).

## Studio pages (web nav)

Web chrome (`studio-chrome.js`): **Planner**, **Cast**, **Modules**, **Settings**.

| Web page | iOS surface (target) | Status |
|----------|----------------------|--------|
| Planner (`/planner`) | Primary tabbed / stepped flow | **in progress** (stepper shell + plan/preflight/bundle/render/history) |
| Cast (`/cast`) | Cast library (manage members outside planner) | **in progress** (list/create; media/train later) |
| Modules (`/modules`) | Module host / pipeline visibility | **in progress** (registry dump + quality tiers) |
| Settings (`/settings`) | Module install-scope config + prefs | **in progress** (connection; install config later) |
| Account menu (whoami, email-when-done pref) | Account / prefs sheet | **in progress** (whoami display) |
| Auth token gate | Onboarding: paste/store Bearer token | **done** (Keychain) |

## Planner stages (web stepper)

Web rail (`planner-stepper.js`): **Plan** → **Cast & Bundle** → **Audio** → **Render** → **History**.

### Plan

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Pick / create / delete project | projects CRUD | **in progress** (list/create/select; delete later) |
| Save storyboard to project | `POST …/projects/:id/storyboard` | **done** (after plan) |
| Transient session (no project) | local state only | **done** |
| Select plan model (registry `plan.enhance`) | `GET /api/modules`, models | **in progress** (manual model field + default) |
| Write brief | local + plan body | **done** |
| Optional cast slots A–D (include checkboxes) | cast list + bindings | pending |
| Plan | `POST /api/storyboard/plan` | **done** (kit + UI) |
| Refine | `POST /api/storyboard/refine` | **kit done**; UI later |
| Edit scenes / YAML | local storyboard + optional yaml helper | pending (JSON view only) |
| New session / reset | clear local + optional discard | **done** |
| Resume saved browser session | app: restore last session (Keychain/UserDefaults) | pending (token only) |

### Cast & Bundle

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Preflight (auto + manual) | `POST /api/storyboard/preflight` | **done** (manual) |
| Cast readiness / LoRA preflight UI | cast GET + lora status | **in progress** (list status) |
| Stage training images per slot | upload + cast ref/source paths | pending (kit upload ready) |
| Optional per-scene start keyframes | bundle characterRefs / scene keyframes | pending |
| Bundle | `POST /api/storyboard/bundle` | **done** (empty refs object) |

### Audio

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Generate music bed (if module) | `POST /api/storyboard/score-bed`, poll `GET /api/job/:id` | **in progress** (score-bed + poll) |
| Suggest prompt from storyboard | panel helper (chat/score) | pending |
| Generate narration | score/narration path as panel | pending |
| Upload BYO audio | `POST /api/storyboard/audio-upload` | **kit done**; picker UI later |
| Preview / clear bed | artifact + local state | pending |
| BPM + snap scene durations | local mutation of storyboard | pending |
| Analyze beats (auto) | `POST /api/audio/analyze` | **kit done**; UI later |

### Render

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Quality tier from registry | `GET /api/modules` `render.quality_tiers` | **done** |
| Module render config (schema-driven) | modules config projection | pending |
| Keyframes-only preview | render flags as panel | pending |
| Scatter/gather distributed render | scatter route when eligible | pending |
| Submit film pipeline | `POST /api/storyboard/render` (web door) + kit film path | **done** (storyboard render) |
| Poll until done / failed | poll film or render job | **done** (8s poll loop) |
| Browser notify on finish | local notifications / background fetch | pending |
| Download / open finished film | artifact URL / download | **kit done**; UI later |
| Add audio / narration post-finish | add-audio / add-narration | pending |

### History

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| List renders | `GET /api/storyboard/renders` | **done** |
| Tags / label / lock / delete | PATCH/DELETE renders | pending |
| Reload job into planner | GET render + restore state | pending |
| Open artifacts / keyframes | artifact + artifact-url | **kit done**; UI later |

## Supporting surfaces (full studio, not only stepper)

| Web capability | iOS |
|----------------|-----|
| Cast CRUD, portrait, refs, sources, generate-refs, train LoRA / Wan, import/export `.vvcast` | pending (Cast tab) |
| Module list / install / enable / install-scope config | pending (Modules + Settings) |
| Storage usage / reconcile (if operator) | pending (Settings) |
| Demo mode paths (when host enables) | pending if demo AUTH |
| Registry projection: hide unavailable hooks | pending (must match web) |

## Non-goals (for now)

- Replacing **hosted control-plane** signup/provision (web front door); native may deep-link or paste tenant token.
- Running GPU work on-device; all spend stays on the studio host.
- Closed / proprietary client fork; app stays **AGPL**.

## Done means

1. Feature works on web planner against a studio.
2. Same user outcome works in iOS against the **same** studio token and host.
3. Capability still respects `GET /api/modules` (no hardcoding doors the host does not serve).

Track implementation in PRs; update Status column here as lanes land.
