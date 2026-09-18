# MarketSync

**Synchronizes Auctionator scan data between guild members to create a shared, offline-accessible pricing database with instant chat price checks.**

MarketSync turns your guild into a unified pricing network. It automatically synchronizes Auctionator scan data between all guild members in the background, creating a shared, up-to-date pricing database for everyone.

If one person scans the Auction House, everyone gets the data instantly.

> **v0.8.0-rc2:** Validated on WoW TBC Anniversary 2.5.6 (Interface 20506) and WoW Classic Era/Season of Discovery 1.15.9 (Interface 11509) with Auctionator 332.

## Why MarketSync?
- 🚫 **No More Stale Prices**: You log in, but your Auctionator data is 3 days old? Not anymore. If a guildmate scanned 10 minutes ago, you already have their data.
- 🏰 **Offline Auction House**: Browse the entire synced database anywhere in the world. Open the custom Browse Panel to search for items, check prices, or see what's available—even inside a raid or dungeon.
- 💬 **Instant Price Checks**: Link an item in guild chat with a `?` prefix (e.g., `? [Linen Cloth]`), and MarketSync will auto-reply with the latest known price from the cloud.
- ⚙️ **Zero Configuration**: Just install it. It detects Auctionator automatically and starts listening.

## Key Features
- **Granular Intraday Time-Series Tracking**: Bypasses traditional daily locks to record and perfectly merge 30-minute interval market data across the entire guild, tracking true market inflation and variance throughout the day safely in compressed memory.
- **Passive Sync**: Advertises fresh scans in the background and coordinates one guild-wide broadcast at a time, with no manual action required.
- **Item Detail Dashboard**: A dedicated window for deep-dive inspection of item pricing trends, volume analysis, and historical scan attribution (Right-click any item).
- **Item Analytics**: 14-day price trend charts and data source historiography (Personal vs. Guild percentages) to track exactly where your data comes from.
- **Smart Caching**: Builds a searchable index of tens of thousands of items without freezing your game. Configurable cache build speed (1–4) to balance between indexing speed and game performance.
- **Price History**: View detailed price history graphs and see exactly who contributed the item data for each specific day via per-scan-day attribution.
- **Separated Data Views**: Personal scans and guild sync data are physically separated. Your personal data never gets overwritten by incoming guild syncs.
- **Debug Console**: Full-featured network monitor with three panels — Sync Network event log, Swarm Queue tracker, and Cache Processing Stream.
- **Neutral AH Safety**: Dedicated storage and sync isolation for Neutral Auction House data. Freshness advances only after a real neutral scan is captured.
- **Advanced Processing**: Find profitable flips and crafts using net Auction House proceeds and expected recipe yields, with margin-preserving export to Auctionator shopping lists.
- **Notification System**: Minimap flashing and in-addon banners are available without sound. Optional urgency, per-item sounds, and master volume controls are included; sound is disabled by default.
- **LibDBIcon Integration**: Unified minimap icon with standard library support for perfect compatibility with MBB, DBI, and other UI managers.
- **Version Guard**: Release versions and wire-protocol revisions are managed separately. Compatible releases may communicate; incompatible clients advertise update status only and cannot exchange market payloads.
- **Flood Protection**: A two-phase CLAIM protocol guarantees exactly one client responds to any `?` price check.

## ⚠️ System Impact & RAM Usage
Because MarketSync stores multiple Auction House databases (Personal, Guild Sync, and Neutral) directly in your client's active memory for instant, offline browsing, it can consume a significant amount of RAM.

- **Standard Usage**: Maintaining large caches (30,000+ items each) across all three databases can consume **200+ MB** of system memory.
- **Top of the List**: MarketSync will likely appear at the top of your addon memory usage list due to the scale of data being handled.

### 🛡️ Low RAM Features
If you are playing on a system with limited memory or experience frame drops during login, MarketSync includes several built-in optimization tools:
- **Low RAM Master Mode**: Enables the aggressive memory management suite.
- **On-Demand Indexing**: Only indexes a database (Personal, Guild, or Neutral) when you actually click on its tab.
- **Automatic Pruning**: Automatically prunes metadata every login (keeps only the 7 most recent scan days).
- **Yielding Cache Builder**: Adjust the **Cache Build Speed** slider to reduce CPU load during indexing.

## How Sync Works
MarketSync uses a **Swarm Coordinator** protocol to efficiently share data across your guild:
1.  **Advertisement**: Clients announce their scope, scan identity, release version, and protocol revision.
2.  **Exact-Source Request**: A stale client requests the newest advertised scan, and only that advertiser may seed it.
3.  **Single Sequential Session**: One guild-wide broadcast completes before the newest queued advertisement is considered. Session IDs and ordered chunks prevent late packets from contaminating another transfer.
4.  **Compact Delta Transfer**: Low-CPU base-36 records omit history points receivers already have while preserving complete Auctionator item keys.
5.  **Verified Commit**: Only a complete session advances freshness or becomes an outbound source. Incomplete staging data is purged and does not trigger a blocking retry.

## WoW Addon Message Limits & Safety Overloads
MarketSync is explicitly engineered to minimize its impact on the shared addon-message channel:
- **One Physical Sender**: Main and Neutral AH use independently configurable, weighted logical queues over one sequential transmitter, preventing parallel database dumps.
- **Reserved Headroom**: Main traffic receives priority, Neutral traffic can borrow idle capacity, and control packets retain room within the combined budget.
- **Progress-Preserving Throttling**: MarketSync meters its own traffic and backs off under channel pressure without abandoning the active session.
- **Message Payload**: Every message is capped at 248 bytes (allowing for a safety margin below the 255-byte limit).
- **No ACK Flood**: Receivers validate completeness locally; one incomplete listener neither floods the guild with acknowledgements nor delays the next broadcast.
- **Price Check Flood**: A two-phase `CLAIM` protocol ensures that only one person in the guild replies to a `?` price check.

## Usage

### 1. Syncing
Just play the game! Data syncs automatically in the background every 5 minutes. No manual action needed.

### 2. Offline Browsing
Type `/ms` or `/marketsync` (or click the Minimap Button) to open the main window.
- **Personal Scan Tab**: Your personally scanned AH data.
- **Guild Sync Tab**: Data received from guild members.
- **Neutral AH Tab**: Isolated pricing data from the Neutral Auction House.
- **Processing Tab**: Profitability scanners and shopping list export tools.
- **History/Analytics**: Click the "History" or "Analytics" button on any item to view trend graphs.

### 3. Chat Price Checks
Link an item in Guild Chat, Party, or Raid with a `?` prefix:
`? [Linen Cloth]`
MarketSync will automatically reply with the latest known price from the guild database.

## Slash Commands
| Command | Description |
| :--- | :--- |
| `/ms` | Open the main window |
| `/ms search` | Open the browse window |
| `/ms config` | Open settings panel |
| `/ms block [name]` | Block a sync sender |
| `/ms unblock [name]` | Unblock a sync sender |

## License
This project is licensed under the GNU General Public License v3.0.
