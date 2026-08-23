# Bramble

Ad-free YouTube on `com.google.ios.youtube`, packaged from an operator-supplied decrypted stock
YouTube IPA and rebuildable against the next YouTube release with `./package.sh`. This doc covers
setup, what to do before you install, signing, what will not work, verifying an install, and
troubleshooting. It does not repeat the packaging internals — read `package.sh` for those.

## Setup

1. Copy `bramble.config.example` to `bramble.config` (gitignored — never committed).
2. Fill in `INPUT_IPA_SOURCE` with a local path or `https://` URL to a **decrypted, unmodified
   stock YouTube IPA**.
   - `work/Payload/YouTube.app` in this repo is **not** usable input. It already carries an
     injected `YTKPlus.dylib`/`YTKPlus.bundle` from an unrelated teardown and `package.sh` will
     reject it by name (D-11 stock-input check, exit code 3). Supply a clean IPA instead.
3. Run `./package.sh`. On a bare machine it also bootstraps the whole toolchain (Theos, the iOS
   SDK, theos-jailed, YouTubeHeader) into `bramble/.toolchain/`, which takes a few minutes the
   first time and is a no-op afterward.
4. The verified, unsigned output IPA lands at `bramble/build/Bramble-<youtube-version>-<bramble-version>.ipa`,
   alongside a `build-manifest-*.txt` recording the versions and pinned toolchain SHAs used.

## Before you install

- **Delete the App Store YouTube first.** Installing a re-signed build over it fails with an
  entitlement-mismatch error, because the sideloaded build's team prefix differs from Google's.
  There is no side-by-side install — keeping `com.google.ios.youtube` as the bundle ID is what
  makes sign-in work, and it is also what forces this collision.
- **Its container is wiped as a consequence.** Downloads, watch history cached locally, and
  settings stored by the App Store YouTube app are gone once it is deleted. There is no migration
  path.
- **Disable automatic app updates** in Settings, or the App Store will keep trying to reclaim
  `com.google.ios.youtube` and reinstall over your sideloaded build.

## Signing

The documented signer is **AltStore** or **SideStore**, not bare Sideloadly. Both automate the
7-day free-cert provisioning-profile refresh; Sideloadly does not, so a build installed with it
silently stops launching a week later until you manually re-sign.

**Always re-sign with the same Apple ID** on every refresh. The keychain access group is prefixed
by the signing team ID, so switching Apple IDs changes that prefix, forces a fresh Google sign-in,
and may orphan a previously-granted OAuth session. Treat the signing Apple ID as fixed for the
life of the install, not something to rotate casually.

## What will not work

A free-account re-sign strips entitlements that require a paid developer account:

- **Push notifications are dead.** `aps-environment` is stripped, so nothing arrives even though
  the app may still show a "notifications enabled" toggle.
- **youtube.com universal links don't open in-app.** Associated domains are stripped too; a
  youtube.com link opens in Safari (or does nothing) instead of launching the app directly.

Both are expected consequences of a free-cert re-sign, not a Bramble bug — do not spend time
debugging them.

## Verifying the install

Run the three-part sign-in test order in sequence. Each step isolates exactly one failure cause:

1. **Inert build** (`./package.sh --inert`) → install → sign in. A failure here means
   **packaging** is broken (nothing hook-related is even compiled in).
2. **Live build** (`./package.sh`) → install → sign in. A failure here that did not occur at step 1
   means **a hook** broke something on the auth path.
3. **Changed-bundle-ID build** (`./package.sh --bundle-id <id> --display-name <name>`) → install →
   sign in. Answers whether side-by-side install with the App Store YouTube is actually possible —
   a positive result here reopens that question project-wide.

For each install, open **Console.app** on a Mac with the device connected over USB, filter on
subsystem `com.bramble.tweak`, and launch the app. The `%ctor` load line appearing is what
distinguishes "the dylib didn't load" (packaging problem) from "it loaded but a hook silently
missed" (a Phase 2 problem, not a Phase 1 one) — its **absence** is the diagnostic.

## Troubleshooting

- **Substrate path breaks / dylib won't inject:** the vendored `CydiaSubstrate.framework` at
  `bramble/vendor/` is downloaded once and committed specifically to avoid depending on
  `apt.saurik.com` at build time, but if that path ever needs bypassing entirely, Logos supports
  an `internal` code generator that needs no Substrate framework at all. Set
  `Bramble_LOGOS_DEFAULT_GENERATOR = internal` in `bramble/Makefile` (it is currently unset, which
  defaults to `MobileSubstrate`). This is documented here as an escape hatch, not a default — it
  is MEDIUM-confidence and untested against this project's hooks (`research/STACK.md`), so treat
  it as a last resort if the Substrate path breaks, not a first move.
- **"Maximum App ID limit reached" from the signer:** free accounts get 10 App IDs per rolling
  7-day window, and each `.appex` extension consumes one. `package.sh` already strips `PlugIns/`
  (`REMOVE_EXTENSIONS = 1`) so a normal install costs one App ID; running all three sign-in-test
  variants in quick succession still costs three. Space out changed-bundle-ID experiments if the
  quota is tight.
- **Sign-in state lost after a routine refresh:** almost always means the re-sign used a different
  Apple ID than the previous install — see Signing above.
