# Bramble — Session Handoff

Everything needed to pick this up cold: what works, how to build and install it, how the
hook points were found, and which paths are already proven dead.

Written 2026-08-21, updated 2026-08-23 (iPad watch-page investigation, rounds 1–10).
Target: **YouTube 21.32.4**. Verified on **iPhone 15 Pro Max (iOS 26.6)**, iPhone XS,
iPhone 13 Pro Max, and **iPad 5th gen (iPad6,11, iOS 16.7.16)**.

---

## 1. Current state

Working and on device. All features are toggles in a **Bramble** section inside YouTube's own
Settings (bottom of *Video and audio preferences*), backed by `NSUserDefaults`.

| Toggle | Key | Effect | Live or relaunch |
|---|---|---|---|
| Block ads | `BrambleBlockAds` | Upstream YouTube-X ad hooks | relaunch |
| Background playback | `BrambleBackgroundPlayback` | Audio continues backgrounded | relaunch |
| Disable hold for 2x speed | `BrambleNoSpeedmaster` | Player press-and-hold | immediate |
| Disable hold for 2x in Shorts | `BrambleNoSpeedmasterShorts` | Shorts variant | relaunch (cold config) |
| Hide suggested videos | `BrambleHideSuggested` | Related list + overlay panels; iPad: forces compact single-column watch layout (no right column) | immediate |
| Hide comments | `BrambleHideComments` | Comments section below the player | immediate |
| Disable double tap to seek | `BrambleNoDoubleTapSeek` | Double-tap left/right on the player | immediate |
| Hide the playlist Next bar | `BrambleHidePlaylistNext` | Playlist/queue mini-bar above the tab bar | immediate |
| Loop button on the player | `BrambleLoopButton` | Repeat button next to Cast/captions/settings | immediate |
| Hide Shorts | `BrambleHideShorts` | Shorts tab + shelves + cells | immediate |
| Report an older app version | `BrambleSpoofVersion` | Client version → 20.21.6 | relaunch |

**Toggles default ON**, with one exception: `bramblePref()` returns `YES` for an absent key
(an absent key must never read as "feature off", or a fresh install behaves differently from
the build before it) — except **`BrambleHideComments`, which defaults OFF**. Reason: hide-
comments ON combines with Hide suggested to mask the watch pane's native `visibleSections:5`
to `0`, which wipes title/description/comments entirely. A hide-feature whose default breaks
the page it hides things on is not shippable as a default.

### Why some toggles need a relaunch

Three Logos groups, and the split is load-bearing:

- **`Core`** — hooks that override *real* methods. They read their pref per call, so the
  switch takes effect immediately.
- **`Ads`**, **`Background`** — contain `%new` methods. A `%new` method has no `%orig`; once
  `class_addMethod` has run there is no original behaviour left to restore. The only honest
  switch is whether `%ctor` registers the group at all.
- **`Integrity`**, **`Diagnostics`** — registered unconditionally.

`%init(...)` calls live inside `#ifndef BRAMBLE_INERT`. Hook *bodies* are never inside that
guard: Logos scans `%hook`/`%end` textually and has no awareness of the C preprocessor.

---

## 2. Build and install

### Build

```bash
cd /Users/osama/Projects/yt-test/bramble
./package.sh                 # reads bramble.config, outputs build/Bramble-<yt>-<ver>.ipa
./package.sh --inert         # hooks compiled out; for isolating tweak vs packaging
```

`package.sh` bootstraps the toolchain into `.toolchain/theos`, stamps the version, strips
`PlugIns/` **and** `Extensions/`, then runs five verification checks. It fails loudly.

### Sign and install (paid account, ~1 year — better than Sideloadly's 7 days)

