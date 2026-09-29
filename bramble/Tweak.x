#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTIPivotBarItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTIPivotBarSupportedRenderers.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
// Declared rather than imported: YouTubeHeader has no header for the engagement-panel
// container, and these two selectors are all Bramble needs off it. Every call site guards
// with respondsToSelector:, so a rename in a future YouTube degrades to "panel not hidden"
// rather than a crash.
@interface NSObject (BrambleEngagementPanel)
- (id)topEngagementPanelViewController;
- (id)panelIdentifier;
@end

#import <objc/runtime.h>
#import <HBLog.h>
#import <os/log.h>

// Preferences. Every toggle defaults ON, so a fresh install behaves exactly like the build
// that shipped before this file grew a settings section -- an absent key must never read as
// "feature off". Adding a future feature is one row in brambleSettingsRows() plus the hook
// that reads its key; there is deliberately no config class, no plist, and no registration
// step to keep in sync.
static NSString *const kBrambleBlockAds = @"BrambleBlockAds";
static NSString *const kBrambleBackgroundPlayback = @"BrambleBackgroundPlayback";
static NSString *const kBrambleNoSpeedmaster = @"BrambleNoSpeedmaster";
static NSString *const kBrambleNoSpeedmasterShorts = @"BrambleNoSpeedmasterShorts";
static NSString *const kBrambleNoDoubleTapSeek = @"BrambleNoDoubleTapSeek";
static NSString *const kBrambleSpoofVersion = @"BrambleSpoofVersion";
static NSString *const kBrambleHideShorts = @"BrambleHideShorts";
static NSString *const kBrambleHideSuggested = @"BrambleHideSuggested";
static NSString *const kBrambleHideComments = @"BrambleHideComments";
static NSString *const kBrambleHidePlaylistNext = @"BrambleHidePlaylistNext";
static NSString *const kBrambleLoopButton = @"BrambleLoopButton";

// PoToken enforcement is keyed off the client version the app reports. Older versions
// predate it, so the backend does not demand a token a re-signed build cannot mint. This is
// uYouEnhanced's App Version Spoofer, reduced to the one hook that matters:
// +[YTVersionUtils appVersion], confirmed present in 21.32.4.
// 20.21.6 is what PoomSmart's YouTubeLegacy spoofs to as of its early-2026 update. 19.20.2
// (suggested in uYouEnhanced #924) does restore playback but breaks home and search: YouTube's
// December 2025 server change dropped support for clients at 20.23.3 and below, which was
// reproduced here -- search returned "Error loading. Tap to retry."
#define BRAMBLE_SPOOFED_VERSION @"20.21.6"

// TEMPORARY diagnostic. os_log with a custom subsystem reaches neither `devicectl
// ... --console` nor the syslog relay, and a console attach only captures what happens
// while it is attached -- useless for a hook that fires when the user opens a screen.
// A file in the app container can be pulled afterwards with `devicectl device copy from`.
// Remove once the settings insertion point is settled.
static void brambleProbe(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[Bramble] %@", line);
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [dir stringByAppendingPathComponent:@"bramble-probe.log"];
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        [stamped writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

// Arbitrary settings-category number. Its only job is to collide with nothing YouTube uses.
// Engagement-panel identifier for the playlist queue sheet, read out of the 21.32.4 binary
// (the full set of "engagement-panel-*" identifiers is in __cstring).
#define BRAMBLE_PLAYLIST_PANEL_ID @"engagement-panel-playlist"

// Which loopMode value means "repeat this video". -[YTMainAppVideoPlayerOverlayViewController
// setLoopMode:] takes a long whose enum is not named anywhere in the binary, so the value is
// read from NSUserDefaults instead of compiled in: it can be swept on device with the
// PlistBuddy round-trip in HANDOFF section 3 rather than costing a build per guess. 2 is the
// starting guess (0 off, 1 all, 2 one).
// Whether loop is currently on. Runtime state rather than a settings row: the button writes
// it, the playback hooks read it. Kept in NSUserDefaults only so it survives a relaunch.
#define BRAMBLE_LOOP_ACTIVE_KEY @"BrambleLoopActive"

static BOOL brambleLoopActive(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BRAMBLE_LOOP_ACTIVE_KEY];
}

#define BRAMBLE_LOOP_MODE_KEY @"BrambleLoopModeValue"
#define BRAMBLE_LOOP_MODE_DEFAULT 2

#define BRAMBLE_SETTINGS_CATEGORY 0x42524D

static BOOL bramblePref(NSString *key) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) return [value boolValue];
    // Every other toggle defaults ON (see the note above brambleSettingsRows()). This one is a
    // deliberate exception, confirmed on device: combined with kBrambleHideSuggested's bit
    // (both default ON), the two together mask visibleSections down to exactly 0 on this iPad's
    // results controller -- a value the original sweep never tested, and which blanked the
    // whole results list, title and description included, not just comments. Defaulting this
    // one to NO keeps a fresh install identical to the build before the toggle existed, which
    // is what "defaults ON" was supposed to guarantee for every row -- it just means NO here
    // instead of YES, since ON is the state that was never proven safe.
    if ([key isEqualToString:kBrambleHideComments]) return NO;
    return YES;
}

// {key, title, description}. Rows whose hooks are registered in %ctor rather than consulted
// per-call say "after restarting" -- a switch that silently needs a relaunch is worse than
// one that admits it.
static NSArray <NSArray <NSString *> *> *brambleSettingsRows(void) {
    return @[
        @[kBrambleBlockAds, @"Block ads",
          @"Filters ad renderers from the feed, player, and Shorts. Takes effect after restarting YouTube."],
        @[kBrambleBackgroundPlayback, @"Background playback",
          @"Keeps audio playing when the app is backgrounded. Takes effect after restarting YouTube."],
        @[kBrambleNoSpeedmaster, @"Disable hold for 2x speed",
          @"Stops press-and-hold on the player from jumping to 2x speed."],
        @[kBrambleNoSpeedmasterShorts, @"Disable hold for 2x speed in Shorts",
          @"The same gesture inside Shorts. Takes effect after restarting YouTube."],
        @[kBrambleNoDoubleTapSeek, @"Disable double tap to seek",
          @"Stops double-tapping the left or right side of the player from skipping backward or forward."],
        @[kBrambleHideSuggested, @"Hide suggested videos",
          @"Suppresses the related-videos panel that pulls up over the player and the suggestions shown beside the video on iPad."],
        @[kBrambleHideComments, @"Hide comments",
          @"Removes the comments section below the player. Defaults off, unlike other toggles: on the iPad two-column layout, combining this with Hide suggested videos was confirmed to blank the whole panel (title and description too), not just comments."],
        @[kBrambleHidePlaylistNext, @"Hide the playlist Next bar",
          @"Removes the floating bar above the tab bar that announces the next video in a playlist or queue."],
        @[kBrambleLoopButton, @"Loop button on the player",
          @"Adds a repeat button to the player controls. It appears and hides with the rest of the controls."],
        @[kBrambleHideShorts, @"Hide Shorts",
          @"Removes the Shorts tab and Shorts shelves, cells and history entries from every feed."],
        @[kBrambleSpoofVersion, @"Report an older app version",
          @"Reports YouTube 19.20.2 to the server, which predates the proof-of-origin check that blocks signed-out playback on a re-signed build. Restart after changing."],
    ];
}

