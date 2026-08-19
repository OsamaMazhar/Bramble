# Phase 1: Build Baseline and Install Gate - Context

**Gathered:** 2026-08-19
**Status:** Ready for planning

<domain>
## Phase Boundary

An operator-run packaging pipeline that turns a config-supplied decrypted YouTube IPA into an
installable unsigned IPA, plus the on-device proof that the dylib loads and a real Google account
still signs in.

Delivers PKG-01 through PKG-06. Retargets `bramble/Makefile` from upstream YouTube-X's `.deb`
build to `MODULES = jailed`, adds the packaging script and its config, and runs the three device
installs that answer the phase's two open questions (does the dylib load, does sign-in survive).

No tweak behaviour is added or changed in this phase. Hook validation is Phase 2; ad additions are
Phase 3.
</domain>

<decisions>
## Implementation Decisions

### Config & Invocation
- **D-01:** Operator supplies the input IPA through a **gitignored config file** — committed
  `bramble.config.example` plus a gitignored `bramble.config` that the script sources. The example
  is the documentation of every knob. (PKG-03)
- **D-02:** Script and config live **inside `bramble/`**, next to the Makefile they drive. The
  nested repo stays the shippable unit; upstream YouTube-X rebases remain a `Tweak.x`-level merge.
- **D-03:** The YouTube version stamp appears in **all four** places: the output IPA filename
  (`Bramble-<ytversion>-<brambleversion>.ipa`), Theos `PACKAGE_VERSION`, the `%ctor` log line, and
  a build manifest emitted next to the IPA (input version, Bramble version, pinned toolchain SHAs,
  timestamp). (PKG-02)
- **D-04:** A URL-sourced input is **cached by version and reused** on later runs, with a
  `--refetch` flag to force a clean pull. Rebuilds during Phases 2–3 must not re-download ~200 MB.

### Toolchain Bootstrap
- **D-05:** The script **auto-installs the whole toolchain** — Theos, the iOS SDK, theos-jailed,
  YouTubeHeader, and a GNU make check. "One command" means one command on a bare machine. Nothing
  is currently installed here (`$THEOS` unset, no `~/theos`, `make` is 3.81).
- **D-06:** `$THEOS` is **repo-local and self-contained** (gitignored, e.g.
  `bramble/.toolchain/theos`). Auto-install must not perform surgery on a shared machine-global
  toolchain, and pinned SHAs are only safe in a directory Bramble exclusively owns.
- **D-07:** Theos, theos-jailed and YouTubeHeader are all **pinned to known-good SHAs** recorded in
  config. `--update-toolchain` bumps them deliberately. Reproducibility a year out is the point of
  the script; YouTubeHeader is hand-maintained and a header removal breaks the build silently.
- **D-08:** `CydiaSubstrate.framework` is **vendored into the repo** (extract once, commit under
  `bramble/vendor/`). The build never contacts `apt.saurik.com`. This is the mitigation STATE.md
  already names for its Phase 1 blocker.

### Build Verification
- **D-09:** The four research-converged acceptance checks **assert and fail the build** — no IPA is
  emitted on failure. Every one of these failures otherwise produces an app that installs and
  launches looking completely normal.
  1. `otool -L` on the final dylib — no `/var/jb`, no `/Library/MobileSubstrate`
  2. `otool -l` on the host binary — `LC_RPATH @executable_path/Frameworks` present and
     `LC_LOAD_WEAK_DYLIB @rpath/Bramble.dylib` (**weak** — `ANALYSIS.md` records the wrong one)
  3. `PlugIns/` absent from the packaged bundle (PKG-06)
  4. `MinimumOSVersion` **read** from the input, never assumed
- **D-10:** Deployment target minimum is **derived from the input IPA's `MinimumOSVersion`** at
  build time, not pinned. Nothing hardcoded; a future YouTube that raises its floor just works.
  (Teardown artifact reads `16.0`, but it is a repack — read the real input.)
- **D-11:** One additional check is enforced: **the input is stock YouTube** — reject an input that
  already carries an injected dylib or a foreign bundle (e.g. the `YTKPlus.bundle` in
  `work/Payload/YouTube.app`).
- **D-12:** Criterion 2 is proven by **synthetic version bump** — copy the input, rewrite
  `CFBundleVersion`/`CFBundleShortVersionString` to a fake newer value, build both, diff the
  outputs. No second real IPA required to close the phase.

