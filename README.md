# MarketSync

MarketSync syncs Auctionator pricing data between guild members and lets you browse it offline.

## Highlights
- **Item Detail Dashboard**: Right-click any item to open a deep-dive window for pricing trends, volume analysis, and historical scan attribution.
- **Item Analytics**: 14-day price charts and data source historiography (Personal vs. Guild breakdown).
- **LibDBIcon Integration**: Minimap button now uses standard libraries for perfect compatibility with MBB/DBI and other UI managers.
- **Neutral AH Safety**: Dedicated storage and sync protocol for Neutral Auction House data.
- **Enhanced Notifications**: 
  - Custom sound selection and volume slider.
  - Middle-click minimap shortcut for quick access.
  - Batch "Select All" actions for alert management.
- **Advanced Processing**: 
  - Arbitrage and Crafting profitability scans.
  - Auctionator export with margin-preserving price caps.

## Neutral AH Safety Model
- Neutral data is stored in isolated realm fields (`NeutralData`, `NeutralMeta`, `NeutralSync`).
- Neutral capture is intercepted from Auctionator writes and mirrored into the isolated store.
- Main personal snapshot flow is skipped when closing a neutral AH session.
- Neutral transport uses guild messages only (`NADV/NPULL/NACCEPT/NBRES/NEND`).

## Tabs
- `Personal Scan`
- `Guild Sync`
- `Neutral AH`
- `Processing`
- `Settings`

## Notifications Manager
Open `Settings -> Notifications`.

You can:
- add/update tracked requests by item name or itemID,
- set threshold, scope (`All/Main/Neutral`), and cooldown,
- enable/disable or delete requests,
- import from one Auctionator shopping list or all lists.

## Sync Reliability
- Single-blast guard blocks overlapping send/receive/broadcast sessions.
- Pull-claim coordination includes stale-claim cleanup to prevent dead pull locks.
- Deferred ADV/NADV handling queues fresher sources while busy and pulls them when clear.
- ADV announcements remain allowed during active sync (throttled) for freshness visibility.

## Slash Commands
- `/ms` or `/marketsync` - open main window
- `/ms search` - open browse UI
- `/ms config` - open interface settings category
- `/ms block <name>` - block a sender
- `/ms unblock <name>` - unblock a sender

## Requirements
- Auctionator (required)