// All hooks live in a named group (not the default/ungrouped group) so their bodies always
// compile -- Logos scans %hook/%end/%init purely by text and has no awareness of C
// preprocessor conditionals. A bare `%init;` (default group) unconditionally emits a
// MSHookMessageEx-calling table referencing every hook it found textually, even ones whose
// *bodies* a surrounding #ifndef strips out -- that mismatch is what an inert build needs to
// avoid. Gating only the %init(...) calls below (not the hook bodies) keeps compilation
// correct in both configurations while still producing zero MSHookMessageEx references in an
// INERT=1 build (package.sh Check 5).
//
// Three groups, because "off" means two different things here. Core's hooks all override real
// methods, so they read their preference per call and a switch takes effect immediately. Ads
// and Background contain %new methods, which have no %orig to fall back to -- once
// class_addMethod has run there is no original behaviour left to restore -- so their only
// honest switch is whether %ctor registers the group at all.
%group Ads
%hook YTGlobalConfig

- (BOOL)shouldBlockUpgradeDialog { return YES; }

%end

%hook YTIPlayerResponse

%new(@@:)
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}

%new(@@:)
- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}

%end

%hook YTIClientMdxGlobalConfig

%new(B@:)
- (BOOL)enableSkippableAd { return YES; }

%end

%hook YTHotConfig

- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }

%end

%hook YTAdShieldUtils

+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }

%end

%hook YTDataUtils

+ (id)spamSignalsDictionary { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }

%end

%hook YTLocalPlaybackController

- (id)createAdsPlaybackCoordinator { return nil; }

%end

%hook MDXSession

- (void)adPlaying:(id)ad {}

%end

%hook MDXSessionImpl

- (void)adPlaying:(id)ad {}

%end

%hook YTReelDataSource

- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}

%end

// For newer YouTube versions
%hook YTReelContentModel

+ (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}

%end

%hook YTReelInfinitePlaybackDataSource

- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}

- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return [obj respondsToSelector:@selector(videoType)] ? obj.videoType == 3 : NO;
    }]];
    %orig;
}

%end

static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)]) {
        YTIShowEngagementPanelEndpoint *endpoint = [command yt_showEngagementPanelEndpoint];
        return [endpoint.identifier.tag isEqualToString:@"PAproduct_list"];
    }
    return NO;
}

%hook YTWatchNextResponseViewController

- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        YTICommandExecutorCommand *commandExecutorCommand = [onUiReady yt_commandExecutorCommand];
        NSMutableArray <YTICommand *> *commandsArray = commandExecutorCommand.commandsArray;
        [commandsArray removeObjectsAtIndexes:[commandsArray indexesOfObjectsPassingTest:^BOOL(YTICommand *command, NSUInteger idx, BOOL *stop) {
            return isProductList(command);
        }]];
    }
    if (isProductList(onUiReady))
        model.onUiReady = nil;
    %orig;
}

%end

%hook YTMainAppVideoPlayerOverlayViewController

- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_product_in_video"]) return;
    %orig;
}
%end

NSString *getAdString(NSString *description) {
    for (NSString *str in @[
        @"brand_promo",
        @"brand_video_shelf",
        @"carousel_footered_layout",
        @"carousel_headered_layout",
        @"eml.expandable_metadata",
        @"feed_ad_metadata",
        @"full_width_portrait_image_layout",
        @"full_width_square_image_layout",
        @"grid_ads_image_layout",
        @"landscape_image_wide_button_layout",
        @"post_shelf",
        @"product_carousel",
        @"product_engagement_panel",
        @"product_item",
        @"shopping_carousel",
        @"shopping_item_card_list",
        @"statement_banner",
        @"square_image_layout",
        @"text_image_button_layout",
        @"text_search_ad",
        @"video_display_full_layout",
        @"video_display_full_buttoned_layout"
    ])
        if ([description containsString:str]) return str;

    return nil;
}

static BOOL isAdRenderer(YTIElementRenderer *elementRenderer, int kind) {
    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] && elementRenderer.hasCompatibilityOptions && elementRenderer.compatibilityOptions.hasAdLoggingData) {
        HBLogDebug(@"YTX adLogging %d %@", kind, elementRenderer);
        return YES;
    }
    NSString *description = [elementRenderer description];
    NSString *adString = getAdString(description);
    if (adString) {
        HBLogDebug(@"YTX getAdString %d %@ %@", kind, adString, elementRenderer);
        return YES;
    }
    return NO;
}

static NSMutableArray <YTIItemSectionRenderer *> *filteredArray(NSArray <YTIItemSectionRenderer *> *array) {
    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)]) {
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            YTIHorizontalListRenderer *horizontalListRenderer = content.horizontalListRenderer;
            NSMutableArray <YTIHorizontalListSupportedRenderers *> *itemsArray = horizontalListRenderer.itemsArray;
            NSIndexSet *removeItemsArrayIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *horizontalListSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = horizontalListSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 4);
            }];
            [itemsArray removeObjectsAtIndexes:removeItemsArrayIndexes];
        }
        if (![sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)])
            return NO;
        NSMutableArray <YTIItemSectionSupportedRenderers *> *contentsArray = sectionRenderer.contentsArray;
        if (contentsArray.count > 1) {
            NSIndexSet *removeContentsArrayIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *sectionSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = sectionSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 3);
            }];
            [contentsArray removeObjectsAtIndexes:removeContentsArrayIndexes];
        }
        YTIItemSectionSupportedRenderers *firstObject = [contentsArray firstObject];
        YTIElementRenderer *elementRenderer = firstObject.elementRenderer;
        return isAdRenderer(elementRenderer, 2);
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    if (([self.accessibilityIdentifier isEqualToString:@"eml.expandable_metadata.vpp"]))
        [self removeFromSuperview];
}

%end

%hook YTInnerTubeCollectionViewController

- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sectionRenderers) forKey:@"_sectionRenderers"];
    %orig;
}

- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    %orig(filteredArray(array));
}

%end
%end // end group Ads

%group Background

%hook YTIPlayabilityStatus

- (BOOL)isPlayableInBackground { return YES; }

%end

%hook MLVideo

- (BOOL)playableInBackground { return YES; }

%end

%hook YTIBackgroundOfflineSettingCategoryEntryRenderer

%new(B@:)
- (BOOL)isBackgroundEnabled { return YES; }

%end

%end // end group Background

// YTIIcon.iconType is a protobuf enum into YouTube's own icon set, not an image reference --
// there is no field to hand it a custom asset. Using a built-in type is therefore the only way
// to get a glyph that matches the other rows' weight and tint in both light and dark mode.
// YT_TUNE (530) is the slider glyph; `ic_tune` is confirmed present in 21.32.4's assets.
static YTIIcon *brambleSectionIcon(void) {
    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = YT_TUNE;
    return icon;
}

