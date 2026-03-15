# MarketSync

**Synchronizes Auctionator scan data between guild members to create a shared, offline-accessible pricing database with instant chat price checks.**

MarketSync turns your guild into a unified pricing network. It automatically synchronizes Auctionator scan data between all guild members in the background, creating a shared, up-to-date pricing database for everyone.

If one person scans the Auction House, everyone gets the data instantly.

## Why MarketSync?
- 🚫 **No More Stale Prices**: You log in, but your Auctionator data is 3 days old? Not anymore. If a guildmate scanned 10 minutes ago, you already have their data.
- 🏰 **Offline Auction House**: Browse the entire synced database anywhere in the world. Open the custom Browse Panel to search for items, check prices, or see what's available—even inside a raid or dungeon.
- 💬 **Instant Price Checks**: Link an item in guild chat with a `?` prefix (e.g., `? [Linen Cloth]`), and MarketSync will auto-reply with the latest known price from the cloud.
- ⚙️ **Zero Configuration**: Just install it. It detects Auctionator automatically and starts listening.

## Key Features
- **Passive Sync**: Silently shares auction data over the addon channel every 5 minutes. No performance hit, no user action required.
- **Item Detail Dashboard**: A dedicated window for deep-dive inspection of item pricing trends, volume analysis, and historical scan attribution (Right-click any item).
- **Item Analytics**: 14-day price trend charts and data source historiography (Personal vs. Guild percentages) to track exactly where your data comes from.
- **Smart Caching**: Builds a searchable index of tens of thousands of items without freezing your game. Configurable cache build speed (1–4) to balance between indexing speed and game performance.
- **Price History**: View detailed price history graphs and see exactly who contributed the item data for each specific day via per-scan-day attribution.
- **Separated Data Views**: Personal scans and guild sync data are physically separated. Your personal data never gets overwritten by incoming guild syncs.
- **Debug Console**: Full-featured network monitor with three panels — Sync Network event log, Swarm Queue tracker, and Cache Processing Stream — for complete visibility into what the addon is doing.
- **Neutral AH Safety**: Dedicated storage and sync protocol for Neutral Auction House isolation. Main realm data is never contaminated by neutral Prices.
- **Advanced Processing**: Find profitable flips and crafts (EV/Arbitrage) directly within MarketSync, with margin-preserving export to Auctionator shopping lists.
- **Notification System**: Set threshold alerts for specific items with custom sound selection, volume control, and Auctionator shopping-list import support.
- **LibDBIcon Integration**: Unified minimap icon with standard library support for perfect compatibility with MBB, DBI, and other UI managers.
- **Version Guard**: Automatically handles version mismatches between guild members. Outdated clients are safely disabled from syncing to prevent data corruption.
- **Flood Protection**: A two-phase CLAIM protocol with deterministic tiebreaking guarantees exactly one client responds to any `?` price check.

## ⚠️ System Impact & RAM Usage
Because MarketSync stores multiple Auction House databases (Personal, Guild Sync, and Neutral) directly in your client's active memory for instant, offline browsing, it can consume a significant amount of RAM.

- **Standard Usage**: Maintaining large caches (30,000+ items each) across all three databases can consume **200+ MB** of system memory.
- **Top of the List**: MarketSync will likely appear at the top of your addon memory usage list due to the scale of data being handled.

### 🛡️ Low RAM Features
If you are playing on a system with limited memory or experience frame drops during login, MarketSync includes several built-in optimization tools:

- **Low RAM Master Mode**: Enables the aggressive memory management suite.
- **On-Demand Indexing**: Instead of building all search indices at once on login, MarketSync will only index a database (Personal, Guild, or Neutral) when you actually click on its tab. This significantly reduces initial memory load.
- **Automatic Pruning**: Every login, MarketSync automatically prunes its metadata. It keeps only the **7 most recent scan days** per item and removes entries for items not seen in more than **30 days**.
- **Yielding Cache Builder**: If you experience stutters during indexing, use the **Cache Build Speed** slider. Lowering the speed spreads the work over a longer duration, keeping your frame rate smooth.

## How Sync Works
MarketSync uses a **Swarm Coordinator** protocol to efficiently share data across your guild:

1.  **Advertisement**: Every 5 minutes, each client broadcasts what data it has (realm, scan day, item count, version).
2.  **Pull Request**: If another client has fresher data, you automatically request it.
3.  **Consensus**: Multiple potential senders coordinate to elect a single "seeder" to avoid redundant broadcasts.
4.  **Bulk Transfer**: The seeder transmits item data using the Protocol v4 architecture:
    - **Full Variation Support**: Base-36 encoding preserves random suffixes (e.g., "of the Bear").
    - **5 Parallel Channels**: Uses `MSyncD1–D5` prefixes to bypass single-prefix rate limits.
    - **Base-36 Encoding**: Compresses numeric payloads by ~30%.
    - **248-Byte Dense Packing**: Maximizes items per message (~16 per chunk).
    - Achieves **~80 items/sec** sustained, completing a full 25,000-item sync in ~10 minutes.
5.  **Commit**: After receiving the `END` signal, the client applies a randomized 1-20s **Jitter Delay** before acknowledging, preventing server-side chat flood.

