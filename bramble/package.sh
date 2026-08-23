#!/bin/bash
# bramble/package.sh
#
# The single script an operator runs to turn a config-supplied input YouTube IPA into a
# verified, correctly-named unsigned IPA. Resolves the input (local path or cached URL
# fetch), rejects a non-stock input, reads the real YouTube version and deployment target
# from it, bootstraps the toolchain if needed, drives `make package`, then hard-fails the
# build if any of the five verification checks (see Task 2 section below) do not pass.
#
# Usage:
#   ./package.sh [--refetch] [--inert] [--bundle-id <id>] [--display-name <name>]
#                [--input <path-or-url>]
#
#   --refetch                bypass the URL input cache, force a clean re-download
#   --inert                  build with hooks compiled out (INERT=1, D-14)
#   --bundle-id <id>         passthrough to `make package BUNDLE_ID=...` (D-15 experiment)
#   --display-name <name>    passthrough to `make package DISPLAY_NAME=...`
#   --input <path-or-url>    override INPUT_IPA_SOURCE for this run only (does not touch
#                            bramble.config) -- used by the synthetic version-bump test
#
# Requires bramble/bramble.config (copy from bramble.config.example and fill in
# INPUT_IPA_SOURCE first).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REFETCH=0
INERT=0
BUNDLE_ID_FLAG=""
DISPLAY_NAME_FLAG=""
INPUT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --refetch) REFETCH=1; shift ;;
    --inert) INERT=1; shift ;;
    --bundle-id) BUNDLE_ID_FLAG="$2"; shift 2 ;;
    --display-name) DISPLAY_NAME_FLAG="$2"; shift 2 ;;
    --input) INPUT_OVERRIDE="$2"; shift 2 ;;
    *) echo "Error: unknown argument '$1'." >&2; exit 2 ;;
  esac
done

# --- Config gate ----------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/bramble.config" ]; then
  echo "Error: $SCRIPT_DIR/bramble.config not found." >&2
  echo "Copy bramble.config.example to bramble.config and fill in INPUT_IPA_SOURCE, then re-run." >&2
  exit 2
fi
source "$SCRIPT_DIR/bramble.config"

EFFECTIVE_INPUT="${INPUT_OVERRIDE:-$INPUT_IPA_SOURCE}"
if [ -z "$EFFECTIVE_INPUT" ]; then
  echo "Error: no input IPA source configured. Set INPUT_IPA_SOURCE in bramble.config, or pass --input <path-or-url>." >&2
  exit 2
fi

# --- Resolve input: local path used directly, URL fetched into a version-keyed cache --
# Never echo the resolved URL/path itself -- it may carry credentials (security_context).
if echo "$EFFECTIVE_INPUT" | grep -qE '^https?://'; then
  CACHE_DIR="$SCRIPT_DIR/${INPUT_CACHE_DIR:-.cache/input}"
  mkdir -p "$CACHE_DIR"
  URL_HASH="$(printf '%s' "$EFFECTIVE_INPUT" | shasum -a 256 | cut -c1-16)"
  CACHE_FILE="$CACHE_DIR/${URL_HASH}.ipa"
  if [ "$REFETCH" = "1" ] || [ ! -f "$CACHE_FILE" ]; then
    echo "Fetching input IPA from configured source (not cached, or --refetch given)..."
    curl -fL "$EFFECTIVE_INPUT" -o "$CACHE_FILE"
  else
    echo "Reusing cached input IPA (pass --refetch to force a clean re-download)."
  fi
  RESOLVED_INPUT="$CACHE_FILE"
else
  RESOLVED_INPUT="$EFFECTIVE_INPUT"
fi

if [ ! -e "$RESOLVED_INPUT" ]; then
  echo "Error: resolved input does not exist on disk." >&2
  exit 2
fi

# --- Unpack into a scratch staging tree -------------------------------------------------
STAGING_DIR="$SCRIPT_DIR/build/staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

if [ -d "$RESOLVED_INPUT" ]; then
  mkdir -p "$STAGING_DIR/Payload"
  cp -a "$RESOLVED_INPUT" "$STAGING_DIR/Payload/"
else
  unzip -qo "$RESOLVED_INPUT" -d "$STAGING_DIR"
fi

