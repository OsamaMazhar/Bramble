# Roadmap: Bramble

## Overview

Bramble starts by proving it can exist: a dylib that demonstrably loads into a re-signed YouTube
build on a free cert, with a real Google account still able to sign in. Only then does it validate
every hook point against 21.31.3 and answer the one question that decides whether downloads are
buildable at all (does the player response still carry media URLs). With those two gates passed,
the ad delta over upstream lands in one cheap phase, and downloads are built in the order research
proved matters: persistence before networking, audio before video, muxer before wiring. The
endpoint is an ad-free YouTube on the author's device that downloads audio and video, rebuildable
against the next YouTube release with one command.

**Note on numbering:** `research/SUMMARY.md` numbers its phases 0–6. This roadmap numbers them 1–6
(roadmap Phase N = research Phase N−1). Research's Phase 6 (Additive polish) is not in this
roadmap: every item in it — thumbnails, Shorts, audio metadata tagging, track selection — is listed
as v2 in `REQUIREMENTS.md` and carries no v1 REQ-ID.

**Phase count vs. granularity:** config sets `coarse` (3–5). This roadmap has 6. The research
sequencing forbids the two merges that would reach 5 — persistence must not fold into networking,
and standalone mux must not fold into video wiring — and Phases 1 and 2 are hard gates whose
outcomes can reshape everything after them, so they cannot be absorbed into the work they gate.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Build Baseline and Install Gate** - One command produces an installable IPA that loads a dylib and still signs in
- [ ] **Phase 2: Hook Validation and the Download Gate** - Every hook point verified against 21.31.3; SABR question answered before any download design
- [ ] **Phase 3: The Four Ad Additions** - Ads not requested, not rendered, not silently unblockable, each hook individually toggleable
- [ ] **Phase 4: Download Foundation** - Queue state on disk first, then one background session that outlives the process
- [ ] **Phase 5: Audio-Only Download** - The first shipped download: a playable `.m4a` that completes in the background
- [ ] **Phase 6: Mux Standalone, Then Video** - A single `.mp4` with tracks combined, honest about the wait before merge

## Phase Details

### Phase 1: Build Baseline and Install Gate

**Goal**: The tweak reaches a real device, and the account it needs still works
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: PKG-01, PKG-02, PKG-03, PKG-04, PKG-05, PKG-06
**Success Criteria** (what must be TRUE):

  1. Operator points config at a decrypted YouTube IPA (local path or URL), runs one command, and gets an installable unsigned IPA out
  2. The same command run against a different YouTube version produces a build stamped with that version, with no file in the repo edited
  3. The build installs on a device signed with a free Apple ID, and `PlugIns/` is absent from the installed bundle
  4. Launching the installed app puts a `%ctor` load line in the device log — its absence is what distinguishes "didn't load" from "loaded but hooks missed"
  5. A real Google account signs in on the installed build, tested with the dylib inert first and present second, so a failure is attributable to packaging rather than a hook

**Plans**: 5 plans (4 waves)

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Retarget Makefile to MODULES=jailed, add %ctor load line + INERT guard to Tweak.x, write bramble.config.example
- [ ] 01-02-PLAN.md — Vendor CydiaSubstrate.framework, write bootstrap-toolchain.sh (pinned Theos/theos-jailed/YouTubeHeader install)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 01-03-PLAN.md — bramble/package.sh: input resolution, stock-input check, version stamping, build invocation, D-09 verification checks, manifest

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 01-04-PLAN.md — Synthetic version-bump proof (D-12) and bramble/README.md install doc

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 01-05-PLAN.md — Device gate: inert / live / changed-bundle-ID install + sign-in (checkpoint, autonomous:false)

**Gate:** Criterion 5 is a device test, not a checkbox. `PROJECT.md` commits to bundle ID
`com.google.ios.youtube` on the strength of community inference, not proven mechanism. If sign-in
survives a changed bundle ID, the "no side-by-side install" entry in Out of Scope reopens and the
Key Decision is revisited. If sign-in fails outright, the project is in question — which is why
this phase is first and cheap.

### Phase 2: Hook Validation and the Download Gate

**Goal**: No later phase builds on a hook point or a data field that was never verified to exist
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: ADS-01, ADS-02, DL-01
**Success Criteria** (what must be TRUE):

  1. A present/renamed/gone table covers every class and selector the tweak hooks on 21.31.3, each entry checked against the real binary rather than against `hookmap.txt`'s heuristic pairings
  2. Launching with a deliberately broken hook entry produces a visible startup warning naming the class or selector that failed to resolve, instead of the silent no-op that is the default failure mode
  3. A dumped live player response shows whether `adaptiveFormats[].url` is present on `avc1` + `mp4a` formats, a plain download task against one yields playable bytes, and the `mimeType` codec strings seen across ~20 real videos are recorded

**Plans**: TBD

**Gate:** Criterion 3 is the download gate. The risk is SABR, which presents as the `url` field
being *absent* rather than a request failing. If it is absent, Phases 4–6 need redesigning before
they are planned, not after. This is a one-line check — do not budget engineering time for a
signature descrambler; that is an out-of-app impersonation problem and does not transfer to a tweak
reading a response that already passed attestation.

### Phase 3: The Four Ad Additions

