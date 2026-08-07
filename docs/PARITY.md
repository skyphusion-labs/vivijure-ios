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
| Planner (`/planner`) | Primary tabbed / stepped flow | **in progress** (full stepper + scene editor + slots + refine) |
| Cast (`/cast`) | Cast library (manage members outside planner) | **in progress** (CRUD, media upload, train LoRA; export `.vvcast` later) |
| Modules (`/modules`) | Module host / pipeline visibility | **in progress** (registry dump + quality tiers) |
| Settings (`/settings`) | Module install-scope config + prefs | **in progress** (connection; install config later) |
| Account menu (whoami, email-when-done pref) | Account / prefs sheet | **in progress** (whoami display) |
| Auth token gate | Onboarding: paste/store Bearer token | **done** (Keychain) |

## Planner stages (web stepper)

Web rail (`planner-stepper.js`): **Plan** → **Cast & Bundle** → **Audio** → **Render** → **History**.

### Plan

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Pick / create / delete project | projects CRUD | **done** |
| Save storyboard to project | `POST …/projects/:id/storyboard` | **done** |
| Load project storyboard | `GET …/projects/:id` | **done** |
| Transient session (no project) | local state only | **done** |
| Select plan model (registry) | `GET /api/storyboard/models` | **done** (picker + manual fallback) |
| Write brief | local + plan body | **done** |
| Optional cast slots A–D (include + inline or bind) | cast list + bindings | **done** |
| Plan | `POST /api/storyboard/plan` | **done** (kit + UI + characters) |
| Refine | `POST /api/storyboard/refine` | **done** (kit + UI) |
| Edit scenes (prompt, seconds, slots, dialogue) | local storyboard | **done** |
| YAML preview | `POST /api/storyboard/yaml` | **done** |
| New session / reset | clear local + optional discard | **done** |
| Resume saved browser session | UserDefaults session blob | **done** (brief, board, slots, keys) |

### Cast & Bundle

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Preflight (auto + manual) | `POST /api/storyboard/preflight` | **done** (manual + castBindings) |
| Cast readiness / LoRA preflight UI | cast GET + lora status | **in progress** (list + ref counts) |
| Stage training images per slot | cast portrait/ref via bound members | **done** (from cast library; inline file stage later) |
| Optional per-scene start keyframes | bundle `sceneStartImages` | pending (kit accepts; UI later) |
| Bundle | `POST /api/storyboard/bundle` | **done** (characterRefs from bound cast) |

### Audio

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Generate music bed (if module) | `POST /api/storyboard/score-bed`, poll `GET /api/job/:id` | **done** |
| Suggest prompt from storyboard | panel helper (chat/score) | pending |
| Generate narration | score/narration path as panel | pending |
| Upload BYO audio | `POST /api/storyboard/audio-upload` | **done** (file importer) |
| Preview / clear bed | artifact + local state | **in progress** (clear; preview later) |
| BPM + snap scene durations | local mutation of storyboard | **done** |
| Analyze beats (auto) | `POST /api/audio/analyze` | **done** |

### Render

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Quality tier from registry | `GET /api/modules` `render.quality_tiers` | **done** |
| Module render config (schema-driven) | modules config projection | pending |
| Keyframes-only preview | render flags as panel | **done** |
| Scatter/gather distributed render | scatter route when eligible | pending |
| Submit film pipeline | `POST /api/storyboard/render` | **done** |
| Poll until done / failed | poll film or render job | **done** (8s poll loop) |
| Browser notify on finish | local notifications / background fetch | pending |
| Download / open finished film | artifact URL / download | **done** (open via artifact-url) |
| Add audio / narration post-finish | add-audio / add-narration | **kit** `addAudioToRender`; UI later |

### History

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| List renders | `GET /api/storyboard/renders` | **done** |
| Tags / label / lock / delete | PATCH/DELETE renders | **in progress** (label + delete; tags/lock later) |
| Reload job into planner | GET render + restore state | pending |
| Open artifacts / keyframes | artifact + artifact-url | **done** |

## Supporting surfaces (full studio, not only stepper)

| Web capability | iOS |
|----------------|-----|
| Cast CRUD, portrait, refs, sources, train LoRA / Wan | **done** (generate-refs UI later; import/export `.vvcast` later) |
| Module list / install / enable / install-scope config | pending (Modules + Settings) |
| Storage usage / reconcile (if operator) | pending (Settings) |
| Demo mode paths (when host enables) | pending if demo AUTH |
| Registry projection: hide unavailable hooks | pending (must match web) |

## Slice history

| Slice | PR | Notes |
|-------|-----|--------|
| 1 vertical | #3 | Kit core + stepper shell plan/preflight/bundle/render/history |
| 2 parity | (this) | Scenes, slots A–D, refine, cast media/train, audio upload+BPM, history open/label/delete, session restore |
