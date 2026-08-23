# Phase 1: Build Baseline and Install Gate - Pattern Map

**Mapped:** 2026-08-19
**Files analyzed:** 12 (5 modify, 7 new)
**Analogs found:** 5 in-repo (self-referential, "modify in place") / 12 — this phase is
genuinely greenfield for the packaging script, config, verification, and docs. No in-repo
analog exists for any of those; the closest reference for each is cited from
`.planning/research/STACK.md` / `PITFALLS.md` and flagged explicitly below rather than forced.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `bramble/Makefile` | config (build) | batch | itself (current state) + STACK.md target shape | exact (retarget, not greenfield) |
| `bramble/Tweak.x` | source/hook file | event-driven | itself (current state) + Theos `%ctor`/`%init` docs in STACK.md | exact (additive edit, not greenfield) |
| `bramble/control` | config (metadata) | n/a | itself (current state) | exact (decide: update or drop) |
| `bramble/.gitignore` | config | n/a | itself (current state) | exact (additive edit) |
| `bramble/YouTubeX.plist` | config (Substrate filter) | n/a | itself (current state) | exact (decide: drop or rename with `TWEAK_NAME`) |
| `bramble/bramble.config.example` | config | n/a | none in-repo | no analog — see below |
| `bramble/bramble.config` (gitignored) | config | n/a | none in-repo | no analog — generated from `.example` |
| packaging script (name TBD, e.g. `bramble/package.sh`) | script/orchestrator | batch, file-I/O | none in-repo | no analog — external reference only |
| verification checks (embedded in script, or `bramble/verify.sh`, or Makefile targets) | test | batch | none in-repo | no analog — external reference only |
| build manifest (emitted artifact, e.g. `build-manifest.json`) | config (output) | file-I/O | none in-repo | no analog — content spec only (D-03) |
| `bramble/vendor/CydiaSubstrate.framework/` | vendor asset (binary) | file-I/O | none in-repo | no analog — not code, just a destination path (D-08) |
| install doc (e.g. `bramble/README.md` or `docs/INSTALL.md`) | doc | n/a | none in-repo | no analog — content spec only (Deferred section + PITFALLS Pitfalls 4/5) |

## Pattern Assignments

### `bramble/Makefile` (config, batch)

**Analog:** itself — this is a retarget, not a new file. The current state IS the starting
point; STACK.md's "Makefile shape for Bramble" is the target shape to converge on.

**Current full state** (`bramble/Makefile`, all 31 lines):
```make
ARCHS = arm64
ifeq ($(SIMULATOR),1)
	TARGET = simulator:clang:latest:15.0
else
	ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
		TARGET = iphone:clang:latest:15.0
	else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
		TARGET = iphone:clang:latest:15.0
	else
		TARGET = iphone:clang:latest:11.0
	endif
endif

INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubeX

$(TWEAK_NAME)_FILES = Tweak.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(SIMULATOR),1)
setup:: clean all
	@rm -f /opt/simject/$(TWEAK_NAME).dylib
	@cp -v $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib /opt/simject/$(TWEAK_NAME).dylib
	@cp -v $(PWD)/$(TWEAK_NAME).plist /opt/simject/$(TWEAK_NAME).plist
endif
```

Notes on what this current state is missing vs. what the phase needs:
- No `MODULES = jailed` — this is the entire point of the retarget.
- `TARGET` branches on `THEOS_PACKAGE_SCHEME` in a way that's jailbreak-oriented (rootless/roothide
  vs plain `iphone:clang:latest:11.0`); per STACK.md this whole branch collapses because package
  scheme is cosmetic for a sideloaded build — `TARGET = iphone:clang:17.5:14.0` (or a
  `MinimumOSVersion`-derived value per D-10) replaces it.
- `INSTALL_TARGET_PROCESSES = YouTube` is a jailbreak `install`/`debug` convenience (auto-launches
  the app after `make install` over SSH). Harmless to leave for jailed builds but not load-bearing;
  the phase's install path is Sideloadly/AltStore, not `make install`.
- No `BUNDLE_ID`, `DISPLAY_NAME`, `PACKAGE_VERSION`, `REMOVE_EXTENSIONS`, `CODESIGN_IPA` — all
  required per D-09/D-10/PKG-06 and STACK.md's target shape.