APP_MATCHES=("$STAGING_DIR"/Payload/*.app)
if [ ${#APP_MATCHES[@]} -ne 1 ] || [ ! -d "${APP_MATCHES[0]}" ]; then
  echo "Error: expected exactly one Payload/*.app in the input, found ${#APP_MATCHES[@]}." >&2
  exit 2
fi
APPDIR="${APP_MATCHES[0]}"

# --- D-11: reject a non-stock input before any build work starts ----------------------
# Bundle patterns match the actual known YTKillerPlus artifact name (YTKPlus.bundle,
# per PROJECT.md/README.md). A prior '*mod*.bundle' pattern was dropped: it substring-matched
# Google's own stock 'BodoniModaSemibold.bundle' font bundle (real YouTube 21.32.4 input),
# a false positive that would reject every genuinely stock IPA.
FOUND_DYLIBS="$(find "$APPDIR" -name '*.dylib')"
FOUND_BUNDLES="$(find "$APPDIR" \( -iname '*plus*.bundle' -o -iname '*killer*.bundle' \))"
if [ -n "$FOUND_DYLIBS" ] || [ -n "$FOUND_BUNDLES" ]; then
  echo "Error: input is not a stock YouTube.app -- it already carries injected content:" >&2
  [ -n "$FOUND_DYLIBS" ] && echo "$FOUND_DYLIBS" | sed 's/^/  dylib: /' >&2
  [ -n "$FOUND_BUNDLES" ] && echo "$FOUND_BUNDLES" | sed 's/^/  bundle: /' >&2
  echo "Supply an unmodified, decrypted stock YouTube IPA." >&2
  exit 3
fi

# --- Read version + deployment target from the real input; never hardcode (D-03, D-10) -
YOUTUBE_VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APPDIR/Info.plist")"
MIN_OS_VERSION="$(/usr/libexec/PlistBuddy -c "Print MinimumOSVersion" "$APPDIR/Info.plist")"
if [ -z "$YOUTUBE_VERSION" ] || [ -z "$MIN_OS_VERSION" ]; then
  echo "Error: could not read CFBundleVersion / MinimumOSVersion from $APPDIR/Info.plist." >&2
  exit 3
fi
echo "Input resolved: YouTube $YOUTUBE_VERSION, MinimumOSVersion $MIN_OS_VERSION"

# --- Toolchain bootstrap (idempotent; only sourced when incomplete) -------------------
# Sentinel is $THEOS/makefiles/common.mk, not the plan-cited theos-set-variables.sh --
# that file does not exist anywhere in current Theos (confirmed in 01-02-SUMMARY.md);
# using it would force a full re-clone on every invocation.
export THEOS="${THEOS:-$SCRIPT_DIR/.toolchain/theos}"
if [ ! -f "$THEOS/makefiles/common.mk" ]; then
  source "$SCRIPT_DIR/bootstrap-toolchain.sh"
fi

mkdir -p "$THEOS/lib/iphone/rootless"

# --- Build ------------------------------------------------------------------------------
MAKE_ARGS=(package THEOS_PACKAGE_SCHEME=rootless "IPA=$APPDIR" FINALPACKAGE=1
  "YOUTUBE_VERSION=$YOUTUBE_VERSION" "BRAMBLE_VERSION=${BRAMBLE_VERSION:-0.1.0}"
  "MINIMUM_OS_VERSION=$MIN_OS_VERSION" "INERT=$INERT" "IOS_SDK_VERSION=${IOS_SDK_VERSION:-16.5}")
[ -n "$BUNDLE_ID_FLAG" ] && MAKE_ARGS+=("BUNDLE_ID=$BUNDLE_ID_FLAG")
[ -n "$DISPLAY_NAME_FLAG" ] && MAKE_ARGS+=("DISPLAY_NAME=$DISPLAY_NAME_FLAG")

echo "Building: make ${MAKE_ARGS[*]}"
make "${MAKE_ARGS[@]}"

# --- Locate make's own artifact and copy (not move) to a stable, versioned name --------
PACKAGES_MATCHES=("$SCRIPT_DIR"/packages/*.ipa)
if [ ${#PACKAGES_MATCHES[@]} -ne 1 ] || [ ! -f "${PACKAGES_MATCHES[0]}" ]; then
  echo "Error: expected exactly one IPA in bramble/packages/ after make package, found ${#PACKAGES_MATCHES[@]}." >&2
  exit 4
fi
MAKE_OUTPUT_IPA="${PACKAGES_MATCHES[0]}"

# --- Workaround: vendored theos-jailed's ipa.sh always recreates an empty PlugIns/ entry --
# `[[ ! -z appex_files ]]` there tests the literal string "appex_files" (a bash bug -- missing
# the `$`), not the array, so it is always true and unconditionally `mkdir`s $APPEX_PATH
# (default "PlugIns") right after our REMOVE_EXTENSIONS=1 deletes it. theos-jailed is ~3 years
# dormant (research/STACK.md staleness flag); not worth patching the gitignored vendored copy
# since a fresh bootstrap re-fetches the same bug. Strip the resulting empty entry here instead,
# in the script we actually own, before Check 3 (PKG-06) runs.
APP_BUNDLE_NAME="$(basename "$APPDIR")"
# grep -c (not -q) deliberately -- -q exits after the first match, closing the pipe early and
# SIGPIPE-killing unzip; under pipefail that makes the pipeline's status unzip's 141 even though
# grep matched. -c reads all of stdin so unzip always exits cleanly (matches Check 3 below).
PLUGINS_PRECHECK_COUNT="$(unzip -l "$MAKE_OUTPUT_IPA" | grep -cE "PlugIns/|Extensions/" || true)"
if [ "$PLUGINS_PRECHECK_COUNT" -gt 0 ]; then
  echo "Stripping PlugIns/ and Extensions/ from the output IPA..."
  # REMOVE_EXTENSIONS=1 only removes PlugIns/. YouTube also ships
  # Extensions/AppMigrationExtension.appex, which is a second .appex: it consumes another of
  # a free account's three app IDs, and it needs its own provisioning profile, so leaving it
  # makes iOS reject an in-place upgrade with "Info.plist missing at .../PlugIns/...".
  # YTKillerPlus strips both, which is the behaviour being matched here.
  zip -qd "$MAKE_OUTPUT_IPA" "Payload/$APP_BUNDLE_NAME/PlugIns/*" "Payload/$APP_BUNDLE_NAME/PlugIns/" 2>/dev/null || true
  zip -qd "$MAKE_OUTPUT_IPA" "Payload/$APP_BUNDLE_NAME/Extensions/*" "Payload/$APP_BUNDLE_NAME/Extensions/" 2>/dev/null || true
fi

mkdir -p "$SCRIPT_DIR/build"
OUTPUT_SUFFIX=""
[ "$INERT" = "1" ] && OUTPUT_SUFFIX="${OUTPUT_SUFFIX}-inert"
[ -n "$BUNDLE_ID_FLAG" ] && OUTPUT_SUFFIX="${OUTPUT_SUFFIX}-bundletest"
OUTPUT_IPA="$SCRIPT_DIR/build/Bramble-$YOUTUBE_VERSION-${BRAMBLE_VERSION:-0.1.0}${OUTPUT_SUFFIX}.ipa"
cp "$MAKE_OUTPUT_IPA" "$OUTPUT_IPA"
echo "Packaged (unverified): $OUTPUT_IPA"

# --- Verification: five hard-fail checks on the real packaged output (D-09 + D-14) -----
# Never trust the pre-zip staging tree -- unzip the actual produced IPA and inspect that.
fail_check() {
  echo "VERIFICATION FAILED: $1" >&2
  rm -f "$OUTPUT_IPA"
  exit 5
}

SCRATCH_DIR="$SCRIPT_DIR/build/verify-scratch"
rm -rf "$SCRATCH_DIR"
mkdir -p "$SCRATCH_DIR"
unzip -qo "$OUTPUT_IPA" -d "$SCRATCH_DIR"

VERIFY_APP_MATCHES=("$SCRATCH_DIR"/Payload/*.app)
[ ${#VERIFY_APP_MATCHES[@]} -eq 1 ] && [ -d "${VERIFY_APP_MATCHES[0]}" ] \
  || fail_check "expected exactly one Payload/*.app in the packaged output IPA"
VERIFY_APPDIR="${VERIFY_APP_MATCHES[0]}"

DYLIB="$VERIFY_APPDIR/Frameworks/Bramble.dylib"
[ -f "$DYLIB" ] || fail_check "Bramble.dylib not found at $DYLIB in the packaged output"

HOST_BINARY_NAME="$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$VERIFY_APPDIR/Info.plist")"
HOST_BINARY="$VERIFY_APPDIR/$HOST_BINARY_NAME"
[ -f "$HOST_BINARY" ] || fail_check "host executable $HOST_BINARY_NAME not found in the packaged output"

# Check 1: otool -L on the dylib -- no jailbreak-only load paths.
BAD_PATH_LINE="$(otool -L "$DYLIB" | grep -E '/var/jb|/Library/MobileSubstrate' || true)"
[ -z "$BAD_PATH_LINE" ] \
  || fail_check "Check 1 (otool -L): forbidden path in Bramble.dylib load commands: $BAD_PATH_LINE"

# Check 2: otool -l on the host binary -- LC_RPATH @executable_path/Frameworks AND a
# LC_LOAD_WEAK_DYLIB (not a plain, non-weak load command) naming @rpath/Bramble.dylib.
# Checked per load-command block (awk record per "Load command"), not a flat substring
# match anywhere in the output -- a non-weak load of the same path must NOT satisfy this.
HOST_LOAD_COMMANDS="$(otool -l "$HOST_BINARY")"
RPATH_OK="$(echo "$HOST_LOAD_COMMANDS" | awk 'BEGIN{RS="Load command "} /cmd LC_RPATH/ && /path @executable_path\/Frameworks/ {f=1} END{print f+0}')"
[ "$RPATH_OK" = "1" ] \
  || fail_check "Check 2 (otool -l): LC_RPATH @executable_path/Frameworks not found on host binary"
WEAK_DYLIB_OK="$(echo "$HOST_LOAD_COMMANDS" | awk 'BEGIN{RS="Load command "} /cmd LC_LOAD_WEAK_DYLIB/ && /name @rpath\/Bramble.dylib/ {f=1} END{print f+0}')"
[ "$WEAK_DYLIB_OK" = "1" ] \
  || fail_check "Check 2 (otool -l): LC_LOAD_WEAK_DYLIB @rpath/Bramble.dylib not found (a non-weak load command of the same path does not satisfy this check)"

# Check 3: PlugIns/ absent from the final packaged IPA (PKG-06 / REMOVE_EXTENSIONS=1).
PLUGINS_COUNT="$(unzip -l "$OUTPUT_IPA" | grep -c 'PlugIns/' || true)"
[ "$PLUGINS_COUNT" -eq 0 ] \
  || fail_check "Check 3 (unzip -l): $PLUGINS_COUNT PlugIns/ entries found in the output IPA"

# Check 4: MinimumOSVersion was actually read from the input, never assumed (D-10).
[ -n "$MIN_OS_VERSION" ] \
  || fail_check "Check 4: MIN_OS_VERSION is empty -- deployment target was never read from the input"

# Check 5 (D-14): hook-registration symbol count on the compiled dylib itself, branching on
# the same INERT value already threaded through the make package call above. This proves
# what the compiler actually emitted, not just the #ifndef BRAMBLE_INERT guard's placement
# in source (which Plan 01-01 Task 2 already checked and cannot prove on its own).
#
# Which symbol registers a hook depends on the Logos generator: MobileSubstrate emits
# MSHookMessageEx, the internal generator (what the Makefile selects) emits
# method_setImplementation. Matching both keeps this check honest across that choice instead
# of silently passing zero hooks the day the generator changes.
HOOK_SYMBOL_COUNT="$(nm -m "$DYLIB" | grep -cE 'MSHookMessageEx|_method_setImplementation' || true)"
if [ "$INERT" = "1" ]; then
  [ "$HOOK_SYMBOL_COUNT" -eq 0 ] \
    || fail_check "Check 5 (nm -m): INERT=1 build still contains $HOOK_SYMBOL_COUNT hook-registration reference(s) -- the BRAMBLE_INERT guard did not exclude hook registration from the compiled dylib"
else
  [ "$HOOK_SYMBOL_COUNT" -gt 0 ] \
    || fail_check "Check 5 (nm -m): live (non-inert) build contains 0 hook-registration references -- the guard silently swallowed every hook, or the build is otherwise broken"
fi

rm -rf "$SCRATCH_DIR"

# --- All five checks passed: emit the build manifest. Never write INPUT_IPA_SOURCE or any
# URL/path derived from it into this file or into any echo/print statement anywhere in this
# script -- it may carry embedded credentials (security_context, T-01-07).
MANIFEST="$SCRIPT_DIR/build/build-manifest-$YOUTUBE_VERSION-${BRAMBLE_VERSION:-0.1.0}.txt"
{
  echo "youtube_version: $YOUTUBE_VERSION"
  echo "bramble_version: ${BRAMBLE_VERSION:-0.1.0}"
  echo "theos_sha: ${THEOS_SHA:-}"
  echo "theos_jailed_sha: ${THEOS_JAILED_SHA:-}"
  echo "youtubeheader_sha: ${YOUTUBEHEADER_SHA:-}"
  echo "build_timestamp_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MANIFEST"

echo "Verified and packaged: $OUTPUT_IPA"
echo "Manifest: $MANIFEST"
