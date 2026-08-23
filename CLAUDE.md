<!-- GSD:project-start source:PROJECT.md -->
## Project

**Bramble**

An iOS YouTube tweak, forked from PoomSmart/YouTube-X (MIT), that blocks ads and adds
video/audio downloads to the official YouTube app. It ships with a packaging script that turns
any newer decrypted YouTube IPA into a tweaked build, so a new YouTube release is a script run
rather than a re-derivation. Built for the author and a small number of people they share it
with — not a public release.

**Core Value:** Ad-free YouTube on my device, rebuildable against the next YouTube version with one command.

### Constraints

- **Compatibility**: bundle ID stays `com.google.ios.youtube` — Google's OAuth redirect scheme
  is bound to it, and sign-in is a hard requirement. Consequence: the App Store YouTube must be
  removed; no side-by-side install.
- **Install**: Sideloadly / AltStore with a free Apple ID — 7-day certificate expiry, and
  team-ID-prefixed keychain access groups mean Google's cross-app SSO will not carry over.
  Sign-in happens directly through the OAuth flow.
- **Tech stack**: Theos + Logos, Objective-C. Runtime hooking via `MSHookMessageEx` against
  CydiaSubstrate, matching how the reference build injects into the app.
- **Codec**: AVFoundation passthrough muxing handles AVC video + AAC audio only. The format
  picker must be capped accordingly, or downloads fail at the merge step.
- **Versioning**: YouTube 21.31.3 is the current target, but nothing may hardcode it — the
  packaging script's value is that it survives future releases.
- **Sourcing**: the decrypted input IPA is supplied by the operator via configuration. The
  project does not locate or bundle a source.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Headline verdict