```bash
W=/tmp/brbuild
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/54dd6aa0-4363-456e-9cee-b5bbe2af86de.mobileprovision"
ID="Apple Development: Osama Mazhar (L2NN97SCG5)"
DEV=2B289A99-B601-5130-98C4-5D964C531F85     # iPhone 15 Pro Max

rm -rf $W && mkdir -p $W
unzip -qo build/Bramble-21.32.4-0.1.0.ipa -d $W
A=$W/Payload/YouTube.app
rm -rf "$A/_CodeSignature"
cp "$PROFILE" "$A/embedded.mobileprovision"
for f in "$A/Frameworks/"*; do codesign --force --sign "$ID" "$f"; done
codesign --force --sign "$ID" --entitlements /tmp/brsign/ent-full.plist "$A"
codesign --verify --strict "$A"

xcrun devicectl device uninstall app --device $DEV com.google.ios.youtube
xcrun devicectl device install app --device $DEV "$A"
xcrun devicectl device process launch --device $DEV com.google.ios.youtube
```

Notes:

- The wildcard profile is `829378375Z.*`, valid to **2027-07-18**, and includes the device UDID
  `00008130-0014145C18A1401C`.
- Entitlements: `application-identifier`, `com.apple.developer.team-identifier`,
  `get-task-allow`, and team-prefixed `keychain-access-groups`
  (`...youtube`, `...common.SSO`, `...common.folsom`). App groups **cannot** be restored —
  `group.com.google.YouTube` is globally registered to Google.
- **In-place installs fail** (`CoreDeviceError 3002`) whenever the installed bundle has
  `PlugIns/` — e.g. after installing App Store YouTube. Uninstall first.
- **Uninstall wipes prefs**, so all toggles return to their ON defaults. It also wipes the
  sign-in session.
- **iOS 16 and older devices need `ios-deploy`, not `devicectl`.** `devicectl` is CoreDevice-
  based and only drives iOS 17+; on an older device it shows a nameless stub row reading
  `unavailable` and `manage pair` fails with error 1011, which looks exactly like "not
  paired". Read the real UDID off the USB bus with
  `ioreg -rc IOUSBHostDevice -w 0 | grep "USB Serial Number"`, confirm with
  `xcrun xcdevice list`, then
  `ios-deploy --id <udid> --bundle build/signed/Payload/YouTube.app --no-wifi`.
  Proven on Javeria's iPad (iPad 5th gen, iOS 16.7.16, UDID
  `f41584fde500f130ecf9539bbb8a507fa8dbf770`).