**Goal**: Ad targeting is not sent, ad surfaces do not render, and a blocklist break is a two-minute fix
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: ADS-03, ADS-04, ADS-05, ADS-06, ADS-07
**Success Criteria** (what must be TRUE):

  1. With logging enabled, browsing produces a retrievable file recording both blocked and inspected-but-not-blocked renderer IDs and class names — logging both is what makes a *rename* detectable, not just a removal — and with it off, nothing is written
  2. An InnerTube request captured during playback carries no ad context, because `decorateContext:` was suppressed at the request layer
  3. In-player companion, shopping, and app-promo surfaces are absent on videos that previously showed them
  4. No ad plays after a stream reload, refresh, or restore — not only on first load
  5. Any single ad hook can be turned off individually at runtime, so a sign-in or playback regression is bisected without a rebuild

**Plans**: TBD

**Note:** This is *four* additions, not three. `bramble/PLAN.md` predates this roadmap and says
three — it omits ADS-04, request-layer `decorateContext:` suppression, which is genuinely absent
from upstream YouTube-X and present in the closed reference build. Do not propagate the older count.

### Phase 4: Download Foundation

**Goal**: A transfer outlives the process that started it, and the queue describing it outlives it too
**Mode:** mvp
**Depends on**: Phase 2 (independent of Phase 3 — may run in parallel)
**Requirements**: DL-02, DL-03
**Success Criteria** (what must be TRUE):

  1. A transfer started in the app completes while the app is backgrounded
  2. A transfer completes after the system terminates and relaunches the app, with the app reattaching to the existing transfer rather than restarting it
  3. Launching against a hand-crafted stale queue leaves no queue entry without a live task and no file on disk without an owning entry — reconciliation runs in both directions
  4. A user force-quit is recorded as a cancelled transfer rather than a failure, because force-quit cancelling transfers and stopping relaunch is correct system behaviour

**Plans**: TBD

**Ordering (internal to this phase):** persistence before networking. `QueueStore` and launch
reconciliation are built before `TransferService`. Durability retrofitted onto a working in-memory
queue is never complete, and the gaps only appear under process death — which is hard to test into
existence after the fact. Neither half ships user-visible value alone, which is why they are one
phase rather than two.

### Phase 5: Audio-Only Download

**Goal**: The first shipped download — a user gets a playable `.m4a` without keeping the app open
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: DL-04, DL-06, DL-07
**Success Criteria** (what must be TRUE):

  1. A user starts an audio download from a row in the app's existing action sheet
  2. The resulting file is a valid `.m4a` that plays as audio, and the user can get it out of the app
  3. Formats the muxer cannot handle never appear as choices — the codec filter runs when the catalog is built, not when a merge fails
  4. The download completes with the app backgrounded, and its progress is visible when the user returns

**Plans**: TBD
**UI hint**: yes

**Explicitly not in scope:** metadata tagging. Audio-only is the one flow that is fully
background-capable end to end precisely because it has no export pass — the downloaded AAC file is
already a valid `.m4a`. Tagging would add an `AVAssetExportSession` pass that exists solely for
metadata, and that cannot be relied on in the background. Deferred to v2 as a foreground-only
post-step.

### Phase 6: Mux Standalone, Then Video

**Goal**: A video downloads as one playable `.mp4`, and the wait before merging reads as waiting rather than as broken
**Mode:** mvp
**Depends on**: Phase 5
**Requirements**: DL-05, DL-08
**Success Criteria** (what must be TRUE):

  1. The muxer, run against two hand-placed track files, produces a playable `.mp4` with audio and video in sync — proven before any download code is wired to it
  2. A user downloads a video and gets a single `.mp4` that plays with both tracks combined
  3. A video whose two transfers finished while backgrounded is shown as awaiting merge rather than appearing stalled, and merges when the app next comes to foreground
  4. A duration mismatch between the two tracks is caught before muxing, because a mismatch muxes "successfully" into an A/V-desynced file with no error at all
  5. Source track files are deleted only after the export reports complete *and* the output file exists

**Plans**: TBD

**Ordering (internal to this phase):** two independent unknowns — *does AVFoundation accept these
tracks?* and *does the two-leg state machine work?* — must not be debugged at the same time. Build
the muxer standalone first. `AwaitingMerge` is a first-class persisted phase, not a transient: a
pair can sit there for days.

## Coverage Notes

Two success criteria reach slightly past the letter of their requirements. Both are recorded rather
than resolved by inventing REQ-IDs:

- **No v1 requirement covers the surface that shows download state.** DL-07 gives an entry point
  and DL-08 requires that an awaiting-merge item "is shown as such" — which implies somewhere it is
  shown. Phase 5 criterion 4 (progress visible) and Phase 6 criterion 3 (awaiting-merge visible)
  scope that to the minimum: whatever surface DL-08 needs, Phase 5 already needs for progress. If
  a first-class downloads list is wanted, add it as an explicit requirement rather than letting it
  grow inside these two criteria.

- **"Playable" implies retrievable.** DL-04 asks for a playable `.m4a`; a file that cannot leave
  the app is not usefully playable. Phase 5 criterion 2 folds share-out into DL-04 rather than
  adding a separate requirement.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

Phases 3 and 4 both depend only on Phase 2 and are independent of each other — with
`parallelization: true` they may run concurrently.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Build Baseline and Install Gate | 1/5 | In Progress|  |
| 2. Hook Validation and the Download Gate | 0/TBD | Not started | - |
| 3. The Four Ad Additions | 0/TBD | Not started | - |
| 4. Download Foundation | 0/TBD | Not started | - |
| 5. Audio-Only Download | 0/TBD | Not started | - |
| 6. Mux Standalone, Then Video | 0/TBD | Not started | - |
