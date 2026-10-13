# MarketSync 0.9.7-rc2

Release candidate for Forever 1.60.1 (Interface 16001), Classic Era / SoD 1.15.9, and TBC 2.5.6. Auctionator is optional.

## Faction separation

- Alliance and Horde now have separate saved auction prices, histories, alert state, and sync freshness on the same realm/playset. Switching characters restores the active faction's own data.
- Guild price advertisements, requests, and transfers require an explicit matching faction. Opposite-faction and older unlabelled messages are rejected; unknown player faction disables syncing.
- Forever still matches numbered backend partitions within the same playset. Full character identities remain unchanged, and other clients keep exact realm matching.

## Upgrading

Update both guild members to rc2 and reload. Older unlabelled price histories remain preserved in SavedVariables as an archive, but are not reused because their faction cannot be determined reliably. Run a fresh scan on each faction or receive prices from another rc2 user. Saved profession knowledge is retained.

This candidate includes rc1's enhanced Classic shopping-list and craft-material searches. Please report Lua errors, missing peers, or prices appearing under the wrong faction with your client build, faction, and realm name.

Full changelog: https://github.com/Bl4ut0/MarketSync/compare/v0.9.7-rc1...v0.9.7-rc2
