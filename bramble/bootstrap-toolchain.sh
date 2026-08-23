#!/bin/bash
# bramble/bootstrap-toolchain.sh
#
# Turns a bare machine (no $THEOS, no ~/theos, stock macOS GNU make) into one with a
# repo-local, pinned Theos + theos-jailed + YouTubeHeader toolchain under
# bramble/.toolchain/theos. Every clone is pinned to a commit SHA from bramble.config
# (D-07) so a compromised upstream `master` cannot silently substitute code.
#
# Intended usage: `source bramble/bootstrap-toolchain.sh` (not `./bootstrap-toolchain.sh`)
# so that $THEOS and any PATH changes this script makes (GNU make's gnubin) are inherited
# by the caller's shell -- package.sh relies on this for its own `make package` call.
#
# Idempotent: every step checks for its own prior work before cloning/downloading again.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/bramble.config" ]; then
  echo "Error: $SCRIPT_DIR/bramble.config not found." >&2
  echo "Copy bramble.config.example to bramble.config and fill in INPUT_IPA_SOURCE, then re-run." >&2
  exit 1
fi
source "$SCRIPT_DIR/bramble.config"

export THEOS="$SCRIPT_DIR/.toolchain/theos"

# --- Step 1: GNU make ---------------------------------------------------------------
# macOS ships GNU Make 3.81; Theos's makefiles need 4+.
MAKE_VERSION_LINE="$(make --version 2>/dev/null | head -1)"
MAKE_MAJOR="$(echo "$MAKE_VERSION_LINE" | grep -oE '[0-9]+' | head -1)"
if [ -z "$MAKE_MAJOR" ] || [ "$MAKE_MAJOR" -lt 4 ]; then
  echo "GNU Make 4+ not found (found: ${MAKE_VERSION_LINE:-none}) -- installing via Homebrew..."
  brew list make &>/dev/null || brew install make
  export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
  echo "Using: $(make --version | head -1)"
fi

# --- Step 2: Theos --------------------------------------------------------------------
if [ ! -f "$THEOS/makefiles/common.mk" ]; then
  echo "Installing Theos (pinned to $THEOS_SHA)..."
  rm -rf "$THEOS"
  git clone --recursive https://github.com/theos/theos.git "$THEOS"
  git -C "$THEOS" checkout "$THEOS_SHA"
  git -C "$THEOS" submodule update --init --recursive
  ACTUAL_THEOS_SHA="$(git -C "$THEOS" rev-parse HEAD)"
  if [ "$ACTUAL_THEOS_SHA" != "$THEOS_SHA" ]; then
    echo "Error: Theos HEAD ($ACTUAL_THEOS_SHA) does not match pinned THEOS_SHA ($THEOS_SHA)." >&2
    exit 1
  fi
fi

# --- Step 3: iOS SDK --------------------------------------------------------------------
if [ ! -d "$THEOS/sdks/iPhoneOS${IOS_SDK_VERSION}.sdk" ]; then
  echo "Fetching iPhoneOS${IOS_SDK_VERSION}.sdk..."
  rm -rf /tmp/theos-sdks-clone
  git clone -n --depth=1 --filter=tree:0 https://github.com/theos/sdks.git /tmp/theos-sdks-clone
  (cd /tmp/theos-sdks-clone && git sparse-checkout set --no-cone "iPhoneOS${IOS_SDK_VERSION}.sdk" && git checkout)
  if [ ! -d "/tmp/theos-sdks-clone/iPhoneOS${IOS_SDK_VERSION}.sdk" ]; then
    echo "Error: theos/sdks has no iPhoneOS${IOS_SDK_VERSION}.sdk. Check IOS_SDK_VERSION in bramble.config" >&2
    echo "against the versions actually listed at https://github.com/theos/sdks." >&2
    rm -rf /tmp/theos-sdks-clone
    exit 1
  fi
  mkdir -p "$THEOS/sdks"
  mv "/tmp/theos-sdks-clone/iPhoneOS${IOS_SDK_VERSION}.sdk" "$THEOS/sdks/"
  rm -rf /tmp/theos-sdks-clone
fi

# --- Step 4: theos-jailed + vendored CydiaSubstrate --------------------------------------
if [ ! -d "$THEOS/mod/jailed" ]; then
  echo "Installing theos-jailed (pinned to $THEOS_JAILED_SHA)..."
  rm -rf /tmp/theos-jailed-clone
  git clone --recursive https://github.com/qnblackcat/theos-jailed.git /tmp/theos-jailed-clone
  git -C /tmp/theos-jailed-clone checkout "$THEOS_JAILED_SHA"

  # Pre-place the vendored framework at theos-jailed's own pre-download check path so its
  # installer finds it already present and skips its network fetch entirely (D-08).
  mkdir -p /tmp/theos-jailed-clone/module/lib
  cp -a "$SCRIPT_DIR/vendor/CydiaSubstrate.framework" \
    "/tmp/theos-jailed-clone/module/lib/CydiaSubstrate_0.9.6301.framework"

  set +e
  INSTALL_OUTPUT="$(THEOS="$THEOS" /tmp/theos-jailed-clone/install 2>&1)"
  INSTALL_EXIT=$?
  set -e
  echo "$INSTALL_OUTPUT"
  if [ "$INSTALL_EXIT" -ne 0 ]; then
    echo "Error: theos-jailed's install script exited $INSTALL_EXIT." >&2
    exit 1
  fi
  if echo "$INSTALL_OUTPUT" | grep -qi 'saurik\|Downloading CydiaSubstrate'; then
    echo "Error: theos-jailed's installer performed a network fetch for CydiaSubstrate --" >&2
    echo "the vendored-framework pre-placement did not take effect (D-08 violation)." >&2
    exit 1
  fi
fi

# --- Step 5: YouTubeHeader ----------------------------------------------------------------
if [ ! -d "$THEOS/include/YouTubeHeader" ]; then
  echo "Cloning YouTubeHeader (pinned to $YOUTUBEHEADER_SHA)..."
  git clone https://github.com/PoomSmart/YouTubeHeader.git "$THEOS/include/YouTubeHeader"
  git -C "$THEOS/include/YouTubeHeader" checkout "$YOUTUBEHEADER_SHA"
fi

# --- Step 6: rootless link search path ----------------------------------------------------
mkdir -p "$THEOS/lib/iphone/rootless"

echo "Toolchain ready: THEOS=$THEOS"
