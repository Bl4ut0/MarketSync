# Classic-family backport status

MarketSync uses one data model and two Auction House transports. Forever (and any client exposing `C_AuctionHouse.SendSearchQuery`) keeps the modern scanner and embedded Auction House tabs. Classic Era, Anniversary, and Season of Discovery share the legacy `QueryAuctionItems` scanner in a portable **Scanner** tab; TBC selects whichever Auction House API its client exposes. The Personal Scan, Guild Sync, Neutral AH, Analytics, Processing, Alerts, and Settings panels remain in the portable window.

The portable window has a saved **Window Theme** selector in its Settings tab and Blizzard AddOn Settings. Forever keeps the current frame shell; Legacy restores the old v0.8 AuctionFrame parchment pieces, bottom-tab template and spacing, with warmer panel chrome. The choice is independent of client flavor and reloads the UI to reconstruct the frame. Current functional panel contents remain shared between themes, so this is not an older codebase or a rollback of newer features.

The legacy scanner supports a full get-all scan when `CanSendAuctionQuery()` allows it, plus targeted list scans by item name with result-page traversal. It aggregates auction rows by item ID and suffix, stores minimum unit buyout and available quantity, and sends observations through MarketSync's shared history/sync pipeline. Auctions without buyouts are not used as price observations. It waits for the server throttle rather than issuing queries every frame, and reads/writes large scans in batches.

The portable **Search AH** tab is a separate live query, not a saved-scan lookup. Enter an item name while the auctioneer is open; MarketSync walks the result pages and groups listings only when item variant, stack size, and exact stack buyout match. The view shows unit buyout, stack size, number of auctions, and total available quantity. Search results are temporary and do not overwrite the scan database or broadcast to the guild. Search actions from MarketSync's scan feed and analytics route here on legacy clients. This first pass is read-only: bidding and buying still use the native Auction House controls.

On the classic Auction House sell pane, MarketSync adds a manual **Undercut 1c/unit** suggestion. It reads the last observed unit price, converts to the sell pane's unit/stack price mode, and fills the buyout (plus a valid starting bid if needed). The player must review and post the auction. This control does not appear on Forever and does not use main-AH prices at a neutral AH. Item variants should be reviewed carefully because the legacy sell-slot API exposes an item ID, not a full variant link.

Build client-specific test packages with the Interface number reported by that **installed client** (the numbers below are the values currently declared in the source TOC, not a guarantee of future client compatibility):

```text
python tools/package.py --output dist/MarketSync-Forever.zip --interface 16001 --flavor forever
python tools/package.py --output dist/MarketSync-Era.zip --interface 11509 --flavor era
python tools/package.py --output dist/MarketSync-Anniversary.zip --interface <installed-interface> --flavor anniversary
python tools/package.py --output dist/MarketSync-SoD.zip --interface 11509 --flavor sod
python tools/package.py --output dist/MarketSync-TBC.zip --interface 20506 --flavor tbc
```

All flavor ZIPs contain a single `MarketSync/` folder from the same source/version. Each has a flavor-specific load type and Interface, plus a manifest and SHA-256 sidecar. They are **test builds**, not published releases. The packager deliberately requires an explicit Interface for Era, Anniversary, SoD, and TBC rather than guessing the installed client's build. Verify those values before distributing them.

The automated package matrix checks the archive structures, load types, TOC Lua entries, and sidecars. CI bundles Era, SoD, and TBC ZIPs as **test artifacts** from the same commit; Anniversary needs its installed-client Interface number before a CI artifact can be generated. The CurseForge publisher still uploads only Forever. This does not establish runtime compatibility. The live-client checks still needed are: addon load without Lua errors; legacy full-scan availability/cooldown and actual completion; live Search AH grouping and multi-page results; targeted multi-page list scans; item suffix identity; portable Scanner layout; neutral-AH isolation; Guild Sync; Auctionator coexistence; manual undercut suggestion; and whether individual Processing recipes/outputs apply to each ruleset. Do not publish the legacy flavors until those checks pass.
