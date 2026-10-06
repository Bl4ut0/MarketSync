# Classic-family backport status

MarketSync uses one data model and two Auction House transports. Forever (and any client exposing `C_AuctionHouse.SendSearchQuery`) keeps the modern scanner and embedded Auction House tabs. Classic Era and Season of Discovery use the legacy `QueryAuctionItems` scanner in a portable **Scanner** tab; TBC selects whichever Auction House API its client exposes. The Personal Scan, Guild Sync, Neutral AH, Analytics, Processing, Alerts, and Settings panels remain in the portable window.

The legacy scanner supports a full get-all scan when `CanSendAuctionQuery()` allows it, plus targeted list scans by item name with result-page traversal. It aggregates auction rows by item ID and suffix, stores minimum unit buyout and available quantity, and sends observations through MarketSync's shared history/sync pipeline. Auctions without buyouts are not used as price observations. It waits for the server throttle rather than issuing queries every frame, and reads/writes large scans in batches.

Build client-specific test packages with the Interface number reported by that **installed client** (the numbers below are the values currently declared in the source TOC, not a guarantee of future client compatibility):

```text
python tools/package.py --output dist/MarketSync-Era.zip --interface 11509 --game-type classic
python tools/package.py --output dist/MarketSync-SoD.zip --interface 11509 --game-type classic
python tools/package.py --output dist/MarketSync-TBC.zip --interface 20506 --game-type tbc
```

All three ZIPs contain a single `MarketSync/` folder. They are **test builds**, not published releases. Verify the client Interface values before distributing them. The live-client checks still needed are: addon load without Lua errors; legacy full-scan availability/cooldown and actual completion; targeted multi-page list scans; item suffix identity; portable Scanner layout; neutral-AH isolation; Guild Sync; and whether individual Processing recipes/outputs apply to each ruleset. The Forever-only CurseForge workflow does not upload these flavors.
