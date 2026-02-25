# MarketSync Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.3] - 2026-02-25
### Improved
- **Improved**: **Hybrid Metadata Retention Policy**. Introduced a two-tier automated pruning system that prevents unbounded RAM growth from `ItemMetadata` accumulation over long-term usage. **Tier 1** caps per-item `days` attribution sub-tables to the **7 most recent scan days**, removing old day-by-day "who synced it" entries that no feature relies on. **Tier 2** removes the **entire** metadata entry for items whose `lastTime` is older than **30 days** — if nobody has scanned or synced an item in a month, the attribution data is stale and meaningless. On a mature dataset (~30k items with months of daily scans), this reduces `ItemMetadata` RAM usage by approximately **75-80%**. The pruning runs lazily at **Stage 2.5** (60 seconds after login), slotted between passive sync startup and search index building, with zero impact on gameplay performance. **Auctionator's price database is never touched** — only MarketSync's own attribution metadata is pruned.

## [0.5.2] - 2026-02-22
### Fixed
- **Fixed**: A stale `CachedScanStats` cache caused the Swarm to report an incorrect item count after receiving a sync. The cached count was written once per session by `CountRecentItems()` and never invalidated when incoming `BRES` data inserted new items into the Auctionator database. Any `ADV` broadcast that fired mid-transfer would silently advertise the pre-sync count. The cache is now eagerly invalidated on the very first `BRES` chunk of each sync session, and again when `CommitGuildSync()` finalizes the merge — guaranteeing the next `ADV` always re-counts from the live database.
- **Fixed**: A race condition between the 8-second idle timeout and the `END` packet that could cause a fully successful sync to be misidentified as "partial." If the idle timer fired before `END` arrived, it reset `RxCount` to 0. When `END` then checked `rxCount >= itemsSent`, it saw 0 and skipped the `PersonalScanTime` stamp — leaving the client eligible for a redundant re-PULL on the next ADV cycle. Introduced a `sessionRxTotal` counter that survives the timeout reset, so the `END` handler always has the true received count for completeness validation.
- **Fixed**: The Chat Price Check anti-flood system (`? [Item Link]`) was completely non-functional, causing every client on the network to reply simultaneously. Three bugs were identified and resolved: (1) **Self-reply** — clients replied to their own queries because the self-sender filter only applied to addon protocol messages, not chat events. Self-queries are now properly ignored. (2) **No addon-channel coordination** — the old system relied on detecting another client's visible *chat reply* to cancel a pending response, but chat messages have delivery latency and both random timers would fire before either reply was delivered. A new two-phase `CLAIM` protocol has been introduced: when a client's random timer fires, it broadcasts `CLAIM;itemID` on the addon prefix (near-instant, zero chat throttle) but holds its chat reply for a 300ms grace period. If a competing `CLAIM` arrives during that window, a deterministic alphabetical-name tiebreaker guarantees exactly one winner — even when two clients fire within milliseconds of each other. (3) **Wider lottery window** — the random delay has been widened from 0.5–2.0s to 0.5–3.0s to further reduce the chance of timer collisions.
- **Fixed**: The `BroadcastRecentData()` ticker never cancelled itself after the coroutine finished, causing an orphaned timer that fired indefinitely. It now self-cancels once the broadcast completes.

### Improved
- **Improved**: `UpdateLocalDBByKey()` — the sync hot path — now caches the realm database reference once per call instead of resolving `GetRealmDB()` 6 times per item. During a 2,000-item sync this eliminates ~12,000 redundant `GetNormalizedRealmName()` lookups.
- **Improved**: The passive advertisement ticker no longer performs a redundant `IsInInstance()` check. This condition is already handled by `CanSync()` inside `SendAdvertisement()`, which also covers combat, raids, dungeons, PvP, and arena — a strict superset.
- **Improved**: The `CLAIM` handler now evicts stale `claimContestants` entries for items no longer in play, preventing the table from growing indefinitely over long sessions with frequent `?` queries.

