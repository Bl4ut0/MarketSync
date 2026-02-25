# MarketSync

> **Synchronizes Auctionator scan data between guild members to create a shared, offline-accessible pricing database with instant chat price checks.**

**MarketSync** turns your guild into a unified pricing network. It automatically synchronizes Auctionator scan data between all guild members in the background, creating a shared, up-to-date pricing database for everyone.

If *one* person scans the Auction House, *everyone* gets the data instantly.

## Why MarketSync?

*   **🚫 No More Stale Prices:** You log in, but your Auctionator data is 3 days old? Not anymore. If a guildmate scanned 10 minutes ago, you already have their data.
*   **🏰 Offline Auction House:** Browse the entire synced database anywhere in the world. Open the custom **Browse Panel** to search for items, check prices, or see what's available—even inside a raid or dungeon.
*   **💬 Instant Price Checks:** Link an item in guild chat with a `?` prefix (e.g., `? [Linen Cloth]`), and MarketSync will auto-reply with the latest known price from the cloud.
*   **⚙️ Zero Configuration:** Just install it. It detects Auctionator automatically and starts listening.

## Key Features

*   **Passive Sync:** Silently shares auction data over the addon channel every 5 minutes. No performance hit, no user action required.
*   **Smart Caching:** Builds a searchable index of tens of thousands of items without freezing your game. Configurable cache build speed (1–4) to balance between indexing speed and game performance.
*   **Price History:** View detailed price history graphs and see exactly who contributed the item data for each specific day via per-scan-day attribution.
*   **Separated Data Views:** Personal scans and guild sync data are physically separated. Your personal data never gets overwritten by incoming guild syncs.
*   **Debug Console:** Full-featured network monitor with three panels — Sync Network event log, Swarm Queue tracker, and Cache Processing Stream — for complete visibility into what the addon is doing.
*   **Version Guard:** Automatically handles version mismatches between guild members. Outdated clients are safely disabled from syncing to prevent data corruption.
*   **Flood Protection:** A two-phase `CLAIM` protocol with deterministic tiebreaking guarantees exactly one client responds to any `?` price check — even when multiple guild members are online simultaneously.

## ⚠️ System Impact & RAM Usage

Because MarketSync stores the *entire* auction house directly in your client's active memory for instant, offline browsing, **it does use a noticeable amount of RAM**. 

For example, maintaining two simultaneous, 30,000-item caches (one for your Personal Scan, one for the Guild Sync proxy) can consume **~60-70 MB** of system memory. While this is highly optimized for the sheer scale of data being handled, MarketSync will likely appear at the top of your addon memory usage list.

If you experience frame drops or stutters during the background index building process (which occurs when you first log in, or right after you finish an AH scan), you can adjust the **Cache Build Speed** slider in the MarketSync Settings tab. Lowering the speed will dramatically ease the CPU load by spreading the cache building process over a longer, gentler background duration.

## How Sync Works

MarketSync uses a **Swarm Coordinator** protocol to efficiently share data across your guild:

1. **Advertisement:** Every 5 minutes, each client broadcasts what data it has (realm, scan day, item count, version).
2. **Pull Request:** If another client has fresher data, you automatically request it.
3. **Consensus:** Multiple potential senders coordinate to elect a single "seeder" to avoid redundant broadcasts.
4. **Bulk Transfer:** The seeder transmits item data using the **Protocol v4** architecture:
   - **Full Variation Support:** Base-36 encoding perfectly preserves random suffixes (e.g., "of the Bear") using a custom `_` packet delineator, allowing accurate pricing across thousands of variant enchants.
   - **5 parallel data channels** (`MSyncD1`–`MSyncD5`) for quintuple throughput
   - **Base-36 encoding** compresses numeric payloads by ~30%
   - **248-byte dense packing** maximizes items per message (~16 per chunk)
   - Achieves **~80 items/sec** sustained, completing a full 25,000-item sync in **~10 minutes**
5. **Commit:** After receiving the `END` signal, clients immediately commit the items to their guild index. To prevent chat flood from massive guilds, the client applies a **randomized 1-20s Jitter Delay** before responding with a safe `ACK` confirmation to the sender.

### Protocol Architecture

| Layer | Prefix | Purpose |
|---|---|---|
| **Control** | `MarketSync` | ADV, PULL, ACCEPT, CLAIM, RES, REQ, ERR, END — plain text with character names and realm info |
| **Data** | `MSyncD1`–`MSyncD5` | BRES bulk payloads (`dbKey_price_qty_day`) — v4 base-36 compressed |

