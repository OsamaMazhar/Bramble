---
status: complete
date: 2026-08-20
slug: bramble-settings-section
---

# Quick Task: Bramble settings section + Speedmaster toggles

## What

Added a "Bramble" section to YouTube's own Settings with four `NSUserDefaults`-backed
switches, and the hooks that read them.

| Toggle | Default | Hook | Effect |
|---|---|---|---|
| Block ads | ON | group registration in `%ctor` | after relaunch |
| Background playback | ON | group registration in `%ctor` | after relaunch |
| Disable hold for 2x speed | ON | `-[YTMainAppVideoPlayerOverlayViewController currentVideoIsEligibleToActivateSpeedmaster]` | immediate |
| Disable hold for 2x speed in Shorts | ON | `-[YTColdConfig shortsConsumptionClientGlobalConfigIosEnableShortsSpeedmasterGesture]` | after relaunch (cold config) |

Files: `bramble/Tweak.x` only. Commit `8cd1c4e` in the `bramble` repo (separate git
repo from this planning tree).

## Decisions

- **Three Logos groups, not one.** `Core` overrides real methods and reads its preference
  per call. `Ads` and `Background` contain `%new` methods, which have no `%orig` — once
  `class_addMethod` has run there is no original behaviour left to restore, so the only
  honest switch is whether `%ctor` registers the group. Their rows say "after restarting".
- **Every toggle defaults ON.** An absent `NSUserDefaults` key must never read as
  "feature off", or a fresh install silently behaves differently from the build before it.
- **Section appended to `settingsCategoryOrder`, not spliced at an index.** Position is
  cosmetic; index-matching is one more thing to break on the next YouTube release.
- **Toggle rows are a table, no config class.** A future feature is one row plus the hook
  that reads its key.

## Verification

- Hook points parsed out of ObjC class metadata in the decrypted 21.32.4 binary rather
  than copied from community tweaks. Notable find: the five-argument
  `setSectionItems:forCategory:title:titleDescription:headerHidden:` that older tweaks
  call does **not** exist in 21.32.4 — only the icon-taking variant does.
- `./package.sh` → "Verified and packaged", all D-09/D-14 checks pass.
- `INERT=1` build emits 0 `MSHookMessageEx` references; live build emits 1. Check 5 holds
  with three `%init` calls where there was one.

## Not done

- Phase 3's four ad additions (companion-ad accessors, `decorateContext:` suppression,
  wider playback coverage, ad-log diagnostic) — still Phase 3 work. The "Block ads"
  master switch is a partial down payment on ADS-07; per-hook toggles are not built.
- Device test. The section renders per the metadata, but nothing here has run on hardware.
  Phase 1's 01-05 device gate is still the open plan.
