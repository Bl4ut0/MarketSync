# MarketSync Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.3] - 2026-02-20
### Improved
- **Improved**: Swarm sync engine completely rewritten for maximum throughput within WoW's documented addon message limits. The system now uses **3 parallel data channels** (`MSyncD1`, `MSyncD2`, `MSyncD3`) with round-robin dispatch at 1 msg/sec per prefix, achieving **3 messages per second** sustained (744 bytes/sec, well under the 2000 CPS safe limit). Combined with **base-36 payload encoding** (~30% compression), each message packs ~16 items into 248 bytes. Total throughput: **~48 items/sec**. A full 2355-item sync completes in **~50 seconds** in a single pass with zero drops, down from 5-6 retry cycles over 25+ minutes.
- **Improved**: The `BRES` bulk sync protocol has been upgraded to **v3**. All numeric fields (itemID, price, quantity, day) are now base-36 encoded per-item (`id:price:qty:day`), and transmitted on dedicated data channel prefixes separate from control messages. The receiver auto-detects encoding format and is fully backwards-compatible with decimal v1/v2 data from older clients.
- **Improved**: The Network Monitor window has been expanded into a full **Debug Console**. It now contains three panels: the Sync Network event log, the Swarm Queue tracker, and a new **Cache Processing Stream** that emits live timestamped entries as the index builder reads, resolves, and commits Personal and Guild data — so you can see exactly what the cache engine is doing at any given moment.
- **Improved**: Item history attribution has been upgraded from a single flat "last writer wins" source stamp to a **per-scan-day attribution model**. Each day in an item's history now independently credits the player who actually contributed that specific day's price data, so the History popup correctly displays the original contributor per day rather than crediting the most recent sync partner for every row. Old save data gracefully falls back to legacy attribution.

### Added
- **Added**: Sender and receiver both now emit **checkpoint progress notifications** to the Debug Console every 100 items, showing exact counts of items sent, messages transmitted, database entries scanned, and total items received — providing full visibility into sync progress.
- **Added**: A "Reset Data" button has been added to the Settings tab. This securely wipes all MarketSync tables and immediately processes a fresh Personal Scan snapshot, entirely without deleting or tampering with your legacy Auctionator system data.
- **Added**: A "Rebuild Caches" button has been added to the Settings tab. This lets you manually trigger a re-index of the Personal and Guild databases so you can see the cache processing status update in real-time.

### Removed
- **Removed**: The "Run Bulk Sync" button and `/ms sync` slash command have been removed. The passive sync system automatically advertises and syncs every 5 minutes, making manual triggers redundant.

## [0.4.2] - 2026-02-19
### Fixed
- **Fixed**: Decoupled the MarketSync `Personal Scan` cache from the Live Swarm database. When you visit the Auction House, the addon now takes a rigid snapshot of your data and clones it into an isolated `PersonalData` memory pool. 
- **Fixed**: Personal scans and Guild Sync data are now strictly and physically separated in the Browse tabs.
  - The `Personal Scan` tab physically reconstructs its search index from your isolated snapshot pool. Incoming Guild Syncs can aggressively overwrite Live prices without ever touching or shrinking your Personal UI tab data.
  - The `Guild Sync` tab strictly builds its index by filtering the most up-to-date live Swarm metadata.
- **Fixed**: A data parsing crash where Swarm Syncs would randomly halt perfectly in the middle of a chunk transmission. This occurred when the core engine encountered a rare corrupt Auctionator item entry containing a history array `h` but completely lacking a local market price `m`.