- **iPad storage forces uninstall-first.** ~550 MB free vs a 314 MB app: installing over the
  existing copy fails with `0xe8000051` ("Could not inspect the application package") —
  identical error to a corrupt payload, but it's just disk space. Always
  `ios-deploy --id <udid> --uninstall_only --bundle_id com.google.ios.youtube` first.
  Note: uninstall takes **`--bundle_id`**, not `--bundle` (the latter errors with "you need
  to pass in the bundle id").
- **Never let ios-deploy launch the app on the iPad.** Its debugger-attached launch produces
  `EXC_BREAKPOINT` (`lldb_image_notifier`) crash reports that look like a real crash — they
  are artifacts of the debugger attach. Ask the user to open the app manually, or use
  `--noinstall --bundle ... --justlaunch` (passing `--bundle` *without* `--noinstall`
  triggers a reinstall).
- **Probe log from the iPad:** `ios-deploy --id <udid> --bundle_id com.google.ios.youtube
  --download=/Documents --to=/tmp/probe` then read
  `/tmp/probe/Documents/bramble-probe.log`. Same plist read/write trick as below works with
  `--download`/`--upload` instead of devicectl copy.
- **`0xe8008015` at install = wrong provisioning profile embedded**, not a bad entitlement.
  `deploy.sh` used to pick a profile by grepping the whole plist for a `*` string, which
  matches unrelated fields and can select a single-app profile
  (`829378375Z.com.osamamazhar.TripPhotoShare` was picked once). It now reads
  `Entitlements.application-identifier` and requires it to end in `.*`. Two wildcard profiles
  exist; only `54dd6aa0-...` carries the iPad.
- **`0xe80000be` at install = App Store YouTube is still on the device.** Its
  `application-identifier` is Google's `EQHXZ8M8AV.` prefix, so an upgrade in place is
  refused. Uninstall first: `ios-deploy --id <udid> --uninstall_only --bundle_id com.google.ios.youtube`.
- `devicectl` refuses to launch onto a **locked** device — the error mentions "was not, or
  could not be, unlocked". This looks exactly like "the tweak didn't load". Check for it.

---

## 3. Debugging: read the device, don't infer

This is the single biggest lesson from the session. Several hours went into inferring from
binaries and third-party source when the answer was one log line away.

### `brambleProbe()`

Writes to **NSLog and** `Documents/bramble-probe.log` in the app container. The file is what
matters: a console attach only captures hooks that fire while it's held, which lost two
captures outright.

```bash
xcrun devicectl device copy from --device $DEV \
  --domain-type appDataContainer --domain-identifier com.google.ios.youtube \
  --source Documents/bramble-probe.log --destination /tmp/probe.log
```

### Reading and writing prefs from the host

Full read/write access to the app container. This lets you flip toggles without navigating a
broken UI, and **sweep a value without rebuilding**:

```bash
xcrun devicectl device copy from --device $DEV --domain-type appDataContainer \
  --domain-identifier com.google.ios.youtube \
  --source "Library/Preferences/com.google.ios.youtube.plist" --destination /tmp/yt.plist
/usr/libexec/PlistBuddy -c "Set :BrambleHideShorts false" /tmp/yt.plist
xcrun devicectl device copy to --device $DEV --domain-type appDataContainer \
  --domain-identifier com.google.ios.youtube \
  --source /tmp/yt.plist --destination "Library/Preferences/com.google.ios.youtube.plist"
```

Writes stick across relaunch. Reading a value back is how you confirm it took.

### What does NOT work for logs

- `log stream --device` — not supported by this macOS.
- `idevicesyslog` — returns thousands of lines but **none from YouTube**.
- `devicectl ... --console` — carries stdout/NSLog only. `os_log` to a custom subsystem is
  invisible to it. The `%ctor` load line is `os_log` *and* `NSLog` for exactly this reason.

### ObjC metadata tools (`tools/`)

The binary is stripped, so `nm` gives nothing and `otool -oV` won't resolve selector names.
These parse `__objc_classlist` / `__objc_catlist` directly, decoding chained fixups:

```bash
B=build/staging/Payload/YouTube.app/YouTube
python3 tools/objc-find-selector.py "$B" someSelector:            # selector -> owning class
python3 tools/objc-dump-class.py    "$B" YTVersionUtils 'regex'   # class -> methods + type encodings
python3 tools/objc-dump-category.py "$B" YTAttestation            # category -> methods
```

**Always verify a selector against the binary before hooking it.** Real cases from this session:

- `YouTubeHeader` declares `appPreferenceCategories` / `privacyCategories` /
  `miscellaneousCategories` on `YTSettingsGroupData`. **None exist in 21.32.4.**
- uYouEnhanced hooks `YTFullScreenEngagementOverlayView`. This binary has
  `YTFullscreenEngagementOverlayView` (lowercase s). Wrong casing binds to nothing, silently.
- The 5-argument `setSectionItems:forCategory:title:titleDescription:headerHidden:` that older
  tweaks call **does not exist**; only the `icon:`-taking variant does.

---

## 4. Feature hook points (all verified against 21.32.4)

```
Settings section
  +[YTAppSettingsPresentationData settingsCategoryOrder]        (legacy list; not what renders)
  -[YTSettingsGroupData videoandAudioPreferencesCategories]     <- what actually renders it
  -[YTSettingsSectionItemManager updateSectionForCategory:withEntry:]
       ivar _settingsViewControllerDelegate, reached by KVC
  -[YTSettingsViewController setSectionItems:forCategory:title:icon:titleDescription:headerHidden:]
  +[YTSettingsSectionItem switchItemWithTitle:titleDescription:accessibilityIdentifier:
                                     switchOn:switchBlock:settingItemId:]
  Category constant 0x42524D (4346445). Icon: YTIIcon.iconType = YT_TUNE (530).

Speedmaster (hold for 2x)
  -[YTMainAppVideoPlayerOverlayViewController currentVideoIsEligibleToActivateSpeedmaster]
  -[YTColdConfig shortsConsumptionClientGlobalConfigIosEnableShortsSpeedmasterGesture]

Hide Shorts
  -[YTPivotBarView setRenderer:]        drop pivotIdentifier "FEshorts"
  -[YTIElementRenderer elementData]     return empty NSData for shorts_shelf,
                                        shorts_video_cell, shorts_grid_shelf_footer,
                                        youtube_shorts_24, and
                                        compact_video.eml + youtube_shorts_ (history)

Playlist "Next" mini-bar
  -[YTWatchViewController showPlaylistMiniBar]           skip
  -[YTWatchViewController showPlaylistMiniBarIfNeeded]   skip
       "Next" text itself comes from -[YTPlaylistMiniBarView updateWithTitle:subtitle:
       queuePositionText:subtitleAccessibilityLabel:nextLabel:icon:...]. Not
       -[YTPlaylistMiniBarViewController setMiniBarVisible:] -- its attributes
       (TB,N,GisMiniBarVisible,V_miniBarVisible) read as a synthesised ivar setter.

Hide suggested / related
  -[YTWatchNextResultsViewController setVisibleSections:]   <- THE one that works (iPhone)
       bitmask; bit 2 = related list, bit 0 = comments. Clear bit 2.
  -[YTFullscreenEngagementOverlayController setRelatedVideosVisible:]      %orig(NO)
  -[YTFullscreenEngagementOverlayController relatedVideosPeekingEnabled]   NO
  -[YTFullscreenEngagementOverlayView setRelatedVideosView:]               skip
  -[YTRelatedVideosViewController setRelatedViewVisible:]                  %orig(NO)
  -[YTWatchStateController setRelatedVideosVisible:]                       %orig(NO)
  -[YTMainAppVideoPlayerOverlayViewController updateRelatedVideos]         skip
  iPad (regular width): the mask is a no-op — the two-column layout bypasses it entirely.
  Instead force the compact layout (see "iPad watch-page architecture" below):
  -[YTWatchViewController isWideLayoutForWatchView:]              -> NO
  -[YTWatchLayerViewController isWideWatchLayout]                 -> NO
  -[YTSectionListDrawerView isWideMode]                           -> NO
  -[YTSectionListDrawerViewController isWideModeWithWidth:]       -> NO

Double tap to seek
  -[YTDoubleTapToSeekController didDoubleTap:]                     skip when disabled

Loop button (added to the player controls row)
  -[YTMainAppVideoPlayerOverlayViewController layoutSubviews]      re-anchors the button:
       pitch measured from the Cast button, anchor switches to autonavSwitch when it is
       visible (checks superview/bounds/hidden/alpha — during fade-out .alpha already reads
       the animation target, which is why the anchor check needs the controls-visible flag)
  -[... setTopOverlayVisible:isAutonavCanceledState:] / setOverlayVisible:]
       set an objc associated-object "controlsVisible" flag BEFORE %orig; layoutSubviews
       returns early when controls are not visible, so the button doesn't slide onto the
       autoplay toggle during fade-out

Version spoof
  +[YTVersionUtils appVersion]   -> "20.21.6"

Playback integrity (%new — protobuf accessors are resolved lazily by GPBMessage)
  YTIIosPlayerAttestationConfig  hasIosguardEnable / iosguardEnable
  YTIHeartbeatAttestationConfig  hasRequiresAttestation / requiresAttestation
  YTIIosPlayerConfig             heartbeatPolicyErrorIsNonFatal,
                                 requestIosguardDataAfterPlaybackStarts
  -[YTHotConfig iosClientGlobalConfigDisableIosPoTokens] -> YES
```

### The `visibleSections` bitmask — how it was determined

Sweeping the value on device (via the plist trick above), **not** inferred:

| Value | Result |
|---|---|
| `5` (`0b101`) | YouTube's own value — comments + related both shown |
| `4` (`0b100`) | related shown, comments **gone** → bit 2 is the related list |
| `2` (`0b010`) | neither shown |

So `sections & ~4` drops the related list and keeps comments. Masking rather than assigning a
literal leaves other bits intact.

### iPad watch-page architecture (10-round investigation, solved 2026-08-23)

Everything below was established from on-device probe logs on the iPad (iOS 16.7.16), not
inferred. The full round-by-round log is preserved as comments above the
`YTWatchNextResultsViewController` / `YTWatchNextResponseViewController` hooks in `Tweak.x`
— read that before touching any watch-page hook.

**Instance model.** At least two `YTWatchNextResultsViewController` instances are live per
video, and **they rotate roles**:

- a stable *primary* (title/description/comments) whose `visibleSections` is `1` or `5`,
- a per-video *secondary* whose `visibleSections` is always a hardcoded `0` (not a bitmask)
  and which is fed a `YTISectionListRenderer` — this one populates the landscape right
  column,
- the same instance can carry `5` on one load and be demoted to `0` on the next —
  `nativeZero` is a reliable *current-role* signal but NOT a stable instance identity.

**Why the iPhone fix is a no-op on iPad.** `divideContentBetweenWatchNextAndDescription-
Details_compact` vs `..._regular` (both real selectors on `YTWatchNextResponseViewController`)
pick the layout by width. In the regular/two-column layout the secondary's `0` never carries
the related bit, so clearing bit 2 masks nothing. The bitmask mask still matters — it hides
below-video suggestions in portrait — but the column is a *layout* choice, not a sections
choice.

**What does NOT work (do not retry):**

- Blocking `createWatchNextResultsViewControllerAllowingReuse:NO` or
  `createDescriptionDetailsViewControllerAllowingReuse:` — some other factory path steps in
  and populates the pane anyway (whack-a-mole, rounds 4–6).
- Skipping `loadWithModel:` on nativeZero instances (round 9) — hides the suggestions but
  (a) the description-details pane still renders a duplicate of title/likes/comments into
  the column, and (b) it breaks portrait after a landscape stint: the instance that did
  column duty keeps its loads skipped when it returns to below-video duty.
- Forcing `shouldUseDescriptionDetailsViewController` / `shouldUseTeaserCarouselView-
  Controller` to NO — this is what caused the "title/description render then get erased,
  comments never show" regression. Both are plain probes now; never force them.

**What works (round 10).** Hook the four `isWide` gates to NO under `BrambleHideSuggested`
(hook list in section 4). The watch page then renders the compact single-column layout in
landscape too — no column exists, content sits below the video in both orientations,
rotation is stateless. No-ops on iPhone (already compact).

**Misattribution warning.** Round 7 "broke the watch page" and was reverted on that
conclusion — but the actual culprit shipped in the same build: `BrambleHideComments`
defaulting ON, which masked the primary's native `5` to `0`. When a build carries more than
one change and something breaks, bisect the *changes*, not the hypothesis.

---

## 5. Findings that cost the most to establish

### CydiaSubstrate is unusable on modern iOS

The Substrate that `theos-jailed` fetches from `apt.saurik.com` (0.9.6301) links
`/usr/lib/libstdc++.6.dylib`, **removed from iOS after 12**. It cannot load on iOS 26, so
`Bramble.dylib` (which depended on it) couldn't load either — and because theos-jailed injects
as `LC_LOAD_WEAK_DYLIB`, dyld **skipped it silently**. YouTube launched looking untouched.

Fix: `Bramble_LOGOS_DEFAULT_GENERATOR = internal` in the Makefile. Logos then swizzles with
`method_setImplementation` and needs no Substrate at all. **Only valid because Bramble uses no
`%hookf`** — adding one means going back to MobileSubstrate, and then a modern Substrate must
be vendored (YTKillerPlus ships one linking `libc++.1.dylib`, packaged with `cyan`).

`package.sh` Check 5 counts `MSHookMessageEx|_method_setImplementation` so it stays honest
across either generator. Invariant: live build ≥1, `INERT=1` build 0.

### Signed-out playback: **do not re-investigate**

YouTube 21.x gates `/player` behind App Attest, whose keys derive from
`application-identifier`. Any developer/Sideloadly signature rewrites that from
`EQHXZ8M8AV.com.google.ios.youtube` to the signer's team, so attestation fails and the backend
returns an error playability status (`PLAYBACK ERROR code=14`, server-authored
`YTIPlayerErrorMessageRenderer`, reason *"Something went wrong. Refresh and try again later."*).
Search needs no attestation, which is why it keeps working and makes this look like a codec or
packaging fault.

Proven on device:

- Stock App Store YouTube plays signed-out → target is reachable, but only with Google's signature.
- Bramble with its dylib **deleted** fails identically → not caused by any hook.
- **YTKillerPlus re-signed with our certificate fails identically.** YTK ships ad-hoc with
  *Google's* `application-identifier` and no provisioning profile — it is a
  **TrollStore/jailbreak artefact, not a sideload**. iOS 26.6 has neither.
- Client impersonation is unavailable: `YTIClientInfo` is a **shared singleton** (same pointer
  across successive `decorateContext:` calls), so rewriting `clientName` for player requests
  rewrites it for *every* InnerTube request. Setting it to `TVHTML5` broke search and thumbnails.

**Signing in works.** That is the supported mode and what `PROJECT.md` already requires.

The only remaining theoretical route is minting a **web PoToken** by evaluating YouTube's
BotGuard challenge in `JavaScriptCore` and returning it from
`-[YTProofOfOriginTokenManager mintWithVideoID:]`. Opaline does this but offloads the JS to a
closed-source helper server (because it targets iOS 12 hardware; on iOS 26 JSC can do it
on-device). Days of work, breaks whenever Google rotates BotGuard.

### Version spoofing is a two-sided constraint

PoToken enforcement is keyed off the reported client version, so an older version escapes it.
But YouTube's **December 2025** server change dropped support for clients at **20.23.3 and
below** — home and search break. Reproduced: 19.20.2 gave *"Error loading. Tap to retry."* on
search. Current target is **20.21.6** (what `YouTubeLegacy` uses as of its early-2026 update).
The window may close entirely, which is why it's a toggle.

---

## 6. Dead ends — already tried, do not repeat

| Attempt | Outcome |
|---|---|
| Restoring Google's keychain groups under our team | No change to signed-out playback |
| `iosClientGlobalConfigDisableIosPoTokens = YES` | No change (server refuses regardless) |
| YTK's full attestation config hook set | No change |
| Impersonating `TVHTML5` client | Broke search + thumbnails (shared `YTIClientInfo`) |
| Porting muTube's patches | Cobalt codec gates + JS injection; tvOS doesn't use App Attest |
| Filtering `_sectionRenderers` for related videos | Dropped 4 of 7 sections, **zero visual change** |
| Matching `sectionIdentifier == "related-items"` | Only appears on the pagination path, not first render |
| `com.apple.developer.coremedia.allow-alternate-video-decoder-selection` theory | Wrong: a decoder fault fails per-format; *every* video failed while search worked |
| Masking bit 2 of `visibleSections` on iPad | No-op: the column instance is fed `0`, never a real bitmask |
| Blocking the watch-next/description-details factory methods | Fallback paths create and populate the pane anyway |
| Skipping `loadWithModel:` on `sections==0` instances | Column keeps a duplicate description pane; breaks portrait after rotation |
| Forcing `shouldUse{DescriptionDetails,TeaserCarousel}ViewController` to NO | Erased title/description, comments never rendered |

---

## 7. Open items

- **Diagnostics still shipping.** The `NSError` player-error hooks (`yt_attestationErrorWithCode:`,
  `playerErrorWithCode:details:`, `playbackErrorWithCode:playerErrorMessageRenderer:`) and
  `brambleProbe` remain in. They fire only on failure, but should be gated or removed for a
  daily build.
- **`YTAppSettingsPresentationData settingsCategoryOrder`** hook is retained but does nothing —
  `YTSettingsGroupData` is what renders. Harmless; could be deleted.
- **SponsorBlock** — researched, unbuilt. All seams verified on `YTPlayerViewController`:
  `currentVideoID`, `currentVideoMediaTime`, `seekToTime:`, plus
  `potentiallyMutatedSingleVideo:currentVideoTimeDidChange:` and
  `playbackController:didActivateVideo:withPlaybackData:`. Use the **hash-prefix** endpoint
  (`/api/skipSegments/{first-4-of-SHA256(videoID)}`) so video IDs never leave the device —
  YTKillerPlus uses the plain `?videoID=` endpoint, which hands the server a viewing history.
- **`cyan` instead of theos-jailed** for packaging. `CLAUDE.md` flags theos-jailed as the
  stack's biggest fragility (~3 years dormant); YTK packages with `cyan`.
- **Phase 1 `01-05` device gate** is effectively satisfied (load line confirmed, sign-in
  confirmed) but the plan is not marked complete.
- **iPad: suggested videos — SOLVED 2026-08-23 (round 10).** `BrambleHideSuggested` now forces
  the watch page into the compact single-column layout on iPad by hooking the four `isWide`
  gates (`YTWatchViewController isWideLayoutForWatchView:`, `YTWatchLayerViewController
  isWideWatchLayout`, `YTSectionListDrawerView isWideMode`, `YTSectionListDrawerViewController
  isWideModeWithWidth:`) to NO. No right column exists in that mode; title/description/comments
  render below the video in both orientations, and rotation portrait↔landscape keeps them.
  Verified on device. Full round-by-round history (including the dead ends: masking, creation
  blocking, load-skipping) is preserved as comments above the
  `YTWatchNextResultsViewController` / `YTWatchNextResponseViewController` hooks in `Tweak.x`.
  Two adjacent fixes from the same session: the "title/description erased, comments missing"
  regression was the still-active round-2/3 forcing of
  `shouldUseDescriptionDetailsViewController`/`shouldUseTeaserCarouselViewController` to NO
  (both reverted to plain probes), and `Hide comments` now defaults OFF in `bramblePref`
  (defaulting ON combined with Hide suggested to mask the primary's native `5` to `0`).

---

## 8. Working method that actually converged

1. **Verify every selector and class name against the target binary** before writing a hook.
   Headers and other tweaks are both stale in ways that fail *silently*.
2. **Instrument first.** Add a probe, install, read the log. Do not ship a hypothesis-driven fix.
3. **Run the control.** When something breaks, build with the dylib removed. That single test
   separated "our bug" from "packaging" after several rounds of guessing.
4. **Make unknowns runtime-tunable.** Reading a value from `NSUserDefaults` turned a five-minute
   build-sign-install cycle into a thirty-second plist write. That is what cracked
   `visibleSections`.
5. **A null result is information.** Filtering that removes sections with no visual change means
   you are on the wrong lever — stop refining the match and find a different seam.
6. **Bisect changes, not hypotheses.** Round 7 was reverted for a regression actually caused by
   a different change shipped in the same build (see the misattribution warning in section 4).
   When a build carries more than one change and something breaks, split the changes before
   concluding anything about the mechanism.

---

## 9. Repo and release state (2026-08-23)

- Sources live in git as of `d070bb1` (quark-wave branch) — before that `bramble/` was untracked.
- Remote: `origin` = `https://github.com/OsamaMazhar/Bramble.git` (existing **public** fork of
  PoomSmart/YouTube-X; tweak sources only — no IPA, no decrypted binaries, no `bramble.config`).
- First release: branch **`release/v0.1.0`** and annotated tag **`v0.1.0`**, both at `d070bb1`.
- Fresh-machine replication: `bootstrap-toolchain.sh` pins Theos / theos-jailed /
  YouTubeHeader by SHA; `bramble.config.example` documents the operator-supplied decrypted
  IPA; `package.sh` + `deploy.sh` carry build, sign, and per-device install (devicectl for
  iOS 17+, ios-deploy for iOS 16 — see section 2).
