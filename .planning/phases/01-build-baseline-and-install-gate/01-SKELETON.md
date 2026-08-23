# Walking Skeleton — Bramble

**Phase:** 1
**Generated:** 2026-08-19

## Capability Proven End-to-End

> One sentence: the smallest capability that exercises the full stack.

A config-supplied decrypted YouTube IPA, run through one script (`bramble/package.sh`), produces a
verified unsigned IPA that installs on a real device via AltStore/SideStore, loads its dylib
(proven by a `com.bramble.tweak` log line in Console.app), and lets a real Google account sign in.

This project has no database, no HTTP routing, and no UI of its own — the "full stack" here is the
build-to-device pipeline: **operator config → toolchain bootstrap → `make package` → four
hard-fail verification checks → unsigned IPA → sideload install → `%ctor` load line → OAuth
sign-in.** Every later phase (hook validation, ad additions, downloads) builds *inside* the app
this skeleton proves can be built, installed, and signed into — it does not touch this chain again.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Build system | Theos + Logos, `MODULES = jailed` (qnblackcat/theos-jailed fork) | The only fork that emits `--weak --no-strip-codesig` injection and strips extensions — required for a free-cert sideload, not a style preference. See `.planning/research/STACK.md` "Why the fork". |
| Hooking runtime | CydiaSubstrate.framework via the `MobileSubstrate` Logos generator, vendored in-repo | Pure ObjC swizzling (`MSHookMessageEx`), works sandboxed; vendoring removes the apt.saurik.com single point of failure (D-08) |
| Toolchain location | Repo-local, gitignored: `bramble/.toolchain/theos` | D-06 — no surgery on a shared machine-global `~/theos`; pinned SHAs are only safe in a directory Bramble exclusively owns |
| Toolchain pinning | Theos, theos-jailed, YouTubeHeader all pinned to commit SHAs recorded in `bramble/bramble.config` | D-07 — reproducibility a year out is the point of the packaging script; all three are unmaintained or hand-maintained enough that `master` drift breaks silently |
| Config surface | `bramble/bramble.config` (gitignored) sourced from a committed `bramble.config.example` | D-01 — the example is the documentation of every knob; the real file may carry a credentialed input URL and must never reach git |
| Signing | Ship unsigned (`CODESIGN_IPA = 0`); AltStore/SideStore sign at install time, not bare Sideloadly | D-16 — AltStore/SideStore automate the 7-day free-cert profile refresh; a stable team prefix keeps the signed-in session alive across later phases |
| Bundle ID | `com.google.ios.youtube`, unless Plan 01-05's Task 3 experiment proves otherwise | PROJECT.md's hard constraint; the phase's own Gate question is whether this constraint is even necessary — answered on-device, not assumed |
| Version stamping | Read `CFBundleVersion`/`MinimumOSVersion` from the input at build time; never hardcoded; stamped into 4 places (IPA filename, `PACKAGE_VERSION`, `%ctor` log line, build manifest) | D-03, D-10 — the packaging script's entire value proposition is surviving the next YouTube release without a code change |
| Directory layout | Everything lives inside `bramble/`: `Makefile`, `Tweak.x`, `package.sh`, `bootstrap-toolchain.sh`, `bramble.config(.example)`, `vendor/CydiaSubstrate.framework/`, `build/` (gitignored output) | D-02 — `bramble/` is a nested git repo and the shippable unit; upstream YouTube-X rebases stay a `Tweak.x`-level merge |

## Stack Touched in Phase 1

Generic Walking Skeleton checklist items have no literal analog in an iOS tweak project. Real
substitutes, in the same order:

- [x] Project scaffold — `bramble/Makefile` retargeted to `MODULES = jailed`; `bramble/Tweak.x`
      gets its first `%ctor` (build/lint/test runner equivalent: `bash -n`/`make -n` static checks
      plus the real `make package` compile in Plan 01-03)
- [ ] Routing — **no analog.** Substitute: `bramble/package.sh`'s CLI flag surface
      (`--refetch`, `--inert`, `--bundle-id`, `--input`) is the one "entry point" this phase adds.
- [ ] Database — **no analog.** Substitute: the build manifest
      (`bramble/build/build-manifest-<ytversion>-<brambleversion>.txt`) is the one persisted record
      this phase produces — input version, Bramble version, pinned toolchain SHAs, timestamp.
- [ ] UI — **no analog.** Substitute: the `%ctor` `os_log` load line under subsystem
      `com.bramble.tweak` is the one observable signal a human confirms on real hardware, playing
      the role a UI interaction would in a web app.
- [x] Deployment — sideload install via AltStore/SideStore to a real device, real Google sign-in
      (Plan 01-05, three ordered installs: inert, live, changed-bundle-ID)

## Out of Scope (Deferred to Later Slices)

- Any hook *behavior* validation (class/selector present-vs-renamed-vs-gone) — Phase 2
- Any ad-blocking addition beyond what upstream YouTube-X already ships unmodified — Phase 3
- Any download/queue/mux code — Phases 4–6
- A second real YouTube IPA for cross-version proof — D-12 uses a synthetic `CFBundleVersion` bump
  instead; revisit when the next real YouTube release ships
- CI/GitHub Actions build — not requested; audience is a handful of people
- Decryption check, Substrate-wiring check, entitlements dump — considered and explicitly declined
  in `01-CONTEXT.md`; do not reintroduce without flagging it as a re-opened question

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its
architectural decisions (bundle ID, toolchain pinning strategy, signing approach, and directory
layout all stay fixed unless Plan 01-05's Task 3 experiment reopens the bundle-ID question):

- Phase 2: Hook-surface validation against 21.31.3 (present/renamed/gone table + startup
  self-check) and the SABR download-gate spike — no packaging changes
- Phase 3: The four ad additions (ad-log, request-layer suppression, companion-ad accessors, wider
  playback-controller coverage), each individually toggleable
- Phase 4: Download foundation — persisted queue before background `NSURLSession`
- Phase 5: Audio-only download, end to end
- Phase 6: Standalone mux, then video download
</content>