### Improved
- **Improved**: First-launch protection. If you install MarketSync `0.4.2` and have an existing Auctionator database but no offline snapshot, the addon will automatically clone your existing live data within 5 seconds of logging in so your UI does not appear blank.
- **Improved**: `Personal Scan` tab now displays a clean, user-friendly prompt requesting the player to visit the Auction House if their offline cache is 100% empty, instead of simply saying "No results found."
- **Improved**: Leaderboard UI has been redesigned. Filter buttons have been moved into the frame layout (instead of crowding the title bar window controls), added column titles, and implemented subtle row highlights.
- **Improved**: The Version Guard system now continuously tracks legacy clients that attempt to sync with the swarm. Your client will correctly ignore their outdated data payloads, but will now explicitly list the user as "Legacy (vX.X.X)" in your real-time Swarm Queue so you can politely inform guildmates they need to update.
- **Improved**: Implemented deep Swarm Trace Logging. If the Swarm Coordinator experiences a catastrophic coroutine failure while transmitting data, the exact `dbKey` causing the database loop to crash will now be visibly pushed to the Network Monitor event log so users and developers can easily track corrupted edge-case table data. Furthermore, the broadcaster will send a network-wide `ERR` pulse instantly notifying the receiving player exactly why their sync stream halted mid-transfer.

## [0.4.1] - 2026-02-19
### Added
- **Global Network Monitor**: Added a live Tx/Rx (Send/Receive) bandwidth indicator to the top right of the main window so you can safely watch data synchronize in real-time. Also added a standalone, draggable Network Monitor popup window in the Settings tab that acts as a P2P debugging console. It features a full event log and a scrollable Swarm Queue tracker that dynamically lists all connected local and active guild peers based on their synchronization status. 
- **Swarm Coordinator**: Implemented a decentralized consensus protocol for data syncing. When multiple users have the same updated data, they now automatically coordinate and elect a single "seeder" to broadcast the payload. This prevents redundant spam in the guild channel and preserves network bandwidth. Your local connection is natively shown in the new Swarm Queue so you can visibly confirm when you are idling, queuing, seeding, or downloading from the swarm.
- **Version Guard**: The passive sync system now smartly handles version mismatches. If the newest data comes from a newer version of the addon, your outdated client will safely disable its network sync and prompt you to update (your offline browsing and personal scans will continue to work perfectly). If the data comes from an older version of the addon, your client will simply ignore it, allowing the new network to persist without interruption.

### Fixed
- **Fixed**: A severe logic bug prevented clients with massive Auctionator databases (>50k items) from properly interacting with the Swarm Network. The passive detection engine used a hard-coded sample size of 200 items to determine if your data was "fresh" enough to broadcast to the guild. Because arrays are unordered in Lua, it almost entirely missed newly updated items, tricked the client into thinking its DB was empty, and resulted in complete network silence. The engine now calculates absolute data integrity safely without lagging your game: it builds a highly efficient Hash of your scan stats and caches it. The cache dynamically invalidates itself if you visit the Auction house or receive network syncs, ensuring your client announces perfectly accurate Swarm availability every time.
- **Fixed**: Hard-throttled the bulk broadcast system to send 25 items per second. Previously, the system attempted to push thousands of items per second causing the WoW client to silently drop ~98% of the data to protect from chat floods, resulting in "only 24 items synced" out of a full scan.
- **Fixed**: Swarm Network transmission throttle. Previously, the system strictly limited network packets to 20-25 items per second to avoid triggering the WoW client's AddonMessage throttle (which silently drops fast network spam). The Swarm Network has been vastly upgraded with a new `BRES` core module that chunks payloads into 220-byte arrays, compressing ~15 items into a single network API message. The throttle has been aggressively raised and safely tuned to transmit ~150 network objects per second smoothly, making Swarm P2P syncs extremely fast without encountering silent drops.
- **Fixed**: Swarm API collisions for massive guilds. If multiple Swarm seeders possessed the same Auction Data (e.g. 10 users finish a scan within 10 minutes), a random delay of 0-2 seconds was used to establish consensus over who transmits the `PULL` queue. During high concurrency, network latency often caused multiple seeders to claim the transmission queue simultaneously and mathematically saturate the Guild bandwidth constraints. The consensus delay window has been safely expanded to 0-8 seconds, giving all clients enough physical ping overhead to detect a "claiming" seeder before initiating their own redundant data floods.
- **Fixed**: Same-day silence anomaly. Previously, if you organically looked up a single item on the Auction House, it correctly logged your client's data as "Today". If a guildmate then finished a massive 20,000-item system scan that was also logged as "Today", your client would ignore their massive upload because it assumed both arrays were equally fresh. The addon now natively verifies absolute chunk sizes of same-day arrays and will actively request a Swarm push if a guildmate holds more objects than you do on the exact same timestamp.
- **Improved**: The Personal Scan display previously only showed "Today" or "0d ago". The addon now securely snapshots the exact hour and minute (e.g. `2:43 PM`) your client closed the Auction House, and cleanly displays that exact timeframe next to your locally acquired items, so you can perfectly gauge if the Guild Sync network holds future data compared to your local cache.
- **Fixed**: Sync broadcast now correctly handles items not yet cached by the game client, preventing "0 items synced" issues when pushing data to guildmates.
- **Improved**: The Leaderboard UI has been heavily refined. You can now toggle between "All Time" and "Weekly" seeding stats using buttons at the top right of the leaderboard. Because Swarm "seeders" can push hundreds of thousands of items, the raw tracker numbers became bloated and unreadable. The "Items Synced" column has been properly renamed to "Items Seeded" (to reflect P2P uploads to the guild network), and massive numbers are now cleanly formatted with `k` and `m` suffix abbreviations (e.g. `2.4m items`).