- The `SIMULATOR` block at the bottom copies to `/opt/simject` — a jailbreak-simulator-injection
  convenience, orthogonal to this phase; leave alone unless it conflicts.
- `TWEAK_NAME = YouTubeX` — CONTEXT.md flags the `YouTubeX` → `Bramble` rename as in-scope-here-if-
  convenient (Claude's discretion); STACK.md's target Makefile already assumes `TWEAK_NAME = Bramble`.

**Target shape** (`.planning/research/STACK.md` lines 103-129, verbatim):
```make
export TARGET = iphone:clang:17.5:14.0
export ARCHS = arm64

ifneq ($(JAILBROKEN),1)
MODULES = jailed
endif

ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 0.0.0          # overwritten by the packaging script
endif
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(BRAMBLE_VERSION)

TWEAK_NAME = Bramble
DISPLAY_NAME = YouTube
BUNDLE_ID = com.google.ios.youtube

Bramble_FILES = Tweak.x
Bramble_CFLAGS = -fobjc-arc
Bramble_FRAMEWORKS = UIKit AVFoundation

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0
```
Note: `TARGET = iphone:clang:17.5:14.0` here is illustrative from STACK.md; D-10 requires the
minimum OS version be *read from the input IPA's `MinimumOSVersion`* at build time, not hardcoded
— the packaging script should inject it (e.g. via `sed` into the Makefile or an env var Make
reads), not the Makefile literal above.

**Invocation** (STACK.md line 134, the packaging script's core command):
```bash
make package THEOS_PACKAGE_SCHEME=rootless IPA=Payload/YouTube.app FINALPACKAGE=1
```

**Two non-obvious prerequisites** (STACK.md lines 139-141):
```
mkdir -p $THEOS/lib/iphone/rootless   # before building, or rootless link search path errors
# GNU make is mandatory — macOS ships 3.81; brew install make, gnubin first on PATH
```

**`INERT=1` build flag (D-14):** no existing Makefile pattern for this — it's a new conditional.
The natural place is a Makefile-level `-D` flag threaded to a `#ifdef`/`#if` in `Tweak.x` (see
below), e.g. `Bramble_CFLAGS += -DBRAMBLE_INERT=1` guarded by `ifeq ($(INERT),1)`. No in-repo
precedent for conditional hook compilation exists; this is genuinely new.

---

### `bramble/Tweak.x` (source/hook file, event-driven)

**Analog:** itself — 268 lines, byte-identical to upstream YouTube-X (confirmed in STACK.md
sources). This phase is purely additive: one `%ctor` block, plus an `#if`/`#ifndef` guard around
the existing hook bodies for `INERT=1` (D-14). No hook logic changes — that's Phase 2/3.

**Current imports** (`bramble/Tweak.x` lines 1-10):
```objc
#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTReelModel.h>
#import <HBLog.h>
```
`HBLog.h` gives `HBLogDebug` (used at lines 203, 209 for existing ad-log-style debug output) —
this is the project's *existing* logging convention, but D-13 explicitly calls for `os_log` under
a Bramble subsystem/category for the `%ctor` line specifically (device-log-visible in Console.app
without needing HBLog's libsyslog wiring). Treat these as two separate logging mechanisms serving
two purposes: `HBLogDebug` for hook-internal debug traces (existing), `os_log` for the one-line
load signal (new, D-13). `#import <os/log.h>` is the new import needed.

**Current file has no `%ctor` and no `%init`.** Every hook block in the file is a bare
`%hook ... %end` (14 blocks; STACK.md counts "19 `%hook`, 4 `%new`, 9 `%orig`, 2 `%c`" across
sub-blocks/lines). There is an implicit `%init;` Logos inserts automatically when none is written
— confirm this still applies once an explicit `%ctor` is added (Logos syntax allows both to
coexist; `%ctor` is what to add for the load line, not a replacement for hook initialization).

**Existing hook block shape to pattern-match for the `INERT=1` guard** (representative excerpt,
`bramble/Tweak.x` lines 12-16):
```objc
%hook YTGlobalConfig

- (BOOL)shouldBlockUpgradeDialog { return YES; }

%end
```
D-14 needs "a dylib containing only the `%ctor` load line, no `%hook` blocks" under `INERT=1`.
Concretely this means wrapping the hook blocks (not the `%ctor`) in a preprocessor guard, e.g.:
```objc
#ifndef BRAMBLE_INERT
%hook YTGlobalConfig
...
%end
... (all 14 existing blocks) ...
#endif
```
with `%ctor { ... os_log load line ... }` placed *outside* the guard so it compiles unconditionally.
No in-repo precedent for this pattern exists (Tweak.x has never had a conditional compilation
block); this is new, but mechanically simple — one `#ifndef`/`#endif` pair around the existing
hook region, informed directly by STACK.md's Logos directive table.

**`%ctor` / `%init` semantics** (`.planning/research/STACK.md` lines 174-201, the only available
reference — no in-repo `%ctor` exists yet):
```
%ctor { }        Anonymous constructor, runs after the binary loads. argc/argv/envp implicit.
                  Where %init goes.
%init(...)        Initializes a group's hooks. Bare %init; initializes the default group.
```
Concrete `%ctor` shape to write (synthesized from D-13's os_log requirement + D-03's version
stamp requirement — no existing os_log call anywhere in this codebase to copy from):
```objc
#import <os/log.h>

%ctor {
    os_log(OS_LOG_DEFAULT, "Bramble loaded, YouTube target version: %s", BRAMBLE_YOUTUBE_VERSION);
    // or: os_log_create("com.osamamazhar.bramble", "load") for a filterable subsystem/category,
    // per D-13's "Bramble subsystem/category" requirement.
    %init;
}
```
`BRAMBLE_YOUTUBE_VERSION` (or equivalent) is a `-D` compile-time define the packaging script must
pass through the Makefile, since D-03 requires the version stamp to come from the input IPA's
`CFBundleVersion`, read at build time — never hardcoded (this is the same "no file in the repo
edited" constraint the Makefile's `YOUTUBE_VERSION` variable exists to satisfy).

---

### `bramble/control` (config/metadata)

**Analog:** itself (current state, all 9 lines) — a Debian control file for the jailbreak `.deb`
build this phase retires.
```
Package: com.ps.ytx
Name: YouTube X
Version: 1.7.22
Architecture: iphoneos-arm
Description: A YouTube improvement tweak.
Maintainer: PoomSmart
Author: PoomSmart
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000), firmware (>= 11.0), com.ps.ytabgoodies
```
`MODULES = jailed` packaging (`ipa.sh`, per STACK.md) does not read this file — theos-jailed
reads `Info.plist` inside the target `.app`, not a Debian control file. CONTEXT.md leaves this
"update or drop" as an open call, not locked by any D-xx decision. Given nothing in the jailed
pipeline consumes it, dropping is the lower-maintenance choice — flag for the planner to decide,
don't force a rewrite pattern that has no consumer.

---

### `bramble/.gitignore` (config)

**Analog:** itself, current full state (3 lines):
```
.theos
.DS_Store
packages
```
Needs additive entries only — same one-glob-per-line convention, no pattern change:
- The config file (D-01: `bramble.config` gitignored, `bramble.config.example` committed)
- The repo-local toolchain dir (D-06: e.g. `.toolchain/` if `$THEOS = bramble/.toolchain/theos`)
- The input IPA cache dir (D-04)

Exact directory names are Claude's discretion per CONTEXT.md ("Exact layout of the build manifest
and the cache directory").

---

### `bramble/YouTubeX.plist` (config, Substrate filter)

**Analog:** itself, full current state (1 line):
```
{ Filter = { Bundles = ( "com.google.ios.youtube" ); }; }
```
This is a MobileSubstrate `Filter` plist used by *jailbreak* system-wide injection (it tells
Substrate's on-device daemon which running processes to inject the `.dylib` into). `MODULES =
jailed` packaging injects the dylib directly into the app bundle via `insert_dylib` at build time
— there is no on-device Substrate daemon doing filter-based injection for a sideloaded app, so
this file's Substrate-filter *purpose* doesn't carry over. Not called out by any D-xx decision;
flag for the planner alongside the `control` file as "no consumer in the jailed pipeline, drop or
rename to `Bramble.plist` only if kept for symmetry with `TWEAK_NAME`."

---

### `bramble/bramble.config.example` + `bramble/bramble.config` (config, D-01)

**No in-repo analog** — no config file of this shape exists anywhere in this codebase today.

**Closest available reference:** the *set of knobs* D-01 through D-12 require, which map directly
onto STACK.md's documented variables and commands rather than any code to copy structurally:
- Input IPA source: local path or URL (D-01, D-04)
- Toolchain SHA pins: Theos, theos-jailed, YouTubeHeader (D-07) — STACK.md's "Toolchain setup"
  section names exactly these three repos and their clone commands (lines 148-166)
- `BRAMBLE_VERSION` (referenced by the Makefile's `PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(BRAMBLE_VERSION)`)
- Cache directory path, refetch flag surface (D-04)
- `$THEOS` repo-local path (D-06, e.g. `bramble/.toolchain/theos`)

Format (shell-sourced `KEY=value` vs. a small `.env`-style file vs. JSON) is unconstrained by any
decision — D-01 only says "gitignored config file... that the script sources," implying a
shell-sourceable format (`KEY=value` lines) is the most direct match to "the script sources it,"
which argues for shell as the script language too (see below).

---

### Packaging script (D-05 through D-14; name/language Claude's discretion)

**No in-repo analog exists.** No shell or Python orchestration script exists anywhere in this
repo today that drives a build. `patch_ytkplus.py` (project root, 195 lines) is the only script
in the repo with any adjacent shape — but it solves a *different* problem (Mach-O binary patching
of a third-party dylib to remove a license check) and shares only surface-level CLI conventions,
not domain logic. Noted for completeness, not recommended as a structural analog:

**Weak style-only reference** (`patch_ytkplus.py` lines 1-27, 154-195 — argv/flag handling and
docstring-as-usage convention, stdlib-only):
```python
#!/usr/bin/env python3
"""
patch_ytkplus.py — ...
Usage:
    python3 patch_ytkplus.py <path/to/YTKPlus.dylib> [--dry-run] [--in-place]
    --in-place   modify the dylib directly (default writes <name>_patched)
    --dry-run    only report, change nothing
Requires: python3 (stdlib only).
"""
import struct, sys, os
...
def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    dry = "--dry-run" in sys.argv
    inplace = "--in-place" in sys.argv
    ...
if __name__ == "__main__":
    main()
```
If the packaging script ends up Python, this establishes the repo's existing convention for
argv parsing (manual `sys.argv` scanning, no `argparse`, docstring doubles as `--help`) — stdlib
only, matching the project's general economy-of-dependencies posture. But nothing else about this
file transfers; it never shells out, never touches `make`, never handles plists.

**The actual reference is external and already synthesized in `.planning/research/STACK.md` §
"Reference pipelines"** — `arichornlover/uYouEnhanced/.github/workflows/buildapp.yml`, described
step-by-step (STACK.md lines 226-241, verbatim):
```
1. runs-on: macos-14; brew install ldid dpkg make; prepend gnubin to PATH.
2. Checkout theos/theos@master recursively.
3. Sparse-checkout the iOS SDK (cached by version) into $THEOS/sdks.
4. Checkout qnblackcat/theos-jailed and run ./theos-jailed/install.
5. Download the decrypted IPA from a workflow input URL (never committed), unzip it.
6. youtube_version=$(defaults read "$(pwd)/Payload/YouTube.app/Info" CFBundleVersion) and
   sed it into the Makefile.
7. sed BUNDLE_ID / DISPLAY_NAME / SDK version into the Makefile from inputs.
8. mkdir -p theos/lib/iphone/rootless; make package THEOS_PACKAGE_SCHEME=rootless
   IPA=Payload/YouTube.app FINALPACKAGE=1.
9. Upload artifact / draft release with a SHA256.
```
STACK.md's own verdict: "Bramble's packaging script is steps 5-8 as a local shell script. Steps
1-4 are one-time setup." This — not any in-repo file — is the pattern to copy the *shape* of.
Concretely: `defaults read .../Info CFBundleVersion` (or `PlistBuddy -c "Print CFBundleVersion"`)
is the exact command to satisfy D-03/D-10's "read the version / MinimumOSVersion, never hardcode"
requirement; `sed` into the Makefile is the exact mechanism the reference pipeline uses to thread
a runtime-read value into a Make variable, which is the same problem the `YOUTUBE_VERSION`
Makefile variable exists to receive.

Toolchain bootstrap commands (D-05, D-06, D-07, D-08 — the auto-install step) are given verbatim
in STACK.md's "Toolchain setup" section (lines 148-166) and reproduced in full there; the
packaging script's bootstrap phase should invoke exactly these commands, redirected to install
under a repo-local `$THEOS` (D-06) rather than the documented `~/theos` default, and pinned to the
SHAs from `bramble.config` (D-07) rather than tracking `master` as the raw commands do.

Language recommendation (not locked by any D-xx, listed under Claude's Discretion): **shell**,
because (a) D-01 says the script "sources" the config file, which is direct in shell and requires
a parser in Python; (b) the one authoritative reference pipeline (uYouEnhanced) is bash end to
end; (c) every command being orchestrated (`make`, `sed`, `defaults read`/`PlistBuddy`, `otool`,
`unzip`/`zip`, `curl`/`git clone`) is a native shell primitive, so a shell script is the "shortest
diff wins" choice, avoiding a subprocess-wrapping layer Python would need for all of the same
commands anyway.

---

### Verification checks (D-09; location TBD — script or Makefile targets, Claude's discretion)

**No in-repo analog.** The four checks are fully specified by D-09 and cross-referenced in
PITFALLS.md Pitfall 10 — copy the exact commands, not a code structure:

1. `otool -L` on the final dylib — assert no `/var/jb`, no `/Library/MobileSubstrate` (PITFALLS.md
   lines 331-334: "Verify with `otool -L` on the final dylib that nothing points at `/var/jb` or
   `/Library/MobileSubstrate`.")
2. `otool -l` on the host binary — assert `LC_RPATH @executable_path/Frameworks` present and
   `LC_LOAD_WEAK_DYLIB @rpath/Bramble.dylib` present (weak, not `LC_LOAD_DYLIB` — STACK.md line 75
   flags this exact confusion in `ANALYSIS.md`).
3. `PlugIns/` absent from the packaged bundle — a plain `test -d`/`[ ! -d ... ]` after unzip,
   corresponding to `REMOVE_EXTENSIONS = 1` in the Makefile (STACK.md line 72).
4. `MinimumOSVersion` read from the input, never assumed — `PlistBuddy -c "Print
   MinimumOSVersion" Payload/YouTube.app/Info.plist` (or `defaults read`), same command family as
   the version-stamp read in the packaging script step 6 above (D-10).

All four "assert and fail the build — no IPA is emitted on failure" (D-09). Whether these live
inline in the packaging script (as a post-package verification block) or as separate Makefile
targets invoked by the script is unconstrained; given the script already shells out to `make
package` and needs the resulting bundle path anyway, doing the checks as shell assertions
immediately after `make package` returns (same script, same process) is the lower-ceremony
option — no cross-file wiring needed to fail the build on a non-zero check.

---

### Build manifest (D-03, emitted artifact)

**No in-repo analog; format entirely unconstrained** ("Exact layout of the build manifest... "
is explicitly Claude's Discretion). Content is locked, not format: "input version, Bramble
version, pinned toolchain SHAs, timestamp" (D-03). A flat JSON or `KEY=value` text file next to
the output IPA both satisfy this; JSON is marginally easier for a future script to consume if one
is ever added, but nothing in this phase reads the manifest back — text is the lazier choice and
there's no downstream consumer yet to justify structure.

---

### `bramble/vendor/CydiaSubstrate.framework/` (D-08, vendored binary)

**No in-repo analog; not source code.** Extract once from the `apt.saurik.com` `.deb`
(`mobilesubstrate_0.9.6301_iphoneos-arm.deb`, per STACK.md's Staleness flags table) and commit the
resulting `.framework` directory under `bramble/vendor/`. The packaging script's job is to point
theos-jailed at this local path instead of letting `theos-jailed/install` re-download from
`apt.saurik.com` — the specific mechanism (env var, symlink into `$THEOS`, or a
`COPY_PATH`-relative reference) isn't specified by any research doc and should be resolved during
planning by reading `qnblackcat/theos-jailed`'s `install` script behavior directly, since no
local clone of theos-jailed exists yet to inspect in this pass.

---

### Install doc (README/INSTALL, Deferred section + Claude's Discretion on exact contents)

**No in-repo analog** — no README or docs directory exists anywhere in `bramble/` or the parent
repo today (`bramble/PLAN.md` is a superseded planning doc, not user-facing). Mandatory content
items are fully specified in CONTEXT.md's Deferred section, sourced from PITFALLS.md Pitfalls 4
and 5:
- Delete the App Store YouTube first (bundle-ID collision — PITFALLS.md lines 147-166)
- The container is wiped as a consequence
- Disable automatic app updates, or the App Store will try to reclaim the bundle ID
- Push notifications and youtube.com universal links will not work (entitlements stripped on a
  free cert — PITFALLS.md lines 169-189)
- Always re-sign with the *same* Apple ID, or the keychain team prefix changes and the session is
  lost (PITFALLS.md line 179, 183)

No structural pattern to copy; this is prose, and its exact form (single README vs. a docs/
subdirectory) is explicitly left to the planner/implementer.

## Shared Patterns

### Version-stamping (D-03) appears in four places, one source of truth
**Source:** `.planning/research/STACK.md` line 233 (`defaults read ... CFBundleVersion`) +
D-03's four consumers.
**Apply to:** the packaging script (reads it once), `bramble/Makefile` (`YOUTUBE_VERSION` var,
already present as a placeholder: `ifndef YOUTUBE_VERSION ... YOUTUBE_VERSION = 0.0.0 ... endif`),
`bramble/Tweak.x` (`%ctor` os_log line, via a `-D` compile flag), and the build manifest. Read
the version exactly once (in the script), thread it everywhere else as a build variable — never
re-derive it in more than one place, or the four locations can drift.

### "Assert and fail the build, never warn" (D-09)
**Source:** D-09 itself; PITFALLS.md Pitfall 10.
**Apply to:** all four verification checks and D-11's stock-input check. Every check is a hard
exit-nonzero on failure with no IPA emitted — the phase's stated dominant risk is silent success
(an app that installs and launches looking completely normal despite a broken build), so none of
these can be advisory.

### Repo-local, gitignored, sourced config (D-01, D-06)
**Source:** D-01 + D-06 combined; `bramble/.gitignore`'s existing convention of one glob per line.
**Apply to:** `bramble.config` / `bramble.config.example` and the `$THEOS` toolchain directory —
both must be invisible to git and both live inside `bramble/`, not at `$HOME` or elsewhere on the
machine, so the whole pipeline is reproducible from a clone of this repo alone.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `bramble/bramble.config.example` / `bramble.config` | config | n/a | No config file of any shape exists in this repo; knobs are fully specified by D-01–D-12 but the file format is greenfield |
| Packaging script | script/orchestrator | batch, file-I/O | No orchestration script exists in-repo; `patch_ytkplus.py` is a weak CLI-style analog only (different domain: Mach-O patching, not IPA packaging). Real reference is external: `uYouEnhanced/.github/workflows/buildapp.yml`, fully described in STACK.md §Reference pipelines |
| Verification checks | test | batch | No test/check script exists in-repo; commands are fully specified by D-09 + PITFALLS.md Pitfall 10 |
| Build manifest | config (output) | file-I/O | No manifest/artifact-emission code exists in-repo; content locked by D-03, format open |
| `bramble/vendor/CydiaSubstrate.framework/` | vendor asset | file-I/O | Binary vendoring, not code; no in-repo precedent for a `vendor/` directory |
| Install doc | doc | n/a | No README/docs directory exists anywhere in the repo yet |

## Metadata

**Analog search scope:** `bramble/` (full directory listing + all tracked files read), project
root (`patch_ytkplus.py`, `ANALYSIS.md`, `work/hookmap.txt` — checked, not used as code analogs),
`.planning/config.json`, `.planning/ROADMAP.md` § Phase 1.
**Files scanned:** 9 files read in full (`bramble/Makefile`, `bramble/Tweak.x`,
`bramble/control`, `bramble/.gitignore`, `bramble/YouTubeX.plist`, `bramble/PLAN.md`,
`patch_ytkplus.py`, plus `01-CONTEXT.md`, `STACK.md`, `PITFALLS.md`).
**Pattern extraction date:** 2026-08-19