// Playback integrity. A re-signed build attests with our Team ID, not Google's, so the
// player's iosguard/heartbeat attestation is rejected server-side. That is why every video
// fails while search still returns results, and why it reproduces with Bramble's dylib
// deleted entirely -- it is a consequence of re-signing, not of any hook here.
//
// These are the same four config classes YTKillerPlus hooks (see work/hookmap.txt); they
// exist in that build for exactly this reason -- they make YouTube tolerate an attestation
// it cannot complete instead of treating the failure as fatal.
//
// The accessors are generated lazily by GPBMessage's +resolveInstanceMethod:, so they are
// absent from the class's static method list and must be added with %new, the same reason
// upstream uses %new for YTIPlayerResponse's playerAdsArray. class_addMethod runs in %ctor
// before protobuf resolves anything, so our implementation is the one that wins.
//
// Each value is paired with its has* accessor returning YES, so the field reads as
// explicitly present rather than absent -- an absent field falls back to a server-supplied
// default, which is the thing being overridden.
// Diagnostics for the playback refusal. The user-facing "Something went wrong. Refresh and
// try again later." text is in neither the binary nor any bundle -- only the assertion
// string "'Something went wrong' panel should always have an associated error" is -- so the
// message is server-sent and the client is being refused rather than failing locally. These
// hooks report the associated error that assertion refers to, instead of inferring it.
//
// Note +[YTAttestation playerErrorWithCode:details:] exists as a category in this binary:
// attestation mints player errors directly. Its category extends an out-of-image class, so
// it cannot be named in a %hook; YTWatchFlowController is on the same failure path and is
// concrete.
%group Diagnostics

%hook YTWatchFlowController

- (void)playbackControllerDidFailWithError:(NSError *)error {
    brambleProbe(@"WATCH FAIL domain=%@ code=%ld userInfo=%@",
                 error.domain, (long)error.code, error.userInfo);
    %orig;
}

%end

%hook YTQueueController

- (void)playbackControllerDidFailWithError:(NSError *)error {
    brambleProbe(@"QUEUE FAIL domain=%@ code=%ld userInfo=%@",
                 error.domain, (long)error.code, error.userInfo);
    %orig;
}

%end

%hook YTRestrictedContentFlow

// Dumps the playability status protobuf, which carries the server's status, reason and
// error-screen renderer -- Google's stated reason verbatim.
+ (BOOL)canHandlePlayabilityStatus:(id)status {
    brambleProbe(@"PLAYABILITY %@", status);
    return %orig;
}

%end

%hook YTPlayerViewController

// Confirms how far playback actually gets before the refusal.
- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)data {
    brambleProbe(@"didActivateVideo videoID=%@", [self currentVideoID]);
    %orig;
}

%end

// The error is minted here, not on the paths hooked above -- which logged nothing while the
// panel still appeared. The YTAttestation category is on NSError (its siblings are
// yt_message, yt_hasDomain:, ham_isTransientNetworkError), and it owns both the player error
// factories and playerErrorMessageRenderer, the renderer that carries the on-screen text.
// Signatures are taken from the category's own type encodings (q = long long), because a
// mismatched hook signature corrupts arguments rather than failing cleanly.
%hook NSError

+ (id)yt_attestationErrorWithCode:(long long)code {
    id error = %orig;
    brambleProbe(@"ATTESTATION ERROR code=%lld -> %@", code, error);
    return error;
}

+ (id)playerErrorWithCode:(long long)code details:(id)details {
    id error = %orig;
    brambleProbe(@"PLAYER ERROR code=%lld details=%@", code, details);
    return error;
}

+ (id)playbackErrorWithCode:(long long)code playerErrorMessageRenderer:(id)renderer {
    id error = %orig;
    brambleProbe(@"PLAYBACK ERROR code=%lld renderer=%@", code, renderer);
    return error;
}

%end

%end // end group Diagnostics

%group Integrity

%hook YTIIosPlayerAttestationConfig

%new(B@:)
- (BOOL)hasIosguardEnable { return YES; }
%new(B@:)
- (BOOL)iosguardEnable { return NO; }

%end

%hook YTIHeartbeatAttestationConfig

%new(B@:)
- (BOOL)hasRequiresAttestation { return YES; }
%new(B@:)
- (BOOL)requiresAttestation { return NO; }

%end

%hook YTIIosPlayerConfig

// The member that matches the reported symptom directly: playback ran, a mid-stream
// heartbeat policy check failed, and the failure was treated as fatal.
%new(B@:)
- (BOOL)hasHeartbeatPolicyErrorIsNonFatal { return YES; }
%new(B@:)
- (BOOL)heartbeatPolicyErrorIsNonFatal { return YES; }

// Let playback begin and gather iosguard data afterwards, rather than gating the start on it.
%new(B@:)
- (BOOL)hasRequestIosguardDataAfterPlaybackStarts { return YES; }
%new(B@:)
- (BOOL)requestIosguardDataAfterPlaybackStarts { return YES; }

%end

// Signed-out playback experiment. Right now the client sends an attestation the backend
// rejects, and a rejected token is worse than no token: YouTube ships this flag for clients
// that do not do PoTokens at all, and those are still served. Sending none may therefore be
// accepted where sending an invalid one is refused. Unlike the config hooks above this is a
// real method on YTHotConfig, so %orig exists and the override is a plain %hook.
%hook YTHotConfig

- (BOOL)iosClientGlobalConfigDisableIosPoTokens { return YES; }

%end

%end // end group Integrity

%group Core

// The tweak's own section in YouTube's Settings. Appended last rather than spliced next to a
// named category, because position is cosmetic and index-matching is one more thing to break
// on the next YouTube release.
// 21.32.4 builds Settings from groups, not from the flat settingsCategoryOrder list that
// older tweaks patch. Note the pinned YouTubeHeader declares appPreferenceCategories /
// miscellaneousCategories on this class; neither exists in this build. The real leaves are
// accountCategories, videoandAudioPreferencesCategories, helpAndPoliciesCategories and
// developmentCategories -- read off the binary, not the header.
%hook YTSettingsGroupData

- (NSArray *)videoandAudioPreferencesCategories {
    // %orig must land in a local before being messaged -- Logos's textual substitution
    // mangles `[%orig mutableCopy]`.
    NSArray *categories = %orig;
    NSMutableArray *order = [categories mutableCopy];
    if (![order containsObject:@(BRAMBLE_SETTINGS_CATEGORY)])
        [order addObject:@(BRAMBLE_SETTINGS_CATEGORY)];
    return order;
}

- (NSArray *)orderedCategoriesForGroupType:(NSUInteger)groupType {
    NSArray *categories = %orig;
    return categories;
}

%end

%hook YTAppSettingsPresentationData

+ (NSArray *)settingsCategoryOrder {
    NSArray *categories = %orig;
    return categories;
}

%end

