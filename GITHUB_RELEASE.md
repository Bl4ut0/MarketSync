## MarketSync v0.8.0-rc2

### Release candidate

This build is intended for WoW TBC Anniversary 2.5.6 (Interface 20506) and WoW Classic Era/Season of Discovery 1.15.9 (Interface 11509) testing with Auctionator 332. Back up your SavedVariables and report Lua errors, incomplete transfers, or unexpected alerts before guild-wide rollout.

### Classic Era / Season of Discovery 1.15.9 compatibility

- Declares Interface 11509 so the addon loads normally after the Edit Mode update.
- Uses the same guarded Settings and UI API path validated on TBC Anniversary 2.5.6.
- Preserves Auctionator's legacy-AH full-scan lifecycle on Era/SoD and supports the installed Auctionator 332 database/event API.

### Reliable guild synchronization

- **One broadcast at a time:** The exact owner of the newest requested scan sends one sequential guild-wide session. Newer scans wait until the current broadcast finishes.
- **Safe completion:** Session IDs and ordered chunks prevent late or mixed packets from completing the wrong transfer. Incomplete data is discarded and never becomes fresh or eligible to rebroadcast.
- **Shared bandwidth budget:** Main and Neutral AH remain independently configurable but use weighted logical queues over one physical sender, leaving headroom for control messages and other addons.
- **Efficient payloads:** Compact base-36 delta records avoid resending history points receivers already know, reducing transfer time without expensive general-purpose compression.
- **No guild ACK storm:** Receivers verify completion locally. A missed packet cannot hold every other guild member behind a retry.
- **Protocol-aware upgrades:** Compatible releases may communicate across addon versions; incompatible clients advertise update status only and are prompted to upgrade before exchanging market data.

### Correct processing values

- Prospecting, milling, disenchanting, and crafting now calculate profit from net Auction House proceeds after the 5% sale cut.
- Variable-yield recipes use expected output rather than assuming the minimum result.

### Notifications and Neutral AH

- Minimap flashing and in-addon banners provide visual alerts with sound disabled by default.
- Urgent rules, per-item sound choices, and the master volume control are available when audio is wanted.
- Main and Neutral price updates share the same notification evaluator.
- Neutral freshness changes only after MarketSync captures a real neutral scan.

**Full Changelog**: https://github.com/Bl4ut0/MarketSync/compare/v0.7.0...v0.8.0-rc2
