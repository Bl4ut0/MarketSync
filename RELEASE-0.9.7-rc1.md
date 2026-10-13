# MarketSync 0.9.7-rc1

Release candidate for Forever 1.60.1 (Interface 16001), Classic Era / SoD 1.15.9, and TBC 2.5.6. Auctionator is optional.

## Fixed

- Guild members on numbered Forever backend realms now discover each other and exchange auction data within the same playset. For example, ClassicBetaPvP and ClassicBetaPvP2 match; PvP and PvE remain separate.
- The matching rule is specific to Forever. Other clients keep exact realm checks, and full character identities and existing saved data are preserved.

## Improved

- Scan Entire List and Scan Buy Materials now collect results on the enhanced Classic Search page, showing every item's live price and stack groups together.
- Source-page purchase verification preserves the exact search used for each item. Bulk scanning remains unchanged.
- The local installer now accepts the Forever beta client.

## Testing

Both guild members should install this candidate and reload. Test discovery and completed main/neutral transfers between numbered Forever partitions, and confirm that separate playsets remain isolated. On Classic clients, test list searches spanning multiple items/pages and buying a verified stack. Please report Lua errors or missing peers/results with the client build and realm names.

Full changelog: https://github.com/Bl4ut0/MarketSync/compare/v0.9.6...v0.9.7-rc1