%hook YTSettingsSectionItemManager

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    // _settingsViewControllerDelegate is an ivar with no accessor; KVC reaches it because
    // NSObject's accessInstanceVariablesDirectly is YES. If that ever stops holding, the
    // Bramble section simply does not render -- it must not take the rest of Settings down.
    YTSettingsViewController *delegate = category == BRAMBLE_SETTINGS_CATEGORY
        ? [self valueForKey:@"_settingsViewControllerDelegate"]
        : nil;
    if (delegate == nil) {
        %orig;
        return;
    }
    NSMutableArray <YTSettingsSectionItem *> *items = [NSMutableArray array];
    for (NSArray <NSString *> *row in brambleSettingsRows()) {
        NSString *key = row[0];
        [items addObject:[%c(YTSettingsSectionItem)
                switchItemWithTitle:row[1]
                   titleDescription:row[2]
            accessibilityIdentifier:key
                           switchOn:bramblePref(key)
                        switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
                            [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key];
                            return YES;
                        }
                      settingItemId:0]];
    }
    // 21.32.4 carries only the icon-taking variant of this selector; the five-argument one
    // that older tweaks call is not in the binary.
    [delegate setSectionItems:items
                  forCategory:BRAMBLE_SETTINGS_CATEGORY
                        title:@"Bramble"
                         icon:brambleSectionIcon()
             titleDescription:nil
                 headerHidden:NO];
}

%end

// "Speedmaster" is YouTube's internal name for press-and-hold-to-speed-up. This is the
// eligibility gate the player consults before arming the gesture.
%hook YTMainAppVideoPlayerOverlayViewController

- (BOOL)currentVideoIsEligibleToActivateSpeedmaster {
    return bramblePref(kBrambleNoSpeedmaster) ? NO : %orig;
}

%end

// Double tap on the left/right half of the player to skip back/forward. didDoubleTap: is the
// raw gesture handler -- no-opping it here (rather than the enableDoubleTapToSeek: setter)
// blocks every internal seek path in one place regardless of which one YouTube's own state
// machine would have used, the same reasoning as the playlist-next-bar hooks below.
%hook YTDoubleTapToSeekController

- (void)didDoubleTap:(id)recognizer {
    if (bramblePref(kBrambleNoDoubleTapSeek)) return;
    %orig;
}

%end

// The related-videos list under the player. YTWatchNextResultsViewController's
// visibleSections is a bitmask, and it -- not the section renderers -- decides what is on
// screen. Filtering _sectionRenderers was tried first and removed four of seven sections with
// no visible change, which is what pointed here; YTKillerPlus hooks this one method and
// nothing else on this class.
//
// Bit meanings established on device by sweeping the value, not inferred:
//   5 (0b101) -- YouTube's own value: comments + related
//   4 (0b100) -- related shown, comments gone   => bit 2 is the related list
//   2 (0b010) -- neither shown
// Clearing bit 2 therefore drops the related list and leaves comments intact. Masking rather
// than assigning a literal keeps any other bits YouTube sets in future untouched.
// Tunable rather than compiled in. The sweep above was done on an iPhone; the iPad's
// two-column watch page keeps showing the related column with bit 2 cleared, so the bit that
// governs it there is not yet known. Reading the mask from NSUserDefaults means the remaining
// values can be swept with the PlistBuddy round-trip in HANDOFF section 3 instead of costing a
// build-sign-install cycle each.
#define BRAMBLE_RELATED_SECTIONS_KEY @"BrambleRelatedSectionsMask"
#define BRAMBLE_RELATED_SECTIONS_DEFAULT 4

static NSInteger brambleRelatedSectionsMask(void) {
    id configured = [[NSUserDefaults standardUserDefaults] objectForKey:BRAMBLE_RELATED_SECTIONS_KEY];
    return configured ? [configured integerValue] : BRAMBLE_RELATED_SECTIONS_DEFAULT;
}

// Comments is bit 0 (value 1) of the same bitmask -- established alongside the related-list bit
// in the original sweep: 5 (0b101) is YouTube's own value with both comments and related shown,
// clearing bit 2 alone (-> 1, comments only) is what "Hide suggested videos" already does, so by
// elimination bit 0 is comments. Independent from BRAMBLE_RELATED_SECTIONS_MASK -- either toggle
// can clear its own bit without touching the other's.
#define BRAMBLE_COMMENTS_SECTIONS_BIT 1

static char kBrambleWasNativeZeroKey;

%hook YTWatchNextResultsViewController

