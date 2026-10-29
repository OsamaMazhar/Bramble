---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 01-04-PLAN.md
last_updated: "2026-08-19T14:49:09.647Z"
last_activity: 2026-08-19
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 5
  completed_plans: 4
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-18)

**Core value:** Ad-free YouTube on my device, rebuildable against the next YouTube version with one command.
**Current focus:** Phase 01 — build-baseline-and-install-gate

## Current Position

Phase: 01 (build-baseline-and-install-gate) — EXECUTING
Plan: 5 of 5
Status: Ready to execute
Last activity: 2026-08-19

Progress: [████████░░] 80%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01 P1 | 10min | 2 tasks | 6 files |
| Phase 01 P02 | 27min | 2 tasks | 12 files |
| Phase 01 P3 | 20min | 2 tasks | 1 files |
| Phase 01 P4 | 12min | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Research's Phase 6 (additive polish) dropped from v1 — every item in it is already listed as v2 in REQUIREMENTS.md and carries no REQ-ID
- [Roadmap]: 6 phases against a `coarse` target of 3–5 — persistence/networking and mux/video wiring must not be merged, and the two gate phases cannot be absorbed into the work they gate
- [Roadmap]: Phases numbered 1–6; research/SUMMARY.md numbers the same phases 0–5 (roadmap Phase N = research Phase N−1)
- [Phase 01]: Deleted bramble/control and bramble/YouTubeX.plist rather than updating them — No consumer in MODULES=jailed packaging pipeline
- [Phase 01]: Pinned THEOS_SHA/THEOS_JAILED_SHA/YOUTUBEHEADER_SHA to real HEAD commits resolved via git ls-remote — Reproducibility pin (D-07) reflects actual repo state at execution time, not stale research-doc values
- [Phase 01]: Corrected IOS_SDK_VERSION 17.5 -> 16.5 in bramble.config.example — theos/sdks does not host 17.5; 16.5 is the newest version it actually has, verified via its GitHub Contents API
- [Phase 01]: bootstrap-toolchain.sh idempotency sentinel changed to $THEOS/makefiles/common.mk — the plan-cited $THEOS/bin/theos-set-variables.sh does not exist anywhere in current Theos (HEAD 5280bd0), which would have forced a full re-clone on every run
- [Phase 01]: package.sh's toolchain-bootstrap sentinel set to $THEOS/makefiles/common.mk (not the plan-cited theos-set-variables.sh) -- carries forward Plan 01-02's established fix
- [Phase 01]: package.sh never echoes INPUT_IPA_SOURCE's resolved value to console or manifest, extending T-01-07's non-disclosure rule beyond just the manifest file
- [Phase 01]: Task 1 (D-12 synthetic version-bump proof) reported as expected block, not failure -- no real INPUT_IPA_SOURCE supplied yet (same operator dependency as Plan 01-03); procedure documented verbatim in SUMMARY for one-pass execution once input exists
- [Phase 01]: No new permanent script committed for the synthetic-bump procedure -- plan objective states package.sh is the thing being tested; procedure recorded as copy-pasteable steps in the plan Summary instead

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1] **PKG-05 is a gate.** Bundle-ID-bound sign-in is community inference, not proven mechanism. If sign-in survives a changed bundle ID, the "no side-by-side install" Out of Scope entry and the matching Key Decision both reopen.
- [Phase 2] **DL-01 is the download gate.** If SABR is enforced, `adaptiveFormats[].url` is simply absent and Phases 4–6 need redesigning before they are planned.
- [Phase 1] theos-jailed is ~3 years dormant and its Substrate download depends on one unmaintained host. Vendor the extracted `CydiaSubstrate.framework` rather than fetching at build time.
- [Phase 6] Codec ceiling only partly characterised — whether wanted resolutions are VP9/AV1-only is unmeasured, and if any tier serves HLS, AVFoundation offers no path to `.mp4`. De-risked by logging `mimeType` during Phase 2.
- [Roadmap] No v1 requirement covers the surface that displays download state — scoped to the minimum inside Phase 5/6 criteria. See ROADMAP.md § Coverage Notes.

### Blockers/Concerns (continued)

- [Platform] **Signed-out playback is unreachable on a re-signed build. Not a bug — do not
  re-investigate.** YouTube 21.x gates `/player` behind App Attest, whose keys derive from the
  app's `application-identifier`. Any developer/Sideloadly signature rewrites that from
  `EQHXZ8M8AV.com.google.ios.youtube` to the signer's team, so attestation fails and the
  backend returns an error playability status (`PLAYBACK ERROR code=14`, server-authored
  `YTIPlayerErrorMessageRenderer`). Search needs no attestation, which is why it keeps working
  and made this look like a codec or packaging fault for several rounds.

  Evidence, all first-hand on iPhone 15 Pro Max / iOS 26.6 (2026-08-20):
  - Stock App Store YouTube plays signed-out → the target is reachable, but only with Google's
    signature.
  - Bramble with its dylib deleted fails identically → not caused by any hook.
  - **YTKillerPlus 6.0 re-signed with our certificate fails identically** → no shipped tweak
    solves it. YTK ships ad-hoc signed with *Google's* `application-identifier`, Google's
    keychain groups and `group.com.google.YouTube`, and no `embedded.mobileprovision`: it is a
    TrollStore/jailbreak artefact, not a sideload. On those devices the original identity
    survives, so attestation succeeds. iOS 26.6 has neither.
  - Client impersonation is not available as a workaround: `YTIClientInfo` is a shared
    singleton (same pointer across successive `decorateContext:` calls), so rewriting
    `clientName` for player requests rewrites it for every InnerTube request and breaks search
    and thumbnails.

  Consequence: sign-in is not merely a PROJECT.md requirement, it is the only functioning mode.

## Quick Tasks Completed

| Date | Slug | Outcome |
|------|------|---------|
| 2026-08-20 | bramble-settings-section | Bramble settings section in YouTube Settings + 4 toggles (ads, background playback, hold-for-2x on player and Shorts). bramble@8cd1c4e. Partial ADS-07. |
| 2026-08-21 | hide-playlist-next-minibar | Playlist/queue "Next" mini-bar hidden behind BrambleHidePlaylistNext. bramble@f1810dd. Builds clean; device check pending. |
| 2026-10-29 | 261029-kea fullscreen-seekbar-home-indicator | Landscape seek bar lifted clear of the home indicator (YTInlinePlayerBarContainerView setFrame:/setCenter: hooks); relatedVideosPeekingEnabled no longer forced NO. Device-checked on iPhone. |

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-08-19T14:49:09.624Z
Stopped at: Completed 01-04-PLAN.md
Resume file: None
