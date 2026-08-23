export ARCHS = arm64

ifndef IOS_SDK_VERSION
IOS_SDK_VERSION = 17.5
endif

ifndef MINIMUM_OS_VERSION
MINIMUM_OS_VERSION = 14.0
endif

export TARGET = iphone:clang:$(IOS_SDK_VERSION):$(MINIMUM_OS_VERSION)

ifneq ($(JAILBROKEN),1)
MODULES = jailed
endif

ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 0.0.0
endif
ifndef BRAMBLE_VERSION
BRAMBLE_VERSION = 0.1.0
endif
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(BRAMBLE_VERSION)

TWEAK_NAME = Bramble
DISPLAY_NAME = YouTube
BUNDLE_ID = com.google.ios.youtube

include $(THEOS)/makefiles/common.mk

# Logos's `internal` generator swizzles with class_getInstanceMethod/method_setImplementation
# instead of calling MSHookMessageEx, which removes the CydiaSubstrate dependency altogether.
# The bundled Substrate 0.9.6301 links /usr/lib/libstdc++.6.dylib, removed from iOS after 12,
# so on a modern device it cannot load -- and because theos-jailed injects the tweak as
# LC_LOAD_WEAK_DYLIB, dyld skipped Bramble silently and the app launched looking untouched.
# Viable only because Bramble uses no %hookf; add one and this must go back to MobileSubstrate.
Bramble_LOGOS_DEFAULT_GENERATOR = internal

Bramble_FILES = Tweak.x
Bramble_CFLAGS = -fobjc-arc -DBRAMBLE_YOUTUBE_VERSION=\"$(YOUTUBE_VERSION)\"
ifeq ($(INERT),1)
# BRAMBLE_INERT excludes the %init(Hooks) call (Tweak.x), which is the only site that
# references the Logos-generated hook functions -- leaving them intentionally compiled but
# dead code, so -Wunused-function/-Wunused-variable must be suppressed here specifically.
Bramble_CFLAGS += -DBRAMBLE_INERT=1 -Wno-unused-function -Wno-unused-variable
endif
Bramble_FRAMEWORKS = UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0