## Core stack
| Technology | Version | Purpose | Why |
|---|---|---|---|
| Theos | git master (HEAD `5280bd0`, 2026-08-08) | build system + Logos preprocessor | Actively maintained. No tagged releases; everyone tracks master. |
| theos-jailed | `qnblackcat/theos-jailed` master (last push 2023-10-15) | `MODULES = jailed` — IPA repackaging | Dormant but working; used by the live uYouEnhanced pipeline as of 2026-07. |
| Logos | vendored in Theos (`vendor/logos`) | `%hook`/`%new`/`%orig` → ObjC runtime code | Generator selectable: `MobileSubstrate` (default), `libhooker`, `internal`. |
| CydiaSubstrate.framework | 0.9.6301 | `MSHookMessageEx` at runtime | Bundled into the app; downloaded by theos-jailed's `install` from apt.saurik.com. |
| PoomSmart/**YouTubeHeader** | git master (2026-07-28) | ~480 YouTube ObjC headers | Note: singular **Header**, not "YouTubeHeaders". Clone to `$THEOS/include/YouTubeHeader`. |
| iOS SDK | iPhoneOS 17.5 | compile against | uYouEnhanced's current pin. Theos does not ship SDKs; fetch from `theos/sdks`. |
| ARCHS | `arm64` | — | arm64e is not needed and complicates injection. |
## The four questions, answered
### Why the fork (qnblackcat vs kabiroberai)
| Fork change | Why it matters here |
|---|---|
| `insert_dylib --inplace --weak --no-strip-codesig` (upstream: `--all-yes`) | `--weak` emits **`LC_LOAD_WEAK_DYLIB`** so a missing dylib doesn't kill launch; `--no-strip-codesig` keeps the signature load command so Sideloadly can re-sign. Upstream strips it and the install fails. |
| `rm -rf $appdir/_CodeSignature/CodeResources` | Injection invalidates the manifest; a stale one breaks re-signing. |
| `ALTBundleIdentifier` = original bundle ID | AltStore/SideStore read this key to track the app. |
| `REMOVE_EXTENSIONS = 1` → `rm -rf $appdir/PlugIns` | **Free-cert constraint**: a free Apple ID allows 3 app IDs; each `.appex` consumes one. YouTube ships several. Strip them or the install is rejected. |
| `EMBED_BUNDLES` / `EMBED_EXTENSIONS` | Ships an asset `.bundle` alongside the dylib. |
### Exact packaging mechanics (read from `ipa.sh`)
### Makefile shape for Bramble
- `mkdir -p $THEOS/lib/iphone/rootless` before building, or the rootless link search path errors.
- GNU make is mandatory. macOS ships make 3.81; `brew install make` and put
### Toolchain setup
# Theos
# SDK (Theos ships none)
# theos-jailed  (installs the module + downloads CydiaSubstrate 0.9.6301)
# YouTube headers
# GNU make
### Logos essentials
| Directive | Semantics |
|---|---|
| `%hook ClassName ... %end` | Opens a hook block. Methods inside replace the class's IMPs. |
| `%orig` / `%orig(args…)` | Calls the original IMP. **Does not work inside a `%new` method.** Do not pass `self`/`_cmd` — Logos supplies them. |
| `%new` / `%new(signature)` | Adds a method that does not exist on the class. Compiles to `class_addMethod`. `signature` is the ObjC type encoding; if omitted Logos generates one. Must be inside `%hook` or `%subclass`. |
| `%c(ClassName)` / `%c(+ClassName)` | Evaluates to the `Class` (or metaclass) at runtime — the safe way to reference a class you cannot link against. |
| `%ctor { }` | Anonymous constructor, runs after the binary loads. `argc`/`argv`/`envp` are implicit. Where `%init` goes. |
| `%init(...)` | Initializes a group's hooks. Bare `%init;` initializes the default group. `%init(Name=objc_getClass("Swift.Name"))` substitutes classes whose names can't be a bare token. |
| `%group` / `%dtor` / `%property` / `%subclass` / `%hookf` | Available; Bramble uses none of them today. |
### YouTubeHeader
- Repo is **`PoomSmart/YouTubeHeader`** — singular. `PoomSmart/YouTubeHeaders` is a 404.
- Consumed by **cloning into `$THEOS/include/YouTubeHeader`**, per its README. Not a
- ~480 headers. Included as `#import <YouTubeHeader/YTIElementRenderer.h>`.
- **Constraint:** these are hand-maintained reverse-engineered headers. A class or selector
- **Pin it.** Bramble should vendor a submodule at a known SHA rather than tracking master,
### Reference pipelines
| Project | Status | Value |
|---|---|---|
| `qnblackcat/uYouPlus` | **ARCHIVED** 2025-04-13, 7.6k stars | The pipeline ANALYSIS.md cites. Still the clearest reference, but dead — do not expect fixes. |
| `arichornlover/uYouEnhanced` | **Live**, 3.1k stars, pushed 2026-07-29 | The successor, explicitly "mainly made for non jailbroken users". Same architecture, current SDK. **Use this as the reference, not uYouPlus.** |
| `PoomSmart/YouTube-X` | Live, pushed 2026-07-08 | The fork base. Jailbreak-oriented Makefile; contributes no packaging. |
## Alternatives considered
| Recommended | Alternative | When the alternative wins |
|---|---|---|
| `MODULES = jailed` | Hand-rolled `insert_dylib` + `install_name_tool` script | Only if you need a step theos-jailed can't express. It already does all seven. Rolling your own re-derives a solved problem and loses `--weak`/`--no-strip-codesig`/`_CodeSignature` handling. |
| `qnblackcat/theos-jailed` | `kabiroberai/theos-jailed` (upstream) | Never, for sideloading. Upstream strips the codesig LC and emits a non-weak load command. |
| Logos generator `MobileSubstrate` | generator `internal` | If the Substrate download breaks, or you want zero bundled frameworks. Requires no `%hookf`. |
| `CODESIGN_IPA = 0` + Sideloadly | theos-jailed's built-in `codesign` path | Only with a *paid* account and a real provisioning profile. A free cert has no usable profile for this. |
| Pin `YouTubeHeader` as a submodule | Clone master into `$THEOS/include` | Clone-to-`$THEOS` is the documented path and fine for a single dev machine; a pinned submodule is better for a reproducible script. |
## What NOT to use
| Avoid | Why | Instead |
|---|---|---|
| `MSHookFunction` | Rewrites `__TEXT`; requires a codesign bypass that does not exist on a stock device. Confirmed by PoomSmart directly. | `MSHookMessageEx` via `%hook` for ObjC; fishhook for C symbols. |
| ElleKit (`tealbathingsuit/ellekit`) | A *jailbreak* Substrate replacement — it substitutes the system-wide hooking runtime. Nothing to substitute in a sideloaded app. Actively maintained, just not for this. | Bundled `CydiaSubstrate.framework`. |
| libhooker | Same category as ElleKit — a jailbreak substrate. Logos can emit for it (`generator = libhooker`) but you'd have to ship libhooker yourself. | `MobileSubstrate` generator. |
| fishhook | Not wrong, just unnecessary — it rebinds lazy/non-lazy **C symbol** pointers in `__DATA`. Bramble hooks only ObjC methods. | Nothing; enable `_USE_FISHHOOK` only if a C function needs hooking. |
| `ldid` | A pseudo-signer for jailbroken/TrollStore devices. A pseudo-signature will not install via Sideloadly with a free cert. | Ship unsigned; let Sideloadly sign. |
| `THEOS_PACKAGE_SCHEME=roothide` | Not in upstream Theos — needs the `roothide/theos` fork. Buys nothing for a sideload. | `rootless`, or omit. |
| arm64e slice | Complicates injection for no gain. | `ARCHS = arm64`. |
| Changing `BUNDLE_ID` | PROJECT.md pins it to `com.google.ios.youtube` for OAuth. Setting it anyway is a one-line footgun in the Makefile. | Leave `BUNDLE_ID = com.google.ios.youtube`. |
## Free-cert / sideload constraints (what this stack is shaped by)
## Staleness flags
| Item | Risk | Detail |
|---|---|---|
| `theos-jailed` (both forks) | **HIGH** | Upstream last pushed 2023-12-25; qnblackcat's fork 2023-10-15. ~3 years dormant. Neither is archived, and uYouEnhanced still ships on it as of 2026-07, so it works — but nobody is maintaining it. This is the single biggest fragility in the stack. |
| `apt.saurik.com` Substrate download | **MEDIUM** | `./theos-jailed/install` hardcodes `http://apt.saurik.com/debs/mobilesubstrate_0.9.6301_iphoneos-arm.deb`. Verified reachable 2026-08-18 (302 → `cache.saurik.com`). Single point of failure on an unmaintained host. **Mitigation: vendor the extracted `CydiaSubstrate.framework` into the repo once, or switch the Logos generator to `internal`.** |
| `uYouPlus` archived | **Confirmed** | ANALYSIS.md names it as the reference. It is frozen. Read `uYouEnhanced` instead. |
| SDK version pin (17.5) | LOW | Cosmetic; bump freely. |
| Deployment target | **MEDIUM — verify** | Reference builds use 14.0/15.0, but YouTube 21.31.3's own `MinimumOSVersion` is almost certainly higher. Read it from the target IPA's `Info.plist` rather than copying a number. Not verified here. |
| Theos master | LOW | Actively developed (HEAD 2026-08-08). Master can break; pin a SHA if a build ever regresses. |
## Confidence
| Claim | Level | Basis |
|---|---|---|
| `MODULES = jailed` is the standard; what it automates | **HIGH** | Read `ipa.sh`, `common.mk`, `stage.sh`, `ipa-jailed.mk` from both forks directly. |
| Fork differences (`--weak`, `_CodeSignature`, `REMOVE_EXTENSIONS`, `ALTBundleIdentifier`) | **HIGH** | Direct `diff` of the two repos. |
| Logos directive semantics | **HIGH** | Theos's own offline docs in the repo. |
| Package scheme meanings | **HIGH** | Read `vendor/mod/rootless/*` and `makefiles/common.mk` in the Theos clone. |
| `YouTubeHeader` name + install path | **HIGH** | Repo README; `PoomSmart/YouTubeHeaders` 404s. |
| Repo maintenance status / dates | **HIGH** | GitHub API, 2026-08-18. |
| `MSHookFunction` fails sideloaded | **MEDIUM** | Well-attested (incl. PoomSmart), but no first-party doc. Moot — Bramble doesn't use it. |
| `internal` generator viability | **MEDIUM** | Documented behaviour + Bramble uses no `%hookf`. Not empirically tested. |
| Deployment target | **LOW** | Not verified against the target IPA. |
## Sources
- `theos/theos@5280bd0` (2026-08-08) — cloned; `makefiles/common.mk`, `vendor/mod/rootless/`, `makefiles/instance/tweak.mk`, `docs/Logos-Syntax.html`
- `kabiroberai/theos-jailed@master` — cloned; `module/bin/ipa.sh`, `module/bin/stage.sh`, `module/common.mk`, `install`
- `qnblackcat/theos-jailed@master` — cloned and diffed against upstream
- `arichornlover/uYouEnhanced` — `Makefile`, `.github/workflows/buildapp.yml` (live reference pipeline)
- `qnblackcat/uYouPlus` — `Makefile`, `.github/workflows/buildapp.yml` (archived reference)
- `PoomSmart/YouTube-X` — cloned; confirmed `bramble/Tweak.x` is byte-identical
- `PoomSmart/YouTubeHeader` — README, tree listing (~480 headers)
- https://theos.dev/docs/installation-macos — Xcode requirement, bootstrap command
- GitHub API — archive status and push dates for all repos above, 2026-08-18
- `curl -I http://apt.saurik.com/debs/mobilesubstrate_0.9.6301_iphoneos-arm.deb` — 302, live
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