## [0.4.0-beta] - 2026-02-19
### Initial Public Beta Release
First major release for testing. Introduces the core Guild Sync functionality and Offline Browsing.

### Added
- **Passive Guild Sync**: Automatically shares Auctionator scan data between guild members in the background.
- **Offline Auction House**: Browse the entire synced database anywhere in the world via `/ms` or the minimap button.
- **Chat Price Checks**: 
    - Type `? [Item Link]` in chat to query the network for the latest price.
    - Added **Anti-Flood System**: Randomized response delay (0.5s - 2.0s) to prevent chat spam when multiple users have the addon.
    - Added suppression logic: If another user replies first, your addon cancels its pending message.
- **History & Analytics**:
    - "History" button in Browse tab opens a detailed graph of price trends.
    - View individual scan data points (Price, Quantity, Scanner Name).
- **Settings Panel**:
    - **Lock Minimap Button**: Prevent accidental drags.
    - **Enable/Disable Chat Replies**: Toggle the `?` query feature.
    - **Passive Sync**: Turn background data sharing on/off.
    - **Debug Mode**: View verbose sync logs.
- **UI & Aesthetics**:
    - Custom "Paper Doll" style 2D Character Portrait in the main window.
    - Clean, tabbed interface (Browse, Personal Scan, Guild Sync, Leaderboard, Settings).
    - Minimap Button: Left-Click to open window, Right-Click to jump straight to Settings.
    - Custom Icon integration (support for `icon.tga` or `.blp` in addon folder).
    
### Changed
- Rebranded from "AuctionatorAnnouncer" to **MarketSync**.
- Moved "Lock Minimap Button" option from Interface Options to the main addon Settings tab for better accessibility.
- Optimized item cache building to run in the background without freezing the game client.
- Standardized background textures to official Blizzard `Browse` styling for seamless integration.

### Fixed
- Fixed "hard edge" visual artifacts on the main window background.
- Fixed overlapping text in the Settings tab layout.


## [0.3.0] - 2026-02-18 (Internal)
### Added
- Basic chat query functionality.
- Initial implementation of the Browse tab.

## [0.2.0] - 2026-02-17 (Internal)
### Added
- Core sync protocol (`ADV` / `REQ` / `PULL` / `RES`).
- Database structure for storing multi-realm data.

## [0.1.0] - 2026-02-15 (Internal)
### Added
- Project initialization.
- Auctionator API integration.
