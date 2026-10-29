---
quick_id: 261029-kea
date: 2026-10-29
---
# Fullscreen seek bar clear of the home indicator

iPhone landscape fullscreen: the seek bar sat in the home-indicator swipe zone, so scrubbing opened the app switcher.

1. Stop forcing relatedVideosPeekingEnabled=NO (re-apply fc7785d).
2. Lift YTInlinePlayerBarContainerView by the bottom safe-area inset + 10pt in landscape via setFrame:/setCenter: hooks; defer the bottom-edge system gesture.
3. Device-check on iPhone 15 Pro Max.