- (void)setVisibleSections:(NSInteger)sections {
    // Tag BEFORE masking: whether YouTube itself asked for an empty section set. This is the
    // reliable secondary-pane signal (see loadWithModel: below) -- the post-mask stored value
    // is not, because our own masking can independently produce 0 on the primary instance too
    // (e.g. an original value of exactly BRAMBLE_RELATED_SECTIONS_MASK masks down to 0), which
    // is what broke title/description/comments when loadWithModel: keyed off the masked value.
    objc_setAssociatedObject(self, &kBrambleWasNativeZeroKey, @(sections == 0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger mask = 0;
    if (bramblePref(kBrambleHideSuggested)) mask |= brambleRelatedSectionsMask();
    if (bramblePref(kBrambleHideComments)) mask |= BRAMBLE_COMMENTS_SECTIONS_BIT;
    NSInteger masked = sections & ~mask;
    brambleProbe(@"visibleSections self=%p %ld -> %ld", self, (long)sections, (long)masked);
    %orig(masked);
}

// UNSOLVED -- iPad's second-column suggestions (both the two-column landscape layout AND,
// reported after this round, portrait) are not blocked by anything tried across six rounds of
// on-device instrumentation. Left here, inert, so the next attempt starts from what's already
// ruled out instead of re-discovering it:
//   Round 1: visibleSections only ever carries 0 or 1 on this layout, never a real bitmask --
//     the iPhone-proven bit-2 mask was never in play here.
//   Round 2: shouldUseTeaserCarouselViewController's own %orig was already NO -- not the gate.
//   Round 3: forcing shouldUseDescriptionDetailsViewController to NO had no visible effect --
//     the secondary YTWatchNextResultsViewController instance was still created regardless.
//   Round 4: found createWatchNextResultsViewControllerAllowingReuse: fires twice per video --
//     allowingReuse:YES for the stable primary, allowingReuse:NO for a fresh instance every
//     time (sections=0, loaded with a real YTISectionListRenderer).
//   Round 5: skipping the allowingReuse:NO call did nothing -- createDescriptionDetailsView-
//     ControllerAllowingReuse:1 fires unconditionally right after and still feeds real content.
//   Round 6: skipping BOTH create calls collapsed the two instances into one, and content still
//     loaded into it via some other fallback path -- blocking creation is a losing game of
//     whack-a-mole; something always steps in.
//   Round 7 (reverted): gated loadWithModel: on whether YouTube had called setVisibleSections:0
//     on that instance *before* our masking. "Broke title/description/comments" -- MISATTRI-
//     BUTED: that build also shipped the Hide-comments toggle defaulting ON, which masked the
//     primary's native 5 to 0 (5 -> 0 in the log). The gate itself was never actually disproven.
//   Round 8 (2026-08-23, KEPT): the erasure symptom was caused by rounds 2/3 still forcing
//     shouldUseDescriptionDetailsViewController/shouldUseTeaserCarouselViewController to NO --
//     orig=1 -> 0 fired on every load and tore down the details pane. Reverted both to plain
//     probes; title/description and comments confirmed restored on device with masking live.
//     Clean round-8 log: primary instance nativeZero=0 (sections 1) on EVERY call, column
//     instance nativeZero=1 (sections 0) on EVERY call -- the tag is a clean discriminator.
//   Round 9: skipped loadWithModel on nativeZero instances. Hid the column's suggestions but
//     (a) the description-details pane kept rendering a duplicate of title/likes/comments into
//     the column, and (b) rotating portrait -> landscape -> portrait left description/comments
//     missing: the same instance serves both roles, so once it did a sections=0 column stint
//     its loads stayed skipped forever.
//   Round 10 (current): abandoned instance-level whack-a-mole. The column is a *layout* choice:
//     the binary gates the whole two-column watch page on isWide selectors (divideContent-
//     BetweenWatchNextAndDescriptionDetails_compact vs _regular). Hide suggested now forces the
//     compact path (hooks below), so no column exists and content renders below the video in
//     both orientations. loadWithModel skip removed.
//   Also reported: suggestions persist in portrait too, not just the two-column landscape
//     layout -- meaning bit-2 masking may not be the operative mechanism on this device/iOS
//     combination in ANY orientation, not just a landscape-only gap as first assumed.
// self=%p and model=%@ are still logged on every load so a future round can correlate instances
// without re-adding this hook from scratch.
- (void)loadWithModel:(id)model {
    brambleProbe(@"loadWithModel self=%p nativeZero=%d model=%@",
        self, [objc_getAssociatedObject(self, &kBrambleWasNativeZeroKey) boolValue], NSStringFromClass([model class]));
    %orig;
}

%end

// iPad's two-column watch page does not necessarily go through visibleSections at all: the
// binary carries a wholly separate protobuf renderer for it (YTITwoColumnWatchNextResultsRenderer,
// with a distinct secondaryResults field -- SupportedRenderers string literally reads
// "TwoColumnWatchNextSecondayResultsSupportedRenderers", typo and all), and
// YTWatchNextResponseViewController has its own regular-width-only path:
// divideContentBetweenWatchNextAndDescriptionDetails_regular, gated by isWide, which asks
// shouldUseTeaserCarouselViewController before building the second-column carousel.
//
// Round 1 on device disproved both existing hooks: visibleSections only ever carries 0 or 1 on
// this layout (never a richer bitmask -- brambleRelatedSectionsMask's bit 2 was never in play),
// and shouldUseTeaserCarouselViewController's own %orig was already NO, so forcing it NO changed
// nothing -- the teaser carousel was never what's populating this column. Round 2 (probed on
// device, see the two-column screenshot this responds to): isWide is 1 and
// divideContentBetweenWatchNextAndDescriptionDetails_regular runs as expected, but the only
// should-show gate that actually came back YES was shouldUseDescriptionDetailsViewController.
// There are two YTWatchNextResultsViewController instances live at once -- a stable one
// (comments/below-player, sections=1, unaffected) and a second one recreated per video whose
// sections is always a hardcoded 0, not a real bitmask -- masking it can never do anything,
// which is why round 1 changed nothing there either. Round 3: gate the one seam that was
// actually engaged.
%hook YTWatchNextResponseViewController

// Round 8 (2026-08-23): both of these had still been forcing NO under the Hide-suggested
// pref -- leftovers from rounds 2/3 that never hid the column. Suspected (not yet confirmed)
// of causing "title/description render then get erased, comments never show": orig=1 -> 0 was
// firing on every load and this gate plausibly tears down the details pane it just rendered.
// Reverted to plain probes: log the value, never change it.
- (BOOL)shouldUseTeaserCarouselViewController {
    BOOL orig = %orig;
    brambleProbe(@"shouldUseTeaserCarouselViewController orig=%d", orig);
    return orig;
}

- (BOOL)shouldUseDescriptionDetailsViewController {
    BOOL orig = %orig;
    brambleProbe(@"shouldUseDescriptionDetailsViewController orig=%d", orig);
    return orig;
}

- (void)setWatchNextResultsViewController:(id)controller {
    brambleProbe(@"setWatchNextResultsViewController: %@ %p", NSStringFromClass([controller class]), controller);
    %orig;
}

- (void)setDescriptionDetailsViewController:(id)controller {
    brambleProbe(@"setDescriptionDetailsViewController: %@ %p", NSStringFromClass([controller class]), controller);
    %orig;
}

- (void)setTeaserCarouselViewController:(id)controller {
    brambleProbe(@"setTeaserCarouselViewController: %@ %p", NSStringFromClass([controller class]), controller);
    %orig;
}

// Round 3 forced shouldUseDescriptionDetailsViewController to NO and it still returned 0 on
// device, yet the second YTWatchNextResultsViewController instance was still created and none
// of the three setters above ever fired for it in any round -- so something else creates and
// attaches it directly, bypassing all four seams tried so far. Round 4 found this factory fires
// twice per video, back to back -- allowingReuse:YES for the stable primary instance and
// allowingReuse:NO for a fresh instance every time. Round 5 found createDescriptionDetailsView-
// ControllerAllowingReuse:1 firing unconditionally right after and feeding the real content.
// Round 6 skipped both outright and the two instances collapsed into one, with content still
// loading into it via some other fallback -- blocking creation is a losing game of whack-a-mole,
// so these are back to plain probes; the actual fix moved to loadWithModel: above, which can't
// be routed around the same way. Left in place for visibility into which path fires.
- (void)createWatchNextResultsViewControllerAllowingReuse:(BOOL)allowingReuse {
    brambleProbe(@"createWatchNextResultsViewControllerAllowingReuse: %d", allowingReuse);
    %orig;
}

- (void)createDescriptionDetailsViewControllerAllowingReuse:(BOOL)allowingReuse {
    brambleProbe(@"createDescriptionDetailsViewControllerAllowingReuse: %d", allowingReuse);
    %orig;
}

- (void)createTeaserCarouselViewControllerAllowingReuse:(BOOL)allowingReuse {
    brambleProbe(@"createTeaserCarouselViewControllerAllowingReuse: %d", allowingReuse);
    %orig;
}

// Requested: trace which controller actually handles a tap on a right-column video card, as an
// independent check on the loadWithModel: hypothesis above -- fromView's ownership should tell
// us whether taps really route through the instance we've been tracking.
- (BOOL)handleCommand:(id)command fromView:(id)fromView entry:(id)entry firstResponder:(id)firstResponder {
    brambleProbe(@"handleCommand fromView=%@ (%p) command=%@", NSStringFromClass([fromView class]), fromView, NSStringFromClass([command class]));
    return %orig;
}

%end

// Round 10: the two-column watch page (right column = suggestions + duplicate description
// pane) is gated by these isWide selectors -- divideContentBetweenWatchNextAndDescription-
// Details_compact vs _regular switches on them. Forcing NO renders the compact single-column
// layout in landscape too: no column exists, content sits below the video like portrait.
// On iPhone these are already NO, so the hooks are no-ops there.
static inline BOOL brambleForceCompactWatchLayout(void) {
    return bramblePref(kBrambleHideSuggested);
}

%hook YTWatchViewController

- (BOOL)isWideLayoutForWatchView:(id)view {
    return brambleForceCompactWatchLayout() ? NO : %orig;
}

%end

%hook YTWatchLayerViewController

- (BOOL)isWideWatchLayout {
    return brambleForceCompactWatchLayout() ? NO : %orig;
}

%end

%hook YTSectionListDrawerView

- (BOOL)isWideMode {
    return brambleForceCompactWatchLayout() ? NO : %orig;
}

%end

%hook YTSectionListDrawerViewController

- (BOOL)isWideModeWithWidth:(CGFloat)width {
    return brambleForceCompactWatchLayout() ? NO : %orig;
}

%end

// Suggested / related videos. Four seams, because the panel is driven from four places and
// suppressing only one leaves it reachable from another.
//
// These force the visible state to NO via %orig(NO) rather than no-opping the setter. A
// no-op leaves the controller believing it showed the panel, which desynchronises its state
// machine; passing NO keeps the app's own bookkeeping correct.
//
// Note uYouEnhanced hooks YTFullScreenEngagementOverlayView with a capital S. No such class
// exists in 21.32.4 -- it is YTFullscreenEngagementOverlayView -- so that hook binds to
// nothing on this version. Names below are read off this binary.
%hook YTFullscreenEngagementOverlayController

- (void)setRelatedVideosVisible:(BOOL)visible {
    %orig(bramblePref(kBrambleHideSuggested) ? NO : visible);
}

// relatedVideosPeekingEnabled is deliberately left alone. Forcing it NO makes the fullscreen
// layout drop the bottom band it reserves for the peek strip, and the seek bar then sits on
// the home indicator. The strip still never appears: setRelatedVideosView: below keeps it
// uninstalled and setRelatedVideosVisible: is forced NO.

%end

%hook YTFullscreenEngagementOverlayView

// Never install the panel's view; relatedVideosView then stays nil on its own, without
// hooking the getter to lie about an ivar that was actually set.
- (void)setRelatedVideosView:(id)view {
    if (bramblePref(kBrambleHideSuggested)) return;
    %orig;
}

%end

%hook YTRelatedVideosViewController

- (void)setRelatedViewVisible:(BOOL)visible {
    %orig(bramblePref(kBrambleHideSuggested) ? NO : visible);
}

%end

%hook YTWatchStateController

- (void)setRelatedVideosVisible:(BOOL)visible {
    %orig(bramblePref(kBrambleHideSuggested) ? NO : visible);
}

%end

// The related videos YouTube shows as a video finishes are a separate path again.
%hook YTMainAppVideoPlayerOverlayViewController

- (void)updateRelatedVideos {
    if (bramblePref(kBrambleHideSuggested)) return;
    %orig;
}

%end

// The playlist "Next" mini-bar: the floating pill above the tab bar that appears whenever a
// playlist or a queue is active. YTPlaylistMiniBarViewController owns it and
// -[YTPlaylistMiniBarView updateWithTitle:subtitle:queuePositionText:
// subtitleAccessibilityLabel:nextLabel:icon:...] is what supplies the "Next" text.
//
// Skipping the show calls rather than forcing -[YTPlaylistMiniBarViewController
// setMiniBarVisible:] to NO: that property reads as a plain synthesised setter
// (TB,N,GisMiniBarVisible,V_miniBarVisible), so writing NO may only move an ivar nobody
// re-reads. Never showing the bar keeps -[YTWatchViewController isPlaylistMiniBarVisible]
// truthful on its own.
//
// Both entry points are covered for the same reason the suggested-videos hooks cover five --
// suppressing one seam leaves the surface reachable from another.
%hook YTWatchViewController

- (void)showPlaylistMiniBar {
    if (bramblePref(kBrambleHidePlaylistNext)) return;
    %orig;
}

- (void)showPlaylistMiniBarIfNeeded {
    if (bramblePref(kBrambleHidePlaylistNext)) return;
    %orig;
}

%end

// Opening a playlist also slides the queue up as an engagement panel sheet -- a separate
// surface from the mini-bar above, confirmed by flipping the toggle off on device: the
// mini-bar came back and the sheet was unaffected either way.
//
// Blocked at the container's open call rather than at the show *command*: the command
// carries its identifier as a nested YTIEngagementPanelIdentifier protobuf, while the panel
// view controller exposes the resolved string directly. Comparing the string needs no
// knowledge of the message layout.
//
// Not -[YTPlaylistPanelController shouldShowPlaylist], the other obvious lever: that
// controller also owns the queue (setActiveVideo:, updateLocalPlaybackSequence), so telling
// it the playlist should not show risks taking playback with it. This hook is presentation
// only.
%hook YTEngagementPanelContainerViewController

- (void)openEngagementPanelNavigationController:(id)navigationController
                                       animated:(BOOL)animated
                        shouldRetainVideoHeight:(BOOL)shouldRetainVideoHeight
                                    showCommand:(id)showCommand
                               isDraggingToOpen:(BOOL)isDraggingToOpen {
    // panelIdentifier is a resolved NSString on the panel view controllers, but other panel
    // types answer the same selector with a YTIEngagementPanelIdentifier protobuf. Sending
    // isEqualToString: to one of those aborts the app, which is exactly what happened here --
    // the playlist panel returns a string, so this only surfaced when some other panel opened.
    // respondsToSelector: is not enough when two unrelated classes share a selector name.
    NSString *identifier = nil;
    if ([navigationController respondsToSelector:@selector(topEngagementPanelViewController)]) {
        id panel = [navigationController topEngagementPanelViewController];
        if ([panel respondsToSelector:@selector(panelIdentifier)]) {
            id value = [panel panelIdentifier];
            if ([value isKindOfClass:NSString.class]) identifier = value;
        }
    }
    brambleProbe(@"engagement panel open: %@", identifier ?: @"(unresolved)");
    if (bramblePref(kBrambleHidePlaylistNext) && [identifier isEqualToString:BRAMBLE_PLAYLIST_PANEL_ID]) return;
    %orig;
}

%end

// Loop button on the player controls.
//
// The button is added as a subview of YTMainAppControlsOverlayView, which is the view YouTube
// itself fades in and out when you tap the video. Visibility therefore needs no hook at all --
// the button inherits it. Anything parented to the player view instead would have to
// replicate that fade, and would linger on screen after a tap.
//
// State is read back from -[YTMainAppVideoPlayerOverlayViewController isSingleLoopOn] rather
// than tracked locally, so the button still reflects reality when loop is changed from
// YouTube's own overflow menu.
// Logos emits only a forward @class for a hooked class, so messaging self inside the hook
// needs a real declaration. Declared here rather than imported: YouTubeHeader carries no
// header for this view, and only playbackRouteButton is needed off it.
@interface YTMainAppControlsOverlayView : UIView
- (UIView *)playbackRouteButton;
- (UIView *)closedCaptionsOrSubtitlesButton;
- (UIView *)overflowButton;
- (UIView *)autonavSwitch;
- (CGFloat)topButtonPadding;
- (UIButton *)brambleLoopButton;
- (id)brambleOverlayController;
- (id)brambleAutonavController;
- (CGFloat)brambleTopButtonPitchFrom:(UIView *)anchor;
- (void)brambleToggleLoop;
@end

@interface NSObject (BrambleLoop)
- (void)setLoopMode:(long long)mode;
- (BOOL)isSingleLoopOn;
- (void)addAutoplayLoopModeObserver:(id)observer;
@end

static char kBrambleLoopButtonKey;
static char kBrambleControlsVisibleKey;

%hook YTMainAppControlsOverlayView

%new
- (UIButton *)brambleLoopButton {
    UIButton *button = objc_getAssociatedObject(self, &kBrambleLoopButtonKey);
    if (button) return button;
    button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = UIColor.whiteColor;
    // Starts hidden. The controls overlay exists before the player does, so anything visible by
    // default shows up over the black canvas while the video is still loading.
    button.alpha = 0.0;
    button.accessibilityLabel = @"Loop video";
    [button setImage:[UIImage systemImageNamed:@"repeat"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(brambleToggleLoop) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(self, &kBrambleLoopButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

// The overlay view is built with -initWithDelegate: and has no public getter for it, so the
// controller is looked for three ways: the _delegate ivar by KVC (the same route the settings
// section uses for _settingsViewControllerDelegate), then the documented eventsDelegate, then
// the responder chain. Whichever answers setLoopMode: wins. Three cheap lookups in one build
// beat one guess per build-sign-install cycle.
%new
- (id)brambleOverlayController {
    @try {
        id delegate = [self valueForKey:@"delegate"];
        if ([delegate respondsToSelector:@selector(setLoopMode:)]) return delegate;
    } @catch (__unused NSException *e) { }

    if ([self respondsToSelector:@selector(eventsDelegate)]) {
        id events = [self performSelector:@selector(eventsDelegate)];
        if ([events respondsToSelector:@selector(setLoopMode:)]) return events;
    }

    for (UIResponder *r = self.nextResponder; r != nil; r = r.nextResponder) {
        if ([r respondsToSelector:@selector(setLoopMode:)]) return r;
    }
    return nil;
}

// The autonav controller hangs off the overlay controller as _autonavController, with no
// public getter -- reached by KVC, then by a responder-chain scan for the one class that
// answers addAutoplayLoopModeObserver:.
%new
- (id)brambleAutonavController {
    id controller = [self brambleOverlayController];
    @try {
        id autonav = [controller valueForKey:@"autonavController"];
        if ([autonav respondsToSelector:@selector(setLoopMode:)]) return autonav;
    } @catch (__unused NSException *e) { }

    for (UIResponder *r = self.nextResponder; r != nil; r = r.nextResponder) {
        if ([r respondsToSelector:@selector(addAutoplayLoopModeObserver:)]) return r;
    }
    return nil;
}

// Distance between adjacent top-right buttons, taken from YouTube's own layout. Captions is
// the neighbour when it exists; it is not always present, so the overflow (settings) button --
// two slots along, hence the halving -- is the fallback, and topButtonPadding the last resort.
%new
- (CGFloat)brambleTopButtonPitchFrom:(UIView *)anchor {
    CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:self];

    UIView *captions = [self respondsToSelector:@selector(closedCaptionsOrSubtitlesButton)]
        ? [self closedCaptionsOrSubtitlesButton] : nil;
    if ([captions isKindOfClass:UIView.class] && captions.superview != nil && !CGRectIsEmpty(captions.bounds)) {
        CGRect f = [captions convertRect:captions.bounds toView:self];
        CGFloat pitch = CGRectGetMidX(f) - CGRectGetMidX(anchorFrame);
        if (pitch > 1.0) return pitch;
    }

    UIView *overflow = [self respondsToSelector:@selector(overflowButton)] ? [self overflowButton] : nil;
    if ([overflow isKindOfClass:UIView.class] && overflow.superview != nil && !CGRectIsEmpty(overflow.bounds)) {
        CGRect f = [overflow convertRect:overflow.bounds toView:self];
        CGFloat pitch = (CGRectGetMidX(f) - CGRectGetMidX(anchorFrame)) / 2.0;
        if (pitch > 1.0) return pitch;
    }

    CGFloat padding = [self respondsToSelector:@selector(topButtonPadding)] ? [self topButtonPadding] : 8.0;
    return CGRectGetWidth(anchorFrame) + padding;
}

%new
- (void)brambleToggleLoop {
    BOOL on = !brambleLoopActive();

    // -[YTAutoplayAutonavController setLoopMode:] is what actually loops. Three other seams
    // were tried and none of them work:
    //   setLoopMode: on YTMainAppVideoPlayerOverlayViewController -- flips isSingleLoopOn, so
    //     the button lit up, but playback never repeated. UI state only.
    //   YTLoopingPlaybackController -- the A/B chapter looper, not video loop.
    //   YTDidToggleSingleVideoPlaybackLoopResponderEvent -- crashed. These events walk
    //     YouTube's own YTResponder chain, and the controls overlay view is a plain UIView, so
    //     dispatch reached a UIResponder that does not implement the handler.
    // YTKillerPlus's dylib references YTAutoplayAutonavController and an _autonavController
    // ivar alongside its own loop button, which is what pointed here.
    id autonav = [self brambleAutonavController];
    if (![autonav respondsToSelector:@selector(setLoopMode:)]) {
        brambleProbe(@"loop: no autonav controller");
        return;
    }
    id configured = [[NSUserDefaults standardUserDefaults] objectForKey:BRAMBLE_LOOP_MODE_KEY];
    long long onValue = configured ? [configured longLongValue] : BRAMBLE_LOOP_MODE_DEFAULT;
    [autonav setLoopMode:on ? onValue : 0];
    brambleProbe(@"loop: %@ setLoopMode:%lld", NSStringFromClass([autonav class]), on ? onValue : 0);

    [[NSUserDefaults standardUserDefaults] setBool:on forKey:BRAMBLE_LOOP_ACTIVE_KEY];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;
    if (!bramblePref(kBrambleLoopButton)) return;

    // Parented to the overlay itself, and visibility driven by the setTopOverlayVisible: hook
    // below rather than by inheritance. Parenting to the cast button's own superview looked
    // tidier and failed twice over: that wrapper is sized tightly around the cast button, so a
    // sibling placed to its left rendered (nothing clips) but sat outside the parent's bounds
    // and so was never hit-tested -- taps did nothing -- and YouTube fades the button inside
    // the wrapper rather than the wrapper itself, so it never hid either. The probe is what
    // showed this: "parented to UIView" appeared, "loop tap ->" never did.
    UIView *anchor = [self respondsToSelector:@selector(playbackRouteButton)] ? [self playbackRouteButton] : nil;
    if (![anchor isKindOfClass:UIView.class]) anchor = nil;

    UIButton *button = [self brambleLoopButton];
    if (button.superview != self) [self addSubview:button];

    // Skip repositioning while the controls are hidden or mid-fade-out. The autonavSwitch
    // visibility check below reads .alpha, a model-layer value UIKit updates to the animation's
    // *target* the instant it's set -- during a fade-out that means it already reads 0 while
    // autonavSwitch is still visibly on screen animating toward it. Recomputing at that moment
    // picks Cast as the anchor and slides the loop button on top of the still-fading
    // autonavSwitch, which is exactly the overlap this guard exists to prevent. There's nothing
    // to reposition for while hidden anyway -- the button already has a correct frame from the
    // last time it was shown, and just needs to fade out from there undisturbed.
    id controlsVisibleObj = objc_getAssociatedObject(self, &kBrambleControlsVisibleKey);
    BOOL controlsVisible = controlsVisibleObj ? [controlsVisibleObj boolValue] : YES;
    if (!controlsVisible) return;

    // Anchored to the cast button: it is the one top-right control always built, unlike the
    // captions and autoplay buttons which come and go with the video. Its frame is in the
    // coordinate space of -topControls, the container it actually lives in, so it has to be
    // converted -- reading .frame directly puts the button somewhere off-screen, which is what
    // made the first attempt invisible.
    // ponytail: fixed offset rather than a constraint chain; if a future layout fills this
    // slot the fix is to change the offset, not to add Auto Layout here.
    CGRect frame;
    if (anchor != nil && anchor.superview != nil && !CGRectIsEmpty(anchor.bounds)) {
        // Step left by the pitch YouTube already uses between its own top buttons, measured off
        // two of them, rather than by a made-up gap. Hardcoding width + 8 put the icon ~50pt
        // too close to the cast button while cast/captions/settings sat evenly spaced, and any
        // fixed number would drift again between portrait, landscape and iPad. Always measured
        // off Cast, the one pair that's reliably both present -- see below for why the anchor
        // it's applied to isn't always Cast itself.
        CGFloat pitch = [self brambleTopButtonPitchFrom:anchor];

        // YouTube's own Autoplay toggle (autonavSwitch) sits one slot left of Cast when it's
        // shown -- observed inside a playlist/queue, absent on a plain single-video watch page.
        // Stepping one pitch left of Cast regardless landed the loop button directly on top of
        // it whenever it's visible; treating it as the real neighbour instead avoids the
        // collision.
        UIView *autonavSwitch = [self respondsToSelector:@selector(autonavSwitch)] ? [self autonavSwitch] : nil;
        if ([autonavSwitch isKindOfClass:UIView.class] && autonavSwitch.superview != nil
            && !CGRectIsEmpty(autonavSwitch.bounds) && !autonavSwitch.hidden && autonavSwitch.alpha > 0.01) {
            anchor = autonavSwitch;
        }

        frame = [anchor convertRect:anchor.bounds toView:self];
        frame.origin.x -= pitch;
    } else {
        // No anchor yet -- the top controls are not laid out until the player is ready, and
        // this runs while the watch page is still a black canvas. Parking the button somewhere
        // visible was useful while the placement was unproven and is just an artifact now.
        button.alpha = 0.0;
        return;
    }
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    [self bringSubviewToFront:button];

    // Only touch alpha while the button is actually shown -- the visibility hooks below own
    // the 0 case, and overwriting it here would undo the fade.
    if (button.alpha > 0.0) button.alpha = brambleLoopActive() ? 1.0 : 0.55;
}

// The two calls YouTube makes when the controls fade in and out on a tap. Mirroring them is
// what gives the button native show/hide behaviour; nothing about the view hierarchy does it
// for us, which is what the first three attempts assumed.
// alpha, not hidden: hidden is not animatable, so the button vanished instantly while the
// real controls were still fading. Assigning alpha inside YouTube's own call means it is
// picked up by whatever animation block that call is already running in, and the button fades
// on exactly the same curve.
- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceled {
    // Set before %orig, not after: %orig can trigger a layout pass synchronously, and
    // layoutSubviews' hidden-controls guard needs to see the new state during that same pass,
    // not one pass later.
    objc_setAssociatedObject(self, &kBrambleControlsVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    UIButton *button = objc_getAssociatedObject(self, &kBrambleLoopButtonKey);
    if (button) button.alpha = visible ? (brambleLoopActive() ? 1.0 : 0.55) : 0.0;
}

- (void)setOverlayVisible:(BOOL)visible {
    objc_setAssociatedObject(self, &kBrambleControlsVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    UIButton *button = objc_getAssociatedObject(self, &kBrambleLoopButtonKey);
    if (button) button.alpha = visible ? (brambleLoopActive() ? 1.0 : 0.55) : 0.0;
}

%end

// Shorts removal, in two halves because they are two different surfaces.
//
// The tab: YTIPivotBarRenderer carries the bottom bar's items; the Shorts entry is the one
// whose pivotIdentifier is "FEshorts" (string confirmed present in 21.32.4).
%hook YTPivotBarView

- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    if (bramblePref(kBrambleHideShorts)) {
        NSMutableArray <YTIPivotBarSupportedRenderers *> *items = [renderer itemsArray];
        [items removeObjectsAtIndexes:[items indexesOfObjectsPassingTest:
            ^BOOL(YTIPivotBarSupportedRenderers *item, NSUInteger idx, BOOL *stop) {
                return [[[item pivotBarItemRenderer] pivotIdentifier] isEqualToString:@"FEshorts"];
            }]];
    }
    %orig;
}

%end

// The cells and shelves: returning empty element data makes the renderer draw nothing, which
// is PoomSmart's YTUnShorts approach (as vendored by uYouEnhanced). Matching on the rendered
// description rather than a typed field is what makes it survive layout changes -- and what
// makes it rot when YouTube renames an id, exactly like the ad blocklist above.
// ponytail: -description on every element is not cheap; it only runs when the switch is on.
%hook YTIElementRenderer

- (NSData *)elementData {
    if (bramblePref(kBrambleHideShorts)) {
        NSString *description = [self description];
        for (NSString *identifier in @[
            @"shorts_shelf",
            @"shorts_video_cell",
            @"shorts_grid_shelf_footer",
            @"youtube_shorts_24"
        ])
            if ([description containsString:identifier]) return [NSData data];
        // Shorts that appear in watch history render as compact video cells instead.
        if ([description containsString:@"compact_video.eml"]
            && [description containsString:@"youtube_shorts_"]) return [NSData data];
    }
    return %orig;
}

%end

%hook YTVersionUtils

+ (NSString *)appVersion {
    return bramblePref(kBrambleSpoofVersion) ? BRAMBLE_SPOOFED_VERSION : %orig;
}

%end

%hook YTColdConfig

- (BOOL)shortsConsumptionClientGlobalConfigIosEnableShortsSpeedmasterGesture {
    return bramblePref(kBrambleNoSpeedmasterShorts) ? NO : %orig;
}

%end

%end // end group Core

%ctor {
    os_log_t log = os_log_create("com.bramble.tweak", "load");
    os_log(log, "Bramble loaded, YouTube target version: %{public}s", BRAMBLE_YOUTUBE_VERSION);
    // os_log with a custom subsystem does not reach `devicectl ... --console` or the
    // syslog relay, which made a silently-skipped dylib indistinguishable from a working
    // one. NSLog goes to stderr, which both surface, so the load line is observable.
    NSLog(@"[Bramble] loaded, YouTube target version: %s", BRAMBLE_YOUTUBE_VERSION);
    brambleProbe(@"loaded, target %s", BRAMBLE_YOUTUBE_VERSION);
#ifndef BRAMBLE_INERT
    %init(Core);
    // Not switchable: without it the app cannot play anything on a re-signed build.
    %init(Integrity);
    %init(Diagnostics);
    if (bramblePref(kBrambleBlockAds)) %init(Ads);
    if (bramblePref(kBrambleBackgroundPlayback)) %init(Background);
#endif
}