## [0.5.1] - 2026-02-21
### Improved
- **Improved**: Data throughput limit increased from 3 channels to **5 parallel channels**. This raises network utilization to ~1250 bytes/second (~80 items/sec), significantly dropping the time it takes to complete massive bulk syncs.
- **Improved**: **Contextual Mute (Smart Bandwidth)**. Active Swarm transfers (`ADV` polling, `PULL` requests, and seeding payloads) are now strictly suppressed if the player is in Combat, a Raid, a Dungeon, a Battleground, or an Arena. This completely guarantees MarketSync leaves 100% of network baseline available overhead for combat-critical addons (like Details! and DBM) precisely when you need it most.
- **Improved**: Added a **Smart Rules** GUI toggle button inside the Settings tab. This opens a new configuration frame that allows you to easily toggle off the Contextual Mute if you manually prefer to let MarketSync push data during combat or while inside instances.
- **Improved**: The background Swarm **Cache Indexer** is now also bound by the Smart Rules configuration. Heavy local data processing will automatically and seamlessly pause the exact moment you enter combat or an instance, and pick up exactly where it left off when you exit.
- **Improved**: Filter categories in the Browse Window no longer display a distracting scrollbar or shrink when expanded. They are permanently fixed at their native width, and players can freely scroll them up and down using their mouse wheel.
- **Improved**: Search results table sorting logic is now significantly more robust and mimics the native Auction House: Sorting by Level now prioritizes the highest rarity items first, then drops to alphabetical order. Sorting by Rarity drops to alphabetical order if rarities are identical.
- **Improved**: MarketSync now listens to the global `AUCTION_HOUSE_SHOW` event, dynamically locking its Swarm Cache Indexer and Network `ADV` broadcasts. This guarantees MarketSync will silently wait and not consume resources or advertise incomplete strings while you are actively running a fresh Auctionator page scan.
- **Fixed**: Restructured the UI bindings over on the Settings tab so the new 'Smart Rules' button doesn't visually overlap the 'Reset Data' or 'Rebuild Caches' buttons.
- **Fixed**: Corrected a deep scoping bug inside the `C_Timer.NewTicker` logic that inadvertently locked the high-speed Swarm data multiplexer strictly to `MSyncD1`, dropping its intended round-robin speed. It now mathematically guarantees iteration across all 5 channels sequentially at roughly 80 items/sec.
- **Fixed**: Stripped the forceful generic `tonumber()` conversion on inbound database keys during `BRES` chunk parsing. Items arriving as numeric strings (e.g. `"1234"`) are seamlessly stored natively to the Auctionator DB, cleanly wiping out instances of twin duplicate items displaying in the search menu.
- **Fixed**: Built a dynamic deduplication filter layer over the top of the graphical `Browse` search pipeline. If overlapping identical twin internal Auctionator keys somehow exist (or have been created previously), the rendering layer actively collapses them and strictly prints the copy with the lowest overall price.
- **Fixed**: Severed a legacy "item count tiebreaker" in the Chat engine that could trigger an infinite sync loop. If two clients share the exact identical `TSF` timestamp, the engine will mathematically guarantee their payloads match perfectly and unconditionally drop any arbitrary `< / >` exact item count disparities.