### The Install Gate
- **D-13:** The `%ctor` load line is emitted via **`os_log`** under a Bramble subsystem/category and
  read in **macOS Console.app** over USB. No extra tooling; the subsystem filter cuts YouTube's log
  noise. Its **absence** is the diagnostic separating "didn't load" from "loaded but hooks missed".
  (PKG-04)
- **D-14:** The inert build is produced by a **build flag with hooks compiled out** —
  `INERT=1` emits a dylib containing only the `%ctor` load line, no `%hook` blocks. This proves the
  packaging and injection path in isolation while still proving the dylib loaded, which a
  dylib-free build cannot do.
- **D-15:** Phase 1 **runs the changed-bundle-ID experiment** as a third install, after the inert
  and live builds both sign in on `com.google.ios.youtube`. A positive result reopens side-by-side
  install and the matching Key Decision in PROJECT.md. Costs one App ID from the free-cert quota.
- **D-16:** The documented signer is **AltStore/SideStore**, not bare Sideloadly — it automates the
  7-day profile refresh, and a stable team prefix is what keeps the keychain (and the signed-in
  session) alive across later phases.

### Sign-in test order (PKG-05, the phase gate)
1. Inert build (`INERT=1`) → install → sign in. A failure here is **packaging**.
2. Live build → install → sign in. A failure here is **a hook**.
3. Changed-bundle-ID build → install → sign in. Answers the Gate question.

### Claude's Discretion
- Script language (shell vs Python), argument parsing, and failure-message formatting.
- Exact layout of the build manifest and the cache directory.
- Whether the four verification checks live in the script or as Makefile targets.
- Whether the tweak is renamed `YouTubeX` → `Bramble` in this phase or later (the Makefile retarget
  makes it near-free here; `research/STACK.md` already assumes `TWEAK_NAME = Bramble`).
- Contents of the install/README doc, beyond the mandatory items in Deferred → Install doc below.

### Considered and declined (do not re-add)
These were offered as build-time checks and deliberately left out. The planner should not
reintroduce them without asking:
- **Decryption check** (`LC_ENCRYPTION_INFO_64` `cryptid 0` on the input binary). Note the residual
  risk: a FairPlay-encrypted input packages and installs cleanly, then fails at runtime with
  nothing to point at.
- **Substrate wiring check** (framework present under `Frameworks/`, Substrate load command reads
  `@rpath/...`) — partially covered by D-09's `otool -L` assertion.
- **Entitlements dump** (`codesign -d --entitlements -` recorded in the manifest), which
  `research/SUMMARY.md` §Phase 0 asks for as evidence.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope and requirements
- `.planning/PROJECT.md` — constraints (bundle ID, free-cert install, no hardcoded version),
  Key Decisions table, Out of Scope
- `.planning/REQUIREMENTS.md` § Packaging & Install — PKG-01…PKG-06 verbatim, plus
  "PKG-05 is a gate, not a checkbox"
- `.planning/ROADMAP.md` § Phase 1 — five success criteria and the Gate note

### Packaging mechanics (the authoritative source for this phase)
- `.planning/research/STACK.md` § "Makefile shape for Bramble" — the target Makefile, the exact
  `make package THEOS_PACKAGE_SCHEME=rootless IPA=... FINALPACKAGE=1` invocation, and the two
  non-obvious requirements (`mkdir -p $THEOS/lib/iphone/rootless`, GNU make)
- `.planning/research/STACK.md` § "Toolchain setup" — the install commands D-05 automates
- `.planning/research/STACK.md` § "Exact packaging mechanics" / "Why the fork" — why
  `qnblackcat/theos-jailed` and not upstream (`--weak`, `--no-strip-codesig`, `_CodeSignature`
  removal, `REMOVE_EXTENSIONS`)
- `.planning/research/SUMMARY.md` § Conflicts Resolved #1 — `THEOS_PACKAGE_SCHEME=rootless`
  adjudicated, with the three-part acceptance test D-09 implements
- `.planning/research/SUMMARY.md` § "Phase 0: Build baseline and install gate" — the phase's
  deliverables and acceptance list as research framed them

### The sign-in gate
- `.planning/research/PITFALLS.md` § "VERDICT FIRST: Google sign-in in a re-signed build" — what is
  verified vs. inferred; read before treating the bundle-ID rule as fact
- `.planning/research/PITFALLS.md` § Pitfall 4 — bundle-ID collision; App Store YouTube must be
  deleted first
- `.planning/research/PITFALLS.md` § Pitfall 5 — free-cert limits: 7-day expiry, 3 concurrent apps,
  **10 App IDs per rolling 7 days** (three installs are planned), stripped entitlements
