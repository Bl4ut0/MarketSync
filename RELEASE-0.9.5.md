# MarketSync 0.9.5

This Forever pre-release includes the MarketSync improvements since 0.9.4. The CurseForge package targets Forever 1.60.1 (build 70205).

## What's New

- Analytics now has a collapsible Recent Scans and Favorites sidebar. The price chart expands when the sidebar is hidden, offers 12, 24, 48, and 96-observation zoom controls plus mouse-wheel zoom, and shows the visible price range.
- Processing now supports item drag-and-drop for Target Material, saved craft analyses, and profession data scanned on another compatible character. Its controls and results have been reorganized to fit both MarketSync windows.
- Crafting materials now resolve from item IDs to the client's localized names when item data becomes available. The Classic Trade Skill anchor error and legacy Processing overflow were fixed.
- Watched scanning uses the checked lists, while Full AH remains a separate scan. Classic Era, Season of Discovery, Anniversary, and TBC now have a standalone legacy scanner, grouped live search and buying view, AH sidecar, and automatic legacy styling in the shared codebase.

The legacy client packages are still CI test artifacts, not part of this Forever CurseForge upload. Processing and Alerts remain opt-in beta features. Legacy buying, posting, and scan behavior still need in-game validation before a multi-flavor CurseForge release.
