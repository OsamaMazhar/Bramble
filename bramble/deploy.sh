#!/bin/bash
# deploy.sh -- one command from a decrypted YouTube IPA to a running tweaked app.
#
#   ./deploy.sh                 package, sign, install, launch
#   ./deploy.sh --no-install    package and sign only (hands you a signed .app to sideload)
#   ./deploy.sh --inert         same, with hooks compiled out (isolates tweak vs packaging)
#
# Retargeting to a newer YouTube release is one line in bramble.config -- point
# INPUT_IPA_SOURCE at the new decrypted IPA. Nothing here or in Tweak.x hardcodes a YouTube
# version: package.sh reads CFBundleVersion out of the input's Info.plist and stamps the
# build from it.
#
# Signing identity, provisioning profile and device are resolved automatically when not set
# in bramble.config, so a new machine or a renewed certificate needs no edits.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INSTALL=1
INERT=0
PACKAGE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --inert) INERT=1; PACKAGE_ARGS+=("$arg") ;;
    *) PACKAGE_ARGS+=("$arg") ;;
  esac
done

[ -f bramble.config ] || { echo "Error: bramble.config not found. Copy bramble.config.example." >&2; exit 1; }
# shellcheck disable=SC1091
source ./bramble.config

# --- 1. Build the tweaked IPA -----------------------------------------------------------
if [ ${#PACKAGE_ARGS[@]} -gt 0 ]; then ./package.sh "${PACKAGE_ARGS[@]}"; else ./package.sh; fi

OUTPUT_SUFFIX=""
[ "$INERT" = "1" ] && OUTPUT_SUFFIX="-inert"
IPA_MATCHES=("$SCRIPT_DIR"/build/Bramble-*"${OUTPUT_SUFFIX}".ipa)
IPA=""
for candidate in "${IPA_MATCHES[@]}"; do
  case "$candidate" in
    *-inert.ipa|*-bundletest.ipa) [ -n "$OUTPUT_SUFFIX" ] && IPA="$candidate" ;;
    *) [ -z "$OUTPUT_SUFFIX" ] && IPA="$candidate" ;;
  esac
done
[ -f "$IPA" ] || { echo "Error: no packaged IPA found in build/." >&2; exit 1; }
echo "Signing: $IPA"

# --- 2. Resolve signing material ---------------------------------------------------------
# A team-prefixed identity is required; application-identifier must be <team>.<bundleid> and
# there is no way around that. See HANDOFF.md section 5 for why this matters for playback.
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')"
fi
[ -n "$SIGN_IDENTITY" ] || { echo "Error: no Apple Development identity found; set SIGN_IDENTITY." >&2; exit 1; }

if [ -z "${DEVICE_ID:-}" ] && [ "$INSTALL" = "1" ]; then
  echo "Error: DEVICE_ID not set in bramble.config. List devices with:" >&2
  echo "  xcrun devicectl list devices" >&2
  exit 1
fi

