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
| Planner (`/planner`) | Primary tabbed / stepped flow | **done** (stepper + parity slice 3 actions) |
| Cast (`/cast`) | Cast library | **done** (CRUD, media, generate-refs, train, `.vvcast` import/export) |
| Modules (`/modules`) | Module host / pipeline visibility | **done** (projection list, install/enable, install-scope config) |
| Settings (`/settings`) | Prefs + storage + connection | **done** (prefs JSON, storage usage/reconcile, notifications) |
| Account menu (whoami, prefs) | Settings | **done** (whoami + prefs editor) |
| Auth token gate | Onboarding: paste/store Bearer token | **done** (Keychain) |

## Planner stages (web stepper)

Web rail (`planner-stepper.js`): **Plan** → **Cast & Bundle** → **Audio** → **Render** → **History**.

### Plan

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Pick / create / delete project | projects CRUD | **done** |
| Save / load storyboard | project storyboard routes | **done** |
| Transient session | local state | **done** |
| Plan model picker | `GET /api/storyboard/models` | **done** |
| Brief + cast slots A–D | plan body characters | **done** |
| Plan / refine | plan + refine | **done** |
| Scene editor + YAML | local + `POST …/yaml` | **done** |
| Session restore | UserDefaults | **done** |

### Cast & Bundle

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Preflight + castBindings | preflight | **done** |
| Cast readiness (refs / LoRA) | cast list | **done** |
| Training images via bound cast | characterRefs from cast | **done** |
| Per-scene start keyframes | character-ref upload + bundle `sceneStartImages` | **done** |
| Bundle | `POST /api/storyboard/bundle` | **done** |

### Audio

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Score bed + poll | score-bed + job | **done** |
| Upload BYO audio | audio-upload | **done** |
| Clear bed | local | **done** |
| BPM + snap | local mutator | **done** |
| Analyze beats | `/api/audio/analyze` | **done** |
| Suggest score prompt | panel helper | pending (cosmetic) |
| Generate narration (score path) | narration via history mux | **done** (history add-narration) |

### Render

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| Quality tier | modules projection | **done** |
| Motion backend chooser | hooks `motion.backend` | **done** |
| Module render config panel | schema-driven overrides | partial (raw prefs/module config; full schema UI later) |
| Keyframes-only | render flag | **done** |
| Scatter/gather | `POST …/render/scatter` | **done** |
| Submit + poll | storyboard render | **done** |
| Local notify on finish | UserNotifications | **done** |
| Open finished film | artifact-url | **done** |
| Add audio / narration post-finish | history actions | **done** |

### History

| Web capability | CONTRACT / API | iOS |
|----------------|----------------|-----|
| List renders | list | **done** |
| Tags / label / delete | PATCH/DELETE | **done** |
| Load bundle into planner | local restore from row | **done** |
| Open artifacts | artifact-url | **done** |
| Finalize (GPU i2v) | `…/finalize` | **done** |
| Animate cloud / hybrid | animate-* | kit has cloud; hybrid UI later |
| Locked shots / regen-shot | PATCH lockedShots, regen | pending |

## Supporting surfaces

| Web capability | iOS |
|----------------|-----|
| Cast generate-refs + poll | **done** |
| Cast `.vvcast` import/export | **done** |
| Module install / enable / uninstall | **done** (dispatch hosts) |
| Module install-scope config GET/PATCH | **done** (JSON editor) |
| Storage usage / reconcile | **done** |
| Demo mode paths | pending if demo AUTH |
| Registry hide unavailable hooks | partial (controls disabled when empty; full hide later) |

## Slice history

| Slice | PR | Notes |
|-------|-----|--------|
| 1 vertical | #3 | Kit core + stepper shell |
| 2 parity | #4 | Scenes, slots, cast media, audio BPM, history open/label/delete |
| 3 parity | (this) | Scene starts, scatter, notify, tags/reload, narration/audio mux, finalize, generate-refs, vvcast, modules install/config, prefs, storage |
