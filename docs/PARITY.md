# vivijure-ios -- planner website parity

**Product mandate:** Vivijure for iOS is a **mobile-friendly frontend to the Storyboard Planner**.
Everything a human can do on the studio web planner must be possible in this app against the same
host CONTRACT.

Authority: host **`docs/CONTRACT.md`** + **`public/planner*.js`**. A feature is **done** only when
the native path works end to end against a live studio.

## Studio pages -- **done**

Planner, Cast, Modules, Settings, auth Keychain gate.

## Planner stages -- **done**

| Stage | Notes |
|-------|--------|
| Plan | projects, models, slots A–D, plan/refine, scenes, YAML, session |
| Cast & Bundle | preflight, bindings, characterRefs, scene starts, bundle |
| Audio | score-bed, upload, BPM snap, analyze, suggest prompt |
| Render | quality, motion pick, schema knobs, **expert JSON merge**, scatter, notify |
| History | tags/label/delete, load, artifacts, audio/narration, finalize, **cloud perShot**, **hybrid backends**, lock, regen |

## Supporting -- **done**

Cast generate-refs / train / vvcast; modules install+config; prefs; storage; demo (when enabled).

## Polling / background

| Mechanism | Status |
|-----------|--------|
| Foreground 8s poll loop | **done** |
| Local notification on terminal status | **done** |
| `beginBackgroundTask` while polling / on background | **done** |
| Resume poll after cold launch (session job id) | **done** |
| BGAppRefresh / push-driven poll when killed long-term | not used (entitlement-heavy; still short OS windows) |

## Remaining optional polish

None required for CONTRACT parity of the human planner path. Nice-to-haves only:
App Store packaging, deeper offline cache of artifacts, SharePlay, etc.

## Slice history

| Slice | PR | Notes |
|-------|-----|--------|
| 1 | #3 | Kit + stepper shell |
| 2 | #4 | Scenes, slots, cast media, audio BPM |
| 3 | #5 | Scene starts, scatter, notify, modules, prefs |
| 4 | #6 | Schema config, lock/regen, animate, score suggest, demo |
| 5 | (this) | Expert JSON merge, per-shot cloud/hybrid maps, resume + background poll |
