# Phase 1: Build Baseline and Install Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-19
**Phase:** 1-Build Baseline and Install Gate
**Areas discussed:** Config & invocation, Toolchain bootstrap, Build verification, The install gate itself

---

## Config & Invocation

### Q1 — How should the operator supply the input IPA path/URL? (PKG-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Gitignored config file | Committed `bramble.config.example` + gitignored `bramble.config` the script sources | ✓ |
| Env vars only | `YOUTUBE_IPA=... ./build.sh` — nothing to manage, but retyped every run | |
| CLI flags | `./build.sh --ipa <path\|url>` — discoverable, but long invocations | |
| Config file + flag override | Config default, any value overridable by flag | |

### Q2 — Where should the packaging script and its config live?

| Option | Description | Selected |
|--------|-------------|----------|
| Inside `bramble/` | Next to the Makefile it drives; Theos runs there anyway | ✓ |
| At repo root | Keeps the fork byte-close to upstream for clean rebases | |
| Collapse `bramble/` into the parent | One repo, one history — loses `git pull upstream` | |

### Q3 — Where should the YouTube version stamp be visible? (PKG-02, multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Output filename | `Bramble-21.31.3-1.0.0.ipa` — verifiable by `ls` alone | ✓ |
| Theos `PACKAGE_VERSION` | `$(YOUTUBE_VERSION)-$(BRAMBLE_VERSION)`, per research/STACK.md | ✓ |
| Logged at `%ctor` | Device log identifies which build is actually installed | ✓ |
| Build manifest file | Input version, Bramble version, toolchain SHAs, timestamp | ✓ |

**Notes:** All four selected — the manifest is cheap and the four stamps cover file, build system,
runtime, and provenance respectively.

### Q4 — What should a re-run do about a URL-sourced input?

| Option | Description | Selected |
|--------|-------------|----------|
| Cache by version, reuse | Download once, reuse later; `--refetch` forces a clean pull | ✓ |
| Fetch every run | No cache invalidation, but pays ~200 MB per rebuild | |
| Local path only for now | Simplest, but narrows PKG-03's stated allowance of a URL | |

---

## Toolchain Bootstrap

### Q1 — What should the script do about an absent toolchain?

| Option | Description | Selected |
|--------|-------------|----------|
| Preflight check, fail fast | Verify each dep, exit with the fix command | |
| Auto-install everything | Theos, SDK, theos-jailed, YouTubeHeader, gmake check | ✓ |
| Separate setup script | `setup.sh` installs once; `build.sh` only checks | |

**Notes:** Nothing is installed on this machine — `$THEOS` unset, no `~/theos`, `make` is GNU 3.81.
"One command" was taken literally, which then made D-06 (repo-local `$THEOS`) necessary.

### Q2 — How should Bramble get `CydiaSubstrate.framework`?

| Option | Description | Selected |
|--------|-------------|----------|
| Vendor it in the repo | Extract once, commit; build never contacts apt.saurik.com | ✓ |
| Fetch, vendor as fallback | Closest to the reference pipeline, but two paths, one exercised | |
| Fetch only, pin the checksum | No binary in git; still dead the day the host is | |
| Switch Logos to `internal` | Removes the dependency entirely; untested, diverges from every reference | |

**Notes:** This is the mitigation STATE.md already names for its Phase 1 blocker.

### Q3 — Track master or pin the git dependencies?

| Option | Description | Selected |
|--------|-------------|----------|
| Pin all three to SHAs | `--update-toolchain` bumps deliberately | ✓ |
| Track master | Simplest; makes a green build non-reproducible | |
| Pin YouTubeHeader only | Pins the fragile one; theos-jailed is dormant anyway | |

### Q4 — Where should `$THEOS` live?

| Option | Description | Selected |
|--------|-------------|----------|
| Repo-local, self-contained | Gitignored `bramble/.toolchain/theos`; Bramble owns what it creates | ✓ |
| Standard `~/theos` | Documented location, shared — but pinned SHAs in a dir you don't own | |
| Honor `$THEOS` if set, else `~/theos` | Polite to existing setups; weakens the pinning decision | |

---

## Build Verification

### Q1 — Should the script enforce the four post-build acceptance checks?

| Option | Description | Selected |
|--------|-------------|----------|
| Assert and fail the build | No IPA emitted on failure | ✓ |
| Print a checklist | Never blocks; relies on reading output you'll stop reading | |
| Separate verify command | Inspect builds you didn't make; makes the gate opt-in | |
| Assert, with an escape hatch | Same protection plus `--skip-verify` | |