This separation ensures character names with special characters pass through untouched on the control layer, while the data layer maximizes throughput with compressed encoding.

### WoW Addon Message Limits & Safety Overloads

MarketSync is explicitly engineered to never trigger a Blizzard API throttle disconnect. Even in a 500-member mega-guild, the Swarm Sync engine protects bandwidth:

| Constraint | WoW Limit | MarketSync Usage |
|---|---|---|
| Per-prefix bucket | 10 msgs burst, 1/sec regen | 1 msg/sec per prefix (never drains) |
| Global CPS (Bytes/Sec) | ~1500–2000 safe threshold | ~1250 bytes/sec (~30% beneath safety limit) |
| Message payload | 255 bytes | 248 bytes (7 byte safety margin) |
| Price Check Flood | Chat channel disconnects | Two-phase CLAIM protocol with 300ms grace + deterministic tiebreaker |

## Installation

1.  **Download** the latest release from [CurseForge](https://www.curseforge.com/wow/addons/market-sync) or GitHub Releases.
2.  **Extract** the `MarketSync` folder into your World of Warcraft AddOns directory:
    *   `_classic_/Interface/AddOns/`
    *   `_retail_/Interface/AddOns/`
3.  **Restart WoW**.

**Dependencies:**
*   [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (Required)

**Compatibility:**
*   WoW Classic (including Anniversary, TBC, SoD)
*   WoW Retail

## Usage

### 1. Syncing
Just play the game! As long as you and other guildmates have the addon installed, data syncs automatically in the background every 5 minutes. No manual action needed.

### 2. Offline Browsing
Type `/ms` or `/marketsync` (or click the Minimap Button) to open the main window.
*   **Personal Scan Tab:** Your personally scanned AH data, stored in an isolated snapshot.
*   **Guild Sync Tab:** Data received from guild members via the Swarm Network.
*   **Leaderboard Tab:** See which guild members are contributing the most data (toggle All Time / Weekly).
*   **History:** Click the "History" button on any item to view price trend graphs and per-day scan attribution.

### 3. Chat Price Checks
Link an item in **Guild Chat**, **Party**, or **Raid** with a `?` prefix:
```
? [Linen Cloth]
```
MarketSync will automatically reply with the most recent price from the guild database:
```
[Linen Cloth]: 5s 20c (Age: 14:32 RT (Playername))
```
If multiple guild members have the addon installed, only **one** client responds — the built-in Swarm anti-flood system uses a randomized lottery with instant addon-channel coordination to guarantee a single reply.

## Configuration

Access settings via the **Settings Tab** in the main window (`/ms`):
*   **Lock Minimap Button:** Prevent accidental movement.
*   **Enable Chat Price Check:** Toggle the auto-reply feature on/off.
*   **Enable Passive Sync:** Toggle background data sharing.
*   **Cache Build Speed:** Adjust how aggressively the addon indexes items (1 = gentle, 4 = fast).
*   **Debug Mode:** View verbose logs for troubleshooting.
*   **Debug Console:** Open the standalone network monitor with full event log, swarm queue, and cache processing stream.
*   **Reset Data:** Wipe all sync data and create a fresh personal snapshot.
*   **Rebuild Caches:** Manually trigger a re-index of personal and guild databases.
*   **Manage Users:** Block/unblock specific sync partners.

## Slash Commands

| Command | Description |
|---|---|
| `/ms` | Open the main window |
| `/ms search` | Open the browse window |
| `/ms config` | Open settings panel |
| `/ms block [name]` | Block a sync sender |
| `/ms unblock [name]` | Unblock a sync sender |

## File Structure

```
MarketSync/
├── Config.lua       # Shared globals, DB init, helpers, prefix registration
├── Sync.lua         # Protocol, base-36 encoding, data merging, passive/bulk sync
├── Chat.lua         # Event handler for addon messages and chat queries
├── UI_Browse.lua    # Browse panel & search index
├── UI_History.lua   # Price history graphs & scan attribution
├── UI_Monitor.lua   # Debug Console (network log, swarm queue, cache stream)
├── UI_Main.lua      # Frame shell, tabs, settings
├── Core.lua         # Minimap, slash commands, ADDON_LOADED
└── MarketSync.toc   # Table of contents
```

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
