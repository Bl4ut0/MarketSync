# MarketSync 0.9.3 — Forever

This release brings the improvements made since the 0.9.0 CurseForge upload into one Forever-focused package. Auctionator remains optional: MarketSync can scan independently or consume Auctionator scans. Processing and Alerts remain opt-in beta features.

## Highlights

- Alert lists now open a mass-import review window in both the portable MarketSync window and the Auction House tab. Set each item's threshold, scope, urgent flag, enabled state, and inclusion before saving.
- Processing has clearer target-material and craft-profit views, a conservative minimum-yield profit baseline, and minimum/expected/maximum outcome estimates. Its ROI display and price-history fallback were corrected.
- Low RAM mode loads each scan database on demand instead of building every search index at startup. Settings have been reorganized in Blizzard's AddOn menu, with beta tabs hidden until enabled.
- Scanner feed names and icons, chat item-link sending, keyboard focus/Escape handling, network-status placement, duplicate tooltip text, and several button/scroll layouts were fixed.
- Posting prices now match the market price instead of automatically undercutting; unstackable items no longer show a false stack line.

## Companion integration since 0.9.0

- `MarketSync.ObservationAPI.v1` reports local and verified guild-synced item observations, variants, known quantities, and scan start/finish/cancel events. `scanTime` and `observedTime` distinguish exact local timestamps from coarser synced timestamps. See the bundled `OBSERVATION_API.md` for the contract and precision limits.

## Compatibility and caution

Version 0.9.3 targets Forever 1.60.1 (build 69893). Other WoW client versions are declared in the TOC but have not been validated for this release. Processing estimates depend on known recipes and price coverage; disenchant odds for custom Forever gear remain unverified. Please report the client build, scanner mode, reproduction steps, and Lua errors when filing a bug.
