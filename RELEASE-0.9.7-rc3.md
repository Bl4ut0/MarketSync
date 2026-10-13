# MarketSync 0.9.7-rc3

Release candidate for Forever 1.60.1 (Interface 16001), Classic Era / SoD 1.15.9, and TBC 2.5.6. Auctionator is optional.

## Scan and guild-sync fixes

- Scan announcements deferred while the auction house is open now retry after closing. Rate-limited announcements retry after the remaining throttle interval.
- Personal shows your own recorded scans. Guild contains cumulative local observations and validated guild scans; incoming data no longer overwrites your personal scan prices or times.
- Incomplete native searches request the remaining results before saving or advertising them. Paging activity extends the search inactivity timeout.
- Quotes use their own observation timestamps and available quantities. Cache rebuilds no longer re-import saved prices as fresh observations.
- Replayed records do not duplicate history or activity. Older personal observations cannot overwrite newer cumulative quotes. The existing revision-based delta selection remains in place.
- Both data stores follow retention and reset rules. Optional Auctionator integration reads cumulative quotes without feeding received data back into personal scan imports.

## Upgrading and testing

Update and reload both guild members. Complete a full scan, close the auction house, and check for a nonzero advertisement followed by a pull and completed transfer. Received prices should update Guild while Personal remains unchanged. Forever playset matching and Alliance/Horde isolation from rc2 are retained.

Existing cumulative history is preserved. Records identifiable as received are separated from Personal during migration; personal values already overwritten by older versions cannot be reconstructed exactly.

This release promotes the locally tested rc3-local1 changes. Please report Lua errors, failed transfers, or unexpected Personal/Guild prices with your client build, faction, and realm name.

Full changelog: https://github.com/Bl4ut0/MarketSync/compare/v0.9.7-rc2...v0.9.7-rc3
