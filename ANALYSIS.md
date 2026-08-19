# YTKillerPlus 6.0 (YouTube 21.31.3) — teardown vs. open-source tweaks

## 1. Package layout

```
Payload/YouTube.app/
  YouTube                              210 MB  Google's binary (untouched, arm64)
  Frameworks/YTKPlus.dylib              27 MB  the tweak
  Frameworks/CydiaSubstrate.framework   396 KB bundled hooking runtime
  YTKPlus.bundle/                       assets, 15 .lproj localizations, SponsorAudio.m4a
```

- `YTKPlus.dylib` install name is `/Library/MobileSubstrate/DynamicLibraries/YTKPlus.dylib` →
  built as a normal jailbreak tweak, then repackaged for sideloading. Substrate is shipped
  inside the app and the dylib is injected as `LC_LOAD_WEAK_DYLIB @rpath/YTKPlus.dylib` — weak, not `LC_LOAD_DYLIB`. That is the signature of theos-jailed's `insert_dylib --weak`, so the reference build used that pipeline too.
- `LC_ENCRYPTION_INFO_64` present with **cryptid 0** → not encrypted, fully readable.
- Symbols stripped (no `_logos_*`), but 8 initializers + `MSHookMessageEx` call sites are intact.
- Links `libroot.dylib` at runtime (rootless/roothide path resolution) — jailbreak build lineage.

**Most of the 27 MB is not the tweak.** It statically links MobileFFmpeg (FFmpeg + gnutls +
libz/bz2/iconv) for the download/re-mux feature. The actual hook logic is a few hundred KB.

## 2. How hooking is done

Everything is runtime ObjC swizzling via Substrate. Imported: `MSHookMessageEx`,
`class_addMethod`, `class_addProperty`, `method_setImplementation`, `objc_getClass`,
`NSSelectorFromString`. No `MSHookFunction`, no `fishhook`, **no network-level filtering**
(no proxy, no NSURLProtocol, no host blocklist — grep for googleads/doubleclick/pagead: zero hits).

Measured: **323 `MSHookMessageEx` sites across 140 classes**, plus ~260 `class_addMethod`
sites (Logos `%new`). Full map in `work/hookmap.txt`.

## 3. Ad blocking — the hook surface

| Layer | Hooked | Effect |
|---|---|---|
| Request | `YTAdsInnerTubeContextDecorator`, `YTAccountScopedAdsInnerTubeContextDecorator` → `decorateContext:` | ad context never attached to InnerTube requests |
| Fingerprint | `YTAdShieldUtils` / `YTDataUtils` → `spamSignalsDictionary`, `spamSignalsDictionaryWithoutIDFA` | returns empty dict |
| Player response | `YTIPlayerResponse` / `YTPlayerResponse` %new `playerAdsArray`, `adSlotsArray` | empty arrays → no pre/mid-roll |
| Playback | `YTLocalPlaybackController` → `createAdsPlaybackCoordinator` (nil), `isPlayingAd`, `isPlayingAdIntro`, `isPlayingAdSurvey`, plus `reloadPlayerAndStartPlayback:`, `refreshStreamingDataAndStartPlayback:`, `restoreToState:startPlayback:` |
| Cast | `MDXSession`, `MDXSessionImpl` → `adPlaying:` (no-op) |
| Feed | `YTInnerTubeCollectionViewController` → `displaySectionsWithReloadingSectionControllerByRenderer:`, `addSectionsFromArray:` | filters `YTIItemSectionRenderer` / `YTIShelfRenderer` arrays |
| Element | `YTIElementRenderer` → `companionAd`, `hasCompanionAdRenderer`, `hasShoppingCompanionAdRenderer`, `hasAppPromoCompanionAdRenderer` |
| Shorts | `YTReelDataSource`, `YTReelContentModel`, `YTReelInfinitePlaybackDataSource` → `makeContentModelForEntry:` | drops `videoType == 3` (ad reels) |
| Overlay | `YTMainAppVideoPlayerOverlayViewController` → `playerOverlayProvider:didInsertPlayerOverlay:`; `_ASDisplayView` → `didMoveToWindow` | kills `player_overlay_product_in_video`, `eml.expandable_metadata.vpp` |
| Promos | `YTPromoThrottleController(Impl)` → `canShowThrottledPromo*`; `YTPromosheetController`, `YTSurveyController`, `YTUpgradeController`, `YTGlobalConfig.shouldBlockUpgradeDialog` |

Renderer-ID blocklist found verbatim in `__cstring`:
`brand_promo`, `carousel_footered_layout`, `carousel_headered_layout`, `eml.expandable_metadata`,
`feed_ad_metadata`, `full_width_portrait_image_layout`, `landscape_image_wide_button_layout`,
`post_shelf`, `product_carousel`, `product_engagement_panel`, `product_item`, `shopping_carousel`,
`shopping_item_card_list`, `square_image_layout`, `text_image_button_layout`, `text_search_ad`,
`video_display_full_layout`, plus `eml.ad_text_search_ad` (extra).