### Protocol Architecture
| Layer | Prefix | Purpose |
| :--- | :--- | :--- |
| **Control** | `MarketSync` | `ADV`, `PULL`, `ACCEPT`, `CLAIM`, `RES`, `REQ`, `ERR`, `END` — Main Realm Sync |
| **Control** | `MarketSync` | `NADV`, `NPULL`, `NACCEPT`, `NCLAIM`, `NERR`, `NEND` — Neutral AH Sync |
| **Data** | `MSyncD1`–`MSyncD5` | `BRES` (Main) / `NBRES` (Neutral) bulk payloads (`dbKey_price_qty_day`) — v4 base-36 compressed |

## WoW Addon Message Limits & Safety Overloads
MarketSync is explicitly engineered to never trigger a Blizzard API throttle disconnect. Even in a 500-member mega-guild, the Swarm Sync engine protects your connection:

- **Per-Prefix Buckets**: MarketSync utilizes 5 distinct prefixes. Each prefix has its own Blizzard-enforced "token bucket" (10 burst, 1/sec regen). MarketSync never exceeds 1 msg/sec per prefix.
- **Global Self-Throttling**: The engine monitors *all* addon traffic. If other addons (like Attune or Questie) are saturating the network, MarketSync proactively pauses its own sync until the traffic clears.
  - **API Limit**: ~40 msgs/sec
  - **Bandwidth Limit**: ~800 bytes/sec
- **Message Payload**: Every message is capped at 248 bytes (allowing for a safety margin below the 255-byte hard limit).
- **Price Check Flood**: A two-phase `CLAIM` protocol with a 300ms grace period ensures that only one person in the guild replies to a `?` price check.

## Installation
1.  Download the latest release from CurseForge or GitHub Releases.
2.  Extract the `MarketSync` folder into your World of Warcraft AddOns directory:
    - `_classic_/Interface/AddOns/`
    - `_retail_/Interface/AddOns/`
3.  Restart WoW.

**Dependencies:**
- Auctionator (Required)

**Compatibility:**
- WoW Classic (including Anniversary, TBC, SoD)
- WoW Retail

## Usage

### 1. Syncing
Just play the game! As long as you and other guildmates have the addon installed, data syncs automatically in the background every 5 minutes. No manual action needed.

### 2. Offline Browsing
Type `/ms` or `/marketsync` (or click the Minimap Button) to open the main window.
- **Personal Scan Tab**: Your personally scanned AH data, stored in an isolated snapshot.
- **Guild Sync Tab**: Data received from guild members via the Swarm Network.
- **Neutral AH Tab**: Isolated pricing data from the Neutral Auction House.
- **Processing Tab**: Profitability scanners and shopping list export tools.
- **Leaderboard Tab**: See which guild members are contributing the most data (toggle All Time / Weekly).
- **History/Analytics**: Click the "History" or "Analytics" button on any item to view price trend graphs and detailed scan attribution.

### 3. Chat Price Checks
Link an item in Guild Chat, Party, or Raid with a `?` prefix:
`? [Linen Cloth]`

MarketSync will automatically reply:
`[Linen Cloth]: 5s 20c (Age: 14:32 RT (Playername))`

## Configuration
Access settings via the **Settings Tab** in the main window (`/ms`):
- **Lock Minimap Button**: Prevent accidental movement.
- **Enable Chat Price Check**: Toggle the auto-reply feature.
- **Enable Passive Sync**: Toggle background data sharing.
- **Cache Build Speed**: Adjust indexing aggressiveness (1 = gentle, 4 = fast).
- **Notification Sounds**: Choose sound, adjust volume, and open the notifications manager.
- **Smart Rules**: Toggle automatic sync/cache suspension during combat/instances.
- **Debug Console**: Open the standalone network monitor and swarm queue tracker.
- **Reset Data / Rebuild Caches**: Maintenance tools for database management.

## Slash Commands
| Command | Description |
| :--- | :--- |
| `/ms` | Open the main window |
| `/ms search` | Open the browse window |
| `/ms config` | Open settings panel |
| `/ms block [name]` | Block a sync sender |
| `/ms unblock [name]` | Unblock a sync sender |

## File Structure
- `Config.lua`: Shared globals, DB initialization, and configuration constants.
- `Sync.lua`: Protocol handling, base-36 encoding, and network throttling.
- `Chat.lua`: Event handlers for chat queries and addon messages.
- `Neutral.lua`: Isolated logic for Neutral AH sync and capture.
- `Processing.lua / UI_Processing.lua`: Profitability scanner logic and UI.
- `Notifications.lua / UI_Notifications.lua`: Notification alert logic and management UI.
- `UI_Browse.lua`: Main search indexer and paginated browse results.
- `UI_History.lua`: Price trend charting and historical attribution.
- `UI_Analytics.lua`: Detailed item health and historiography dashboards.
- `UI_ItemDetail.lua`: The Item Detail Dashboard window.
- `UI_Monitor.lua`: Debug Console (network log, swarm queue, cache stream).
- `UI_Main.lua`: Frame shell, tab management, and settings layout.
- `Core.lua`: Minimap integration, event dispatching, and slash commands.
- `Libs/`: Embedded libraries including `LibDBIcon`, `LibDataBroker`, and `LibStub`.

## License
This project is licensed under the GNU General Public License v3.0 - see the `LICENSE` file for details.
