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

*   **Passive Sync:** Silently shares auction data over the addon channel. No performance hit, no user action required.
*   **Smart Caching:** Builds a searchable index of tens of thousands of items without freezing your game.
*   **Price History:** View detailed price history graphs and see exactly who scanned the item and when.
*   **Flood Maintenance:** Intelligent chat throttling ensures the `?` command never spams your chat channels.

## Installation

1.  **Download** the latest release from [CurseForge](https://www.curseforge.com/wow/addons/market-sync) or GitHub Releases.
2.  **Extract** the `MarketSync` folder into your World of Warcraft AddOns directory:
    *   `_classic_/Interface/AddOns/`
    *   `_retail_/Interface/AddOns/`
3.  **Restart WoW**.

**Dependencies:**
*   [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (Required)

## Usage

### 1. Syncing
Just play the game! As long as you and other guildmates have the addon installed, you are syncing data in the background.

### 2. Offline Browsing
Type `/ms` or `/marketsync` (or click the Minimap Button) to open the main window.
*   **Browse Tab:** Search for items, filter by rarity/level, and see current market prices.
*   **History:** Click the "History" button on an item to view price trends and scan details.

### 3. Chat Price Checks
Link an item in **Guild Chat**, **Party**, or **Raid** with a `?` prefix:
```
? [Linen Cloth]
```
MarketSync will automatically reply with the most recent price from the guild database:
```
[Linen Cloth]: 5s 20c (Age: 10m)
```

## Configuration

Access settings via the **Settings Tab** in the main window (`/ms`):
*   **Lock Minimap Button:** Prevent accidental movement.
*   **Enable Chat Price Check:** Toggle the auto-reply feature on/off.
*   **Enable Passive Sync:** Toggle background data sharing.
*   **Debug Mode:** View verbose logs for troubleshooting.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
