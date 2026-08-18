# Bramble

## What This Is

An iOS YouTube tweak, forked from PoomSmart/YouTube-X (MIT), that blocks ads and adds
video/audio downloads to the official YouTube app. It ships with a packaging script that turns
any newer decrypted YouTube IPA into a tweaked build, so a new YouTube release is a script run
rather than a re-derivation. Built for the author and a small number of people they share it
with — not a public release.

## Core Value

Ad-free YouTube on my device, rebuildable against the next YouTube version with one command.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

- [ ] Upstream YouTube-X ad blocking verified working against YouTube 21.31.3
- [ ] Ad-log diagnostic: opt-in, records which rule matched and which renderer was dropped
- [ ] Companion-ad suppression via `YTIElementRenderer` accessors
- [ ] Wider ad-playback coverage on `YTLocalPlaybackController`, including reload/refresh/restore paths
- [ ] Audio-only download saved as a playable `.m4a`
- [ ] Video download: separate tracks fetched and muxed into a single `.mp4`
- [ ] Transfers continue while the app is backgrounded or terminated
- [ ] Download queue survives app termination without orphaning files
- [ ] Packaging script produces an installable IPA from a decrypted YouTube IPA
- [ ] Packaging script works against a newer YouTube version without code changes
- [ ] Google sign-in works in the packaged build

### Out of Scope

- License checks, activation, device identifiers, phone-home — not needed for a private build,
  and this plumbing is precisely what makes YTKillerPlus a closed paid binary
- Frida detection and anti-tamper — self-protection unrelated to what the tweak does
- Bundled FFmpeg — ~26 MB to gain VP9/Opus/AV1; AVFoundation muxes AVC/AAC natively for ~0 MB.
  Revisit only if a needed resolution is VP9-only
- SponsorBlock, local media player, backup/restore, alt app icons, settings-UI parity — present
  in YTKillerPlus, not asked for here
- Discovering, curating, or scraping mirror sites that host decrypted YouTube IPAs — the script
  reads its source from user-controlled config instead
- Public distribution, update server, hosted repo — audience is a handful of people
- Side-by-side install alongside the App Store YouTube — precluded by keeping the original
  bundle ID, which is required for sign-in

## Context

**Origin.** A teardown of `YouTube_21.31_YTKillerPlus_6.0.ipa` (see `../ANALYSIS.md`,
`../work/hookmap.txt`) established that YTKillerPlus's ad blocking is not merely the same
*technique* as the open-source YouTube-X — it is the same *implementation*. Evidence: identical
class/selector hook sets, an identical renderer-ID blocklist, and leaked log format strings
naming YouTube-X's own `filteredArray()` and `isAdRenderer()` helpers. Forking upstream
therefore starts from parity, not from behind.

**Recovered hook surface.** 323 `MSHookMessageEx` sites across 140 classes were extracted from
`YTKPlus.dylib`. Class attribution used a nearest-preceding heuristic, so a few entries may be
mis-attributed; the selector lists are exact.

**Where the size goes.** YTKillerPlus is 27 MB, of which ~26 MB is statically linked FFmpeg and
gnutls serving the downloader. The ad-blocking logic is a few hundred KB.

**Download pipeline shape**, recovered from YTKillerPlus's ObjC metadata: three independent
queues (video, audio-only, Shorts), per-item phase/progress state, thumbnails fetched separately
and stored alongside the media, and a merge step for video because adaptive formats arrive as
separate tracks.

**Prior work in this directory.** `../bramble/PLAN.md` holds a phased draft (build baseline,
hook validation, the three ad additions, downloads) written before this planning pass. Also
present but unrelated to Bramble: `../YTKPlus_PATCH_REPORT.md` and `../patch_ytkplus.py`, which
document patching YTKillerPlus's own binary. Bramble builds from MIT source and inherits nothing
from that work.

## Constraints

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

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Fork PoomSmart/YouTube-X rather than write fresh | Teardown proved it is the same implementation YTKillerPlus ships; MIT-licensed, ~270 lines | — Pending |
| Keep bundle ID `com.google.ios.youtube` | Sign-in is a hard requirement and OAuth redirect schemes are bound to the ID | — Pending |
| AVFoundation passthrough muxing instead of FFmpeg | Removes ~26 MB; ceiling is AVC/AAC only | — Pending |
| Build audio-only downloads before video | An AAC adaptive format is already a valid `.m4a` — no muxing, so it exercises queue/progress/background machinery with none of the merge risk | — Pending |
| Ad-log diagnostic, opt-in and off by default | The string blocklist is the only part of ad blocking that rots; logging matches makes a renamed renderer a two-minute fix. Off by default because diagnostics observe real browsing | — Pending |
| Packaging script takes its IPA source from user config | Keeps the pipeline reusable regardless of sourcing, and leaves that choice with the operator | — Pending |
| No license, telemetry, or anti-tamper code | Not needed for a private build; it is what makes the closed alternative closed | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-18 after initialization*
