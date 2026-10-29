---
quick_id: 261029-kea
status: complete
---
# Summary

- Geometry-based transform lift matched the wrong views; a transform on YTInlinePlayerBarContainerView is ignored on device.
- Working fix: hook YTInlinePlayerBarContainerView setFrame:/setCenter:, shift a bottom-flush frame up by inset+10pt in landscape; 1 s timer re-sets the frame so the hooks run.
- relatedVideosPeekingEnabled no longer forced NO.
- Device-checked on iPhone 15 Pro Max (iOS 26), 2026-10-29: bar sits clear of the home indicator.