## [0.5.0] - 2026-02-20
### Improved
- **Improved**: Full `dbKey` string preservation (Protocol v4). The sync engine now safely transmits the raw Auctionator suffix formats (e.g. `11976:0:0:0:0:0:684:0`) utilizing a new `_` delimiter. This guarantees that **all** randomized enchantments and suffix items ("of the Bear", "of the Eagle") are perfectly preserved, synchronized, and accurately priced across the guild.
- **Improved**: Settings tab Auto-Refresh. The Index Cache status indicators on the Settings page now smoothly poll and update in real-time every 0.5 seconds, preventing the progress from looking "stuck" until you swap tabs.
- **Improved**: `ACK` Overload Prevention. Added a randomized 1-to-20 second jitter delay to the final `ACK` message when a client finishes downloading a full database. This completely prevents guild channel disconnection floods when massive 500-player guilds all finish a bulk transfer simultaneously.
- **Improved**: The default Minimap Icon angle was moved from 0 degrees (3 o'clock) to 215 degrees (bottom-left) to cleanly avoid overlapping with Blizzard's default tracking and zoom buttons.
- **Improved**: Added **Hard Search** capability logic to the Browse index engine. Users can now perfectly isolate massive variant pools by wrapping their query string in exact quotes (e.g., `"Runecloth"` vs just `Runecloth`), immediately hiding derivative items.

### Fixed
- **Fixed**: UI Browse Indexing Drop. Rewrote the `ParseItemID` omni-parser to intelligently locate numeric bases regardless of arbitrary Auctionator string prefixes (`item:`, `i:`, letter suffixes). This completely fixes the bug where tens of thousands of variant items correctly existed in the local cache but silently failed to appear in the Browse search list.

## [0.4.5] - 2026-02-20
### Fixed
- **Fixed**: A critical sender coroutine starvation bug that caused mid-transfer disconnects. When large stretches of items were skipped (unparseable dbKey formats), the coroutine would run for too long without yielding, causing WoW to silently kill the execution frame. A safety yield every 500 scanned entries now prevents this.
- **Fixed**: ADV item count inflation. `CountRecentItems` was counting ALL dbKeys in the Auctionator database (including unparseable suffix formats like `"12345:0:0:0"`), but `RespondToPull` could only send items with recognized key formats (`%d+`, `g:%d+`, `p:%d+`). The advertised count now matches the actual transferable count, preventing receivers from seeing partial sync percentages that never reach 100%.
- **Fixed**: Personal Scan snapshot inflation. `SnapshotPersonalScan` was cloning every entry from the Auctionator database—including ~20,000 items with unparseable dbKey formats—into the PersonalData pool. The snapshot now filters with the same parseable-key validation used by the sync engine, so the reported item count matches what can actually be displayed in the Browse tab.
- **Fixed**: Sync freshness backwards compatibility with v0.4.3 clients. When the sender doesn't include TSF (legacy client), the system now correctly falls back to item count comparison instead of silently failing the freshness check.

### Improved
- **Improved**: Explicit `END` packet for verified sync completion. The sender now transmits a dedicated `END;itemsSent;messagesSent;senderTSF` control message when the transfer finishes, allowing the receiver to immediately commit instead of waiting for an 8-second idle timeout.
- **Improved**: Verified full-sync validation. The receiver compares its `RxCount` against `itemsSent` from the END packet. Only when `RxCount >= itemsSent` does it stamp its freshness. Partial or timed-out syncs remain eligible for re-PULL on the next ADV cycle.
- **Improved**: Sender TSF passthrough prevents ping-pong sync loops. The receiver stamps the sender's original `PersonalScanTime` (not `time()`) so both clients share the same TSF watermark and neither sees the other as "fresher."
- **Improved**: ADV and PULL suppression during active transfers. Clients no longer broadcast advertisements or initiate new PULLs while actively sending or receiving data, eliminating redundant sync cycles.
- **Improved**: Personal Scan snapshot isolation. `SnapshotPersonalScan()` is no longer called after guild sync commits — the Personal Scan tab only updates when the player personally visits the Auction House.
- **Improved**: Guild Sync tab redesigned as "Best Available Data" view. Instead of only showing items tagged with network metadata, the Guild Sync tab now indexes the complete live Auctionator database—your personal scan as baseline plus any incoming guild sync data merged on top. This ensures the Guild tab always shows the most up-to-date prices regardless of source. When you scan the AH, the index is automatically invalidated and rebuilt with your fresh data.
- **Improved**: Automatic data migration on login. If existing `PersonalData` contains unparseable legacy keys from pre-0.4.5, the addon automatically re-snapshots on login to clean up inflated counts—no manual data wipe required.
- **Improved**: Debug Console line caps set to 500 lines (network log, cache stream) and 50 lines (swarm queue) to prevent unbounded RAM growth during long sessions.
- **Improved**: Cache builder coroutine ticker now respects the Cache Speed slider interval instead of hardcoded 0.01s.

## [0.4.4] - 2026-02-20
### Fixed
- **Fixed**: A severe ambiguity bug in the Swarm consensus logic. Previously, if two users scanned on the exact same "day" (e.g., today), the sync receiver would aggressively reject the upload if the incoming payload had superficially *fewer* items due to natural Auction House churn over the span of a few hours. The Swarm Receiver now intelligently parses the exact Realm Timestamp (`TSF`), prioritizing absolute time freshness over volatile item count differentials.
- **Fixed**: Unregistered outgoing broadcast events. The Debug Console's Network Monitor previously ignored `CHAT_MSG_ADDON` packets matching your own character name, making it impossible to see your own data transmissions. Outgoing `[ADV]`, `[PULL]`, and `[ACCEPT]` signals are now natively hooked to safely bypass the chat filter, visually printing to your console so you know exactly when your client pings the guild.
- **Fixed**: A cross-character data leak involving `SyncStats`. The all-time database seeding leaderboards were improperly writing your network statistics directly into the global `MarketSyncDB` root instead of your isolated `MarketSync.GetRealmDB()` partition. The counters have been rerouted to prevent cross-realm data contamination.

### Improved
- **Improved**: Complete conversion of all local timestamps to Realm Time (`RT`). Timestamp displays on the Personal Scan tab, Guild Sync tab, and Chat Price Checks now uniformly reflect the server's timezone, negating confusion across different geographical locations.
- **Improved**: The Personal Scan tab date formatting was rewritten. It now dynamically calculates the physical Realm Time offset to accurately display `Today at XX:XX RT`, `Yesterday at XX:XX RT`, or `Month DD at XX:XX RT`. This replaces the static (and often incorrect) "Today at" text applied to legacy database entries. Local timezone acronyms (EST, PST, CEST, etc.) were completely stripped from the UI to match the new unified Realm Time standard.
- **Improved**: Swarm Network Protocol upgraded. The `[ADV]` broadcast data packet now transmits a discrete 5th parameter specifically representing the rigid Realm Timestamp (`TSF`) of your data cache, allowing all clients in the swarm to accurately reconstruct chronological sync timelines.

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
