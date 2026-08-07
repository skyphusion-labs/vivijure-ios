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

| Web page | iOS surface | Status |
|----------|-------------|--------|
| Planner | Stepped flow | **done** |
| Cast | Library + detail | **done** |
| Modules | Projection + install + config | **done** |
| Settings | Connection, prefs, storage, demo, notify | **done** |
| Auth token gate | Keychain onboarding | **done** |

## Planner stages

### Plan -- **done**
Projects CRUD, model picker, slots A–D, plan/refine, scene editor, YAML, session restore.

### Cast & Bundle -- **done**
Preflight + bindings, characterRefs from cast, scene start keyframes, bundle.

### Audio -- **done**
Score-bed, BYO upload, clear, BPM snap, analyze, **suggest score prompt** (`/api/chat` + local scaffold).

### Render -- **done**
Quality tier, motion backend (required pick when 2+), **schema-driven render config**, keyframes-only,
scatter, submit + poll, local notify, open film, audioKey/castLoras/renderOverrides on wire.

### History -- **done**
List, tags/label/delete, load into planner, open artifacts, add-audio/narration, finalize,
**animate cloud / hybrid**, **lock shots**, **regen-shot**.

## Supporting surfaces

| Capability | iOS |
|------------|-----|
| Cast generate-refs, train, `.vvcast` | **done** |
| Module install / install-scope config | **done** |
| Storage usage / reconcile | **done** |
| Demo menu / render / chat | **done** (when host enables) |
| Registry skip install-scope + quality knobs on render panel | **done** |

## Remaining / thin

| Item | Notes |
|------|--------|
| Per-shot cloud model map (`perShot` / hybrid `backends` map) | Defaults only; full per-shot map UI later |
| Expert raw JSON overrides merge | Schema form covers normal path |
| Background fetch when app killed | Local notify during poll only |

## Slice history

| Slice | PR | Notes |
|-------|-----|--------|
| 1 | #3 | Kit + stepper shell |
| 2 | #4 | Scenes, slots, cast media, audio BPM, history open |
| 3 | #5 | Scene starts, scatter, notify, tags, narration, modules, prefs |
| 4 | (this) | Schema render config, lock/regen, animate cloud/hybrid, score suggest, demo |