## 4. Diff vs. open source

Reference: **`PoomSmart/YouTube-X`** (MIT, 268 lines of Logos) — the cleanest open implementation.
Also `Tonwalter888/YouMod` `Files/Ads.x`. `dayanch96/YTLite` is source-available but unlicensed.

**They are the same implementation.** Not merely the same technique — the same code:

- Hook-for-hook identical class/selector set for every layer above.
- Identical renderer-ID blocklist strings, same order.
- Leaked log format strings name the open-source functions directly:
  `[filteredArray] blocked content | class=%@ | section=%@`,
  `[isAdRenderer] adLoggingData match | class=%@` — `filteredArray()` and `isAdRenderer()`
  are the two static helpers in YouTube-X's `Tweak.x`.

What YTKPlus adds on top:

| Addition | Detail |
|---|---|
| Ad Log diagnostic | `YTKPlusAdLoggingEnabled` → writes `YTKPlus_AdLog.txt` / "YTKPlus Ad Log Report" with every blocked class + section. This is their maintenance loop for keeping the blocklist current when YouTube renames renderers. |
| Companion-ad hooks | Direct `YTIElementRenderer` companion-ad accessors; YouTube-X only reads `compatibilityOptions.hasAdLoggingData`. |
| Wider playback coverage | `isPlayingAd*` family + the reload/refresh/restore paths, not just `createAdsPlaybackCoordinator`. |
| Anti-anti-adblock awareness | `YTProofOfOriginTokenManager`, `YTIIosPlayerAttestationConfig`, `YTIHeartbeatAttestationConfig`, `YTIServiceIntegrityDimensions`, `auth_integrity_seal` referenced. |
| Licensing + self-protection | `action=verify&email=%@&licenseKey=%@&deviceIdentifier=%@&timestamp=%@&nonce=%@`, `YTKPlus_Verify`, `iKarwanYTKLicense`, plus Frida detection (`detectFridaGadget`, `libfrida-gadget.dylib`, `X-Frida-Port`). Paid tweak; open-source ones have none of this. |

## 5. Non-ad features (why it's 27 MB)

- **Downloads** — `YTKDLDownloader`, `YTKDLSession`, `YTKDLTask`, `YTKDLTrack`, `YTKDLHLSExtraction`,
  `YTKDLStreamOption`, `YTKFileMultiDownloadCenter` + `MobileFFmpeg`/`MobileFFprobe` for HLS/DASH
  demux and mux. Separate video / audio / Shorts queues.
- **Local player** — `AudioViewController`, `VideoViewController`, `MiniPlayerView`,
  `LyricsSheetViewController`, background audio (`UIBackgroundModes: audio` in the bundle plist).
- **SponsorBlock** — `setSponsorBlockValues:`, `setSponsorSegmentsForProgressBar:`, `SponsorAudio.m4a`.
- **Settings UI** — `iKarwanYTKsettings`, `TabBarSettingsViewController`, `IconSelectorViewController`
  (alt icons), `OverlayOptionsController`, `VLCGestureOptionsController`, `ShortsOptionsController`,
  `StreamOptionsController`, `NavBarOptionsController`.
- **Backup/restore** — `YTKPlus_Backup.zip` via `SSZipArchive`.
- Vendored: `MBProgressHUD`, `FCFileManager`, `FCUUID`, `UICKeyChainStore`, `Reachability`, `SSZipArchive`.

## 6. Building your own

1. Start from `PoomSmart/YouTube-X` (MIT) + `PoomSmart/YouTubeHeaders`. Theos, one `Tweak.x`.
2. Package like `qnblackcat/uYouPlus`: decrypted YouTube IPA + `insert_dylib` + `ldid` re-sign.
   That Makefile flow is the standard, and is what produced this IPA's layout.
3. The blocklist is the only part that rots. Port YTKPlus's ad-log idea: log
   `elementRenderer.description` for anything you drop, so renamed renderers are a 2-minute fix.
4. Skip FFmpeg unless you need muxed downloads — it is ~26 MB of the 27 MB.

## Reproducing this analysis

```sh
unzip -o -q <ipa> 'Payload/YouTube.app/Frameworks/YTKPlus.dylib' -d work/
xcrun llvm-objdump -d --macho --no-show-raw-insn work/.../YTKPlus.dylib > ytk.asm
# hook map: for each `bl ... _MSHookMessageEx`, take nearest preceding
# `literal pool for: "Class"` and `Objc selector ref: sel`
```
`work/hookmap.txt` was generated that way. The class attribution uses a nearest-preceding
heuristic over a 45-instruction window, so a handful of entries where a class was held in a
callee-saved register across several hooks may be mis-attributed; the selector lists are exact.