# Pick a profile that covers this device. A wildcard (<team>.*) profile is what allows
# signing com.google.ios.youtube without registering that bundle ID to the team.
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ -z "${PROVISIONING_PROFILE:-}" ]; then
  if [ -n "${DEVICE_UDID:-}" ]; then
    for f in "$PROFILE_DIR"/*.mobileprovision; do
      P="$(security cms -D -i "$f" 2>/dev/null)" || continue
      echo "$P" | grep -q "$DEVICE_UDID" || continue
      # Must be a wildcard *app-ID* profile. Grepping the whole plist for a "*" string
      # matches unrelated fields and silently picks a single-app profile, which then fails
      # at install with 0xe8008015 -- read the entitlement itself.
      echo "$P" | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null \
        | grep -q '\.\*$' || continue
      PROVISIONING_PROFILE="$f"; break
    done
  fi
fi
[ -n "${PROVISIONING_PROFILE:-}" ] || { echo "Error: no wildcard profile found for this device; set PROVISIONING_PROFILE." >&2; exit 1; }

TEAM_ID="$(security cms -D -i "$PROVISIONING_PROFILE" 2>/dev/null \
  | plutil -extract Entitlements.com\\.apple\\.developer\\.team-identifier raw - 2>/dev/null || true)"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(security cms -D -i "$PROVISIONING_PROFILE" 2>/dev/null \
    | plutil -extract ApplicationIdentifierPrefix.0 raw - 2>/dev/null)"
fi
[ -n "$TEAM_ID" ] || { echo "Error: could not read team ID from the provisioning profile." >&2; exit 1; }
echo "Identity: $SIGN_IDENTITY (team $TEAM_ID)"

# --- 3. Stage and sign -------------------------------------------------------------------
STAGE="$SCRIPT_DIR/build/signed"
rm -rf "$STAGE" && mkdir -p "$STAGE"
unzip -qo "$IPA" -d "$STAGE"
APP="$(find "$STAGE/Payload" -maxdepth 1 -name '*.app' | head -1)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")"

rm -rf "$APP/_CodeSignature"
cp "$PROVISIONING_PROFILE" "$APP/embedded.mobileprovision"

# Google's own entitlements cannot be reused: application-identifier and keychain groups are
# prefixed with Google's team. Keychain groups are re-prefixed with ours, which any profile
# grants. App groups are deliberately omitted -- group.com.google.YouTube is registered to
# Google and cannot be claimed, and requesting it makes the install fail with 0xe8008015.
ENTITLEMENTS="$SCRIPT_DIR/build/entitlements.plist"
cat > "$ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>${TEAM_ID}.${BUNDLE_ID}</string>
	<key>com.apple.developer.team-identifier</key>
	<string>${TEAM_ID}</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>${TEAM_ID}.${BUNDLE_ID}</string>
		<string>${TEAM_ID}.com.google.common.SSO</string>
		<string>${TEAM_ID}.com.google.common.folsom</string>
	</array>
</dict>
</plist>
EOF

# Nested code must be signed before the bundle that contains it.
for f in "$APP/Frameworks/"*; do
  [ -e "$f" ] || continue
  codesign --force --sign "$SIGN_IDENTITY" "$f" >/dev/null
done
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"
echo "Signed and verified: $APP"

[ "$INSTALL" = "1" ] || { echo "Done (--no-install)."; exit 0; }

# --- 4. Install --------------------------------------------------------------------------
# An in-place upgrade fails with CoreDeviceError 3002 whenever the installed bundle carries
# PlugIns/ (e.g. App Store YouTube). Try it first because it preserves the container -- and
# therefore the sign-in session and every Bramble toggle -- then fall back to a clean install.
echo "Installing to $DEVICE_ID..."
INPLACE_LOG="$(mktemp)"
if xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >"$INPLACE_LOG" 2>&1 && grep -q "App installed" "$INPLACE_LOG"; then
  echo "Installed in place (settings and sign-in preserved)."
  rm -f "$INPLACE_LOG"
else
  # Falling back costs the sign-in session and every Bramble toggle, so print why rather than
  # swallowing it. A stale PlugIns/*.appex left by a half-finished install reads as
  # CoreDeviceError 3002 here and keeps failing until the app is removed once.
  echo "In-place install failed; uninstalling first (this clears settings and sign-in). Reason:"
  grep -iE "error|Unable to Install|NSLocalizedRecoverySuggestion|MIInstallerErrorDomain" "$INPLACE_LOG" | head -6 | sed 's/^/    /'
  rm -f "$INPLACE_LOG"
  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | grep -E "App installed|ERROR" || {
    echo "Error: install failed." >&2; exit 1; }
fi

# devicectl refuses to launch onto a locked device, and the failure reads like the tweak not
# loading. Surface it plainly instead.
if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1 | grep -q "Launched"; then
  echo "Note: launch failed -- if the device is locked, unlock it and open YouTube manually."
fi
echo "Done."