**Notes:** Hard block chosen without an escape hatch. Every one of these failures otherwise
produces an app that installs and launches looking completely normal.

### Q2 — How should the deployment target minimum be set?

| Option | Description | Selected |
|--------|-------------|----------|
| Derive from the input IPA | Read `MinimumOSVersion` at build time | ✓ |
| Pin in config, verify against input | Explicit; needs an edit when YouTube raises its floor | |
| Pin low and forget it | The copied-number-from-a-reference-build the research warned against | |

### Q3 — Which additional checks beyond the four? (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Input is actually decrypted | `LC_ENCRYPTION_INFO_64` `cryptid 0` preflight | |
| Input is stock YouTube | Reject an already-tweaked input or foreign bundle | ✓ |
| Substrate wired correctly | Framework under `Frameworks/`, `@rpath` Substrate load command | |
| Entitlements dumped | `codesign -d --entitlements -` recorded in the manifest | |

**Notes:** Three declined. Recorded in CONTEXT.md § "Considered and declined" so the planner does
not reintroduce them. Residual risk flagged on the decryption check: a FairPlay-encrypted input
packages and installs cleanly, then fails at runtime with nothing to point at.

### Q4 — How to prove criterion 2 with only one input on hand?

| Option | Description | Selected |
|--------|-------------|----------|
| Second real IPA | Only proof that exercises the real path | |
| Synthetic version bump | Copy input, rewrite `CFBundleVersion`, build both, diff | ✓ |
| Assert no hardcoded version | Grep for literal `21.31` and fail | |
| Defer to next release | Leaves the phase's headline promise unverified for months | |

---

## The Install Gate

### Q1 — How should the `%ctor` load line be emitted and retrieved? (PKG-04)

| Option | Description | Selected |
|--------|-------------|----------|
| `os_log`, read via Console.app | No extra tooling; subsystem filter cuts YouTube's noise | ✓ |
| `NSLog` + `idevicesyslog` | Greppable and scriptable; needs libimobiledevice | |
| Log to a file in the container | Survives not watching at launch; proves the write ran, not the load | |

### Q2 — How should the inert build be produced? (PKG-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Build flag, hooks compiled out | `INERT=1` — only the `%ctor` load line compiled in | ✓ |
| Runtime kill switch | Same binary both tests; doesn't isolate a compile/link problem | |
| No dylib at all | Cleanest sign-in baseline; says nothing about injection | |
| Skip inert, test the real build | Fastest; can't attribute a failure without building inert anyway | |

### Q3 — Should Phase 1 run the changed-bundle-ID experiment?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — third install, after both pass | One extra build; a positive result reopens side-by-side install | ✓ |
| Yes — but only if the primary path fails | Spends nothing; leaves the constraint on inference | |
| No — out of scope for Phase 1 | Smallest phase; Gate stays open | |

**Notes:** ROADMAP's Gate note and REQUIREMENTS' "PKG-05 is a gate, not a checkbox" both hinge on
this. A positive result reopens the PROJECT.md Out of Scope entry and Key Decision.

### Q4 — Which signer should Phase 1 standardise on?

| Option | Description | Selected |
|--------|-------------|----------|
| AltStore/SideStore | Automates the 7-day refresh; stable team prefix keeps the keychain alive | ✓ |
| Sideloadly | Named first in PROJECT.md; manual re-sign every 7 days | |
| Both, document either | Most flexible; neither path really tested | |

**Notes:** Three installs are now planned against a free cert's 10-App-IDs-per-7-days quota.

---

## Claude's Discretion

- Script language (shell vs Python), argument parsing, failure-message formatting
- Build manifest layout and cache directory layout
- Whether verification lives in the script or as Makefile targets
- Whether `YouTubeX` → `Bramble` rename happens in this phase
- Install/README contents beyond the mandatory Pitfall 4/5 items

## Deferred Ideas

- Install doc / README with the mandatory Pitfall 4 and 5 items (delete App Store YouTube, disable
  auto-updates, expect dead push and universal links, always re-sign with the same Apple ID)
- Second real YouTube IPA for a genuine cross-version test — revisit at the next release
- Decryption / Substrate-wiring / entitlements checks (declined above)
- CI or GitHub Actions build — every reference pipeline has one; not requested
