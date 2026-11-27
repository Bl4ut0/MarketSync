# MarketSync 0.9.8-rc1

Release candidate supporting **Forever (`1.60.1`)**, **Classic Era / SoD (`1.15.8`, `1.15.9`)**, **Anniversary / TBC (`2.5.5`, `2.5.6`)**, **Classic Progression (`3.8.0`, `5.5.3`)**, and **Retail (`12.0.0`, `12.0.1`)**. Auctionator is optional.

## Regional & Per-Market Data Pack Support

- At login (`PLAYER_ENTERING_WORLD`), MarketSync resolves the active client flavor, region, realm/ruleset, and faction (`GetClientRegion`, `GetDataPackMarketContext`, `EnsureCurrentDataPack`) and loads **only** the matching LoadOnDemand `MarketSyncData` pack (supporting both `MarketSyncData_Forever_<ruleset>_<faction>` and regional connected-realm/commodity packs via `MarketSyncData.Index`).
- Mismatched game flavors and regions are strictly blocked, Data Pack prices are read on demand without copying rows into `GuildData`, and Analytics (`GetDataPackRecord`) reads the character's active market partition directly.

## Main Tab, Latest Source & Low RAM Mode

- Merged Personal and Guild views into the unified **Main** tab with a **Source** selector (`Latest`, `Personal`, `Guild`, `Neutral`, `Data Pack`) backed by `LatestIndex.lua` merging.
- Added **Low RAM mode** controls (`keep Main tab source loaded`, automatic idle source purging, and per-addon memory diagnostics).
- Added native Classic multi-list scanning (`UI_LegacyMultiScan.lua`), analytics source/date/week/time filters, and unified Auction House panel & minimap entrypoints.

## Shopping List Import & Export

- Shopping lists export as `!MS1!` strings with a CRC32 check. Imports are strictly validated, so a corrupted or malformed string is rejected instead of partially saved.
- `/ms import <string>` imports directly; `/ms import` with no text opens the import dialog.

## Posting Warning

- Before posting, MarketSync asks for confirmation when the unit price is at or below 60% of the median of recent comparable listings (minimum three listings seen within five minutes). The price can still be kept.

## Processing, Alerts & Sync Reliability

- Upgraded **Processing** and **Alerts** panels (flexible price input, responsive layouts across standalone & embedded AH views, real `SOUNDKIT` alert cues).
- Refused `BEGIN`, `DATA`, and `END` sync frames retry with bounded backoff; stalled `BEGIN` transfers abort cleanly without falsely reporting completion, and control queues are capped.
- Extracted optional **MarketSyncLedger 1.0.1** (craft ledger, item ledger, and purchase lists) as a separate toggleable companion addon under **Options -> AddOns -> MarketSync Ledger**.
