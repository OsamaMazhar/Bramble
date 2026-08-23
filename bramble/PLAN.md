# Superseded

This file held a pre-research draft plan. It is superseded by the GSD planning artifacts in the
parent workspace (`.planning/` — local-only, not in this repo):

- `.planning/PROJECT.md` — scope, constraints, key decisions
- `.planning/REQUIREMENTS.md` — 21 v1 requirements (PKG / ADS / DL)
- `.planning/ROADMAP.md` — 6 phases with gates and success criteria
- `.planning/research/` — STACK, FEATURES, ARCHITECTURE, PITFALLS, SUMMARY

## What the draft got wrong

Kept here so the errors are not repeated from memory:

1. **Packaging was hand-rolled.** The draft scripted `insert_dylib` + `install_name_tool` + `ldid`.
   Theos's `MODULES = jailed` (qnblackcat/theos-jailed) does the whole repackage. Hand-rolling also
   reintroduces the `/var/jb` link failure that the jailed module's `-change` step is what avoids.
2. **`ldid` does not belong in this build.** For the Sideloadly/AltStore path, ship unsigned with
   `CODESIGN_IPA = 0` and let the installer apply the free cert. An `ldid`-signed IPA will not
   install that way.
3. **The headers repo is `PoomSmart/YouTubeHeader`, singular** — and it is cloned into
   `$THEOS/include/`, not added as a submodule.
4. **"Three ad additions" is wrong — there are four.** Upstream YouTube-X does not hook
   `YTAdsInnerTubeContextDecorator` / `YTAccountScopedAdsInnerTubeContextDecorator
   -decorateContext:`. Verified: absent from `Tweak.x`, present in the closed build's hook map.
5. **Audio metadata tagging was listed as polish on the audio step.** It belongs in v2 as a
   foreground-only post-step — tagging adds an export pass to the one flow that is otherwise fully
   background-capable.
6. **`qnblackcat/uYouPlus` is archived** (2025-04-13). The live reference is
   `arichornlover/uYouEnhanced`.

Also corrected in the parent workspace's `ANALYSIS.md`: the dylib is injected as
`LC_LOAD_WEAK_DYLIB`, not `LC_LOAD_DYLIB`.