- `.planning/research/PITFALLS.md` § Pitfall 10 — the wrong packaging scheme failure mode

### Existing code
- `bramble/Makefile` — current state: upstream's `.deb` build, must be retargeted
- `bramble/Tweak.x` — byte-identical to upstream YouTube-X main; `%ctor` goes here
- `bramble/PLAN.md` — **superseded**, but its "What the draft got wrong" list records six errors not
  to repeat (hand-rolled packaging, `ldid`, header repo name, three-vs-four ad additions)
- `ANALYSIS.md` — teardown of the reference build. **Contains one known error**: it records
  `LC_LOAD_DYLIB` where the truth is `LC_LOAD_WEAK_DYLIB`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bramble/Makefile` — upstream YouTube-X jailbreak Makefile. Has `ARCHS = arm64`,
  `TWEAK_NAME = YouTubeX`, `Tweak.x` file list, `-fobjc-arc`. Missing everything jailed packaging
  needs: `MODULES = jailed`, `BUNDLE_ID`, `DISPLAY_NAME`, `REMOVE_EXTENSIONS`, `CODESIGN_IPA`,
  `PACKAGE_VERSION`. Target is `iphone:clang:latest:11.0` on the non-rootless branch.
- `bramble/Tweak.x` — 268 lines, ~14 `%hook` blocks, no `%ctor` yet. D-14's `INERT=1` needs one
  `#if` around the hook body plus a new `%ctor`.
- `bramble/control` — still PoomSmart's `com.ps.ytx` metadata. Irrelevant to a jailed IPA build;
  either update or drop.
- `bramble/.gitignore` — already ignores `.theos`, `packages`. Needs the config file, the
  repo-local toolchain dir, and the input cache added.

### Established Patterns
- `bramble/` is a nested git repo (`origin` → OsamaMazhar/Bramble, `upstream` →
  PoomSmart/YouTube-X) and is listed in `.planning/config.json` under `planning.sub_repos`.
  Commits for this phase's tweak/build changes belong in that repo.
- `.planning/config.json` sets `planning.commit_docs: false` for sub-repos — planning artifacts
  stay in the parent.

### Integration Points
- The packaging script is the only new entry point. It drives `make package` in `bramble/` and
  emits into a gitignored output dir.
- `%ctor` in `Tweak.x` is the single integration point for the load-line signal (D-13) and the
  version stamp (D-03).

### Environment as found (2026-08-19)
- `$THEOS` unset, no `~/theos`, no `gmake` — `make` is GNU Make 3.81. D-05 must handle all of this.
- `work/Payload/YouTube.app` is **not a usable input**: it is the YTKillerPlus repack
  (`YTKPlus.bundle` present, `PlugIns/` already stripped, `CFBundleVersion = 21.31.3`,
  `MinimumOSVersion = 16.0`, `CFBundleIdentifier = com.google.ios.youtube`). A clean decrypted
  stock YouTube IPA still has to be supplied via config, and D-11's stock-input check would reject
  this directory by design.
</code_context>

<specifics>
## Specific Ideas

- The `%ctor` log line should carry the YouTube version the build was made against (D-03), so a
  device log identifies which build is actually installed — not just which file is on disk.
- Verification failures should block hard rather than warn (D-09). The phase's dominant risk is
  silent success: a broken build that installs and launches looking completely normal.
- The three-install sequence is ordered so each failure has exactly one attributable cause
  (packaging → hook → bundle ID). Do not collapse it.
</specifics>

<deferred>
## Deferred Ideas

- **Install doc / README** — not discussed in depth, but Pitfalls 4 and 5 make several items
  mandatory whenever it is written: delete the App Store YouTube first (bundle-ID collision), the
  container is wiped, disable automatic app updates or the App Store will try to reclaim the
  bundle ID, expect push notifications and youtube.com universal links to be dead (entitlements
  stripped on a free cert), always re-sign with the **same** Apple ID or the keychain prefix
  changes and the session is lost.
- **Second real YouTube IPA** for a genuine cross-version test — D-12 uses a synthetic bump for
  now. Revisit when the next YouTube release ships.
- **Decryption / Substrate-wiring / entitlements checks** — see Considered and declined above.
- **CI or GitHub Actions build** — every reference pipeline has one; not requested, and the
  audience is a handful of people.
</deferred>

---

*Phase: 1-Build Baseline and Install Gate*
*Context gathered: 2026-08-19*
