# MarketSync

**Your scans. Your guild's market. One place to browse, plan, and buy.**

MarketSync is an Auction House companion for **WoW Forever, Classic Era / Season of Discovery, and TBC**. Scan auctions, keep your own price history, share newer observations with guildmates, and turn those prices into shopping lists, crafting plans, and alerts.

**Auctionator is optional.** MarketSync includes a standalone scanner and can also import supported Auctionator scans when you prefer its scanning interface.

This guide covers **0.9.7-rc6**, the current release candidate.

## Start here

1. Install MarketSync for your client and enable it at character selection.
2. Open an auctioneer and complete a **Full AH Scan** with MarketSync or your selected Auctionator scanner.
3. Close the Auction House so MarketSync can announce the new scan to your guild.
4. Click the minimap icon or use **`/ms`** to browse your saved prices.
5. Access the Crafting Manager via **`/ms craft`**, or expand the AH drawer beside the auction house.
6. Open AddOn Settings via **`/ms config`** to customize memory management, sound triggers, and optional features.

For crafting, open each profession window once so MarketSync can discover the character's known recipes.

---

## Authentic Warcraft Interface Styling

MarketSync features pixel-perfect, native Blizzard interface design:
- **PortraitFrameTemplate Architecture**: The main MarketSync browser, the Crafting & Materials Manager, and the Item Ledger inherit Blizzard's authentic frame template, complete with round metallic portrait rings, authentic emblems, standard Blizzard title bars, and top-right close buttons.
- **Docked Bottom Tabs**: Windows feature Blizzard's docked bottom tabs (`AuctionHouseFrameDisplayModeTabTemplate`), matching the authentic appearance of `AuctionFrame` and `TradeSkillFrame`.
- **Dual-Theme Support**:
  - **Forever / Modern (`_forever_`, `_retail_`)**: Styled in dark bronze dialog textures (`UI-DialogBox-Background-Dark`), amber-gold banners, and bronze tab borders.
  - **Legacy / Classic Era (`_classic_`, `_classic_era_`)**: Styled in authentic parchment (`UI-DialogBox-Background`), silver/slate framing, and muted accents.
- Change themes anytime using **`/ms theme [forever|legacy|auto]`** or under **Settings → Window Theme**.

---

## Understand your price data

### Personal Scan: your own observations

Personal contains the auction prices you recorded yourself. Incoming guild data does not overwrite your personal scan prices or observation times. You can compare what you last recorded with the wider guild market.

### Guild Sync: the cumulative market

Guild combines **your personal observations and validated scans received from guildmates**. Newer observations update this shared view while existing history remains available under the retention rules.

For example, you scan an item at 10g. A guildmate later records it at 12g. Your Personal view retains your 10g observation, while the cumulative Guild view can show the newer 12g quote.

Local items appear in both views, so their counts are not two independent sets of auctions. Prices are recorded observations; an offline quote does not guarantee that a listing is still available to buy.

### Neutral Auction House

Neutral-AH data has its own view and sync scope. It is kept separate from the main faction market.

### Factions and Forever playsets

Alliance and Horde have separate saved price histories, alert state, and sync markets, including when you play both factions in the same environment.

On Forever, numbered backend partitions of the same playset can synchronize (e.g. `English 0` through `English 100+`, `ClassicBetaPvP1` through `ClassicBetaPvP100+`). Different playsets remain separate. Other supported clients retain exact realm matching.

---

## Scan with or without Auctionator

### Standalone MarketSync scanning

The **Scanner** page lets you run a full Auction House scan or scan selected shopping lists. A full scan builds a broad saved-price snapshot; selected lists focus on the items you track.

Full scans follow the client's Auction House cooldown. Native item searches wait for complete results before recording them. Large snapshots are processed in batches so reads, history updates, and item loading can progress across frames.

### Using Auctionator

When Auctionator is installed, MarketSync normally lets it handle scanning and hides the duplicate Scanner tab. Change **Settings → Use Auctionator scanning** to choose MarketSync's native scanner instead.

MarketSync can import supported Auctionator scan observations into its own records. Received guild prices remain cumulative market data rather than being written back as personal Auctionator scans.

### Enhanced Classic Search

On supported Classic clients, the enhanced **Search** page shows live auctions grouped by item variant, unit price, and stack size.

**Scan Entire List** and **Scan Buy Materials** collect results for multiple items into one table. The game still queries items and their result pages in sequence; each item's results remain available together for browsing.

---

## The Auction House breakout drawer

Open the MarketSync arrow beside the Auction House to expand the **sidecar drawer**. It brings three workflows alongside the AH:

| Tab | What it does |
| --- | --- |
| **Shopping** | Create lists, add items, search individual entries, and scan an entire list. |
| **Craft** | Keep crafting requests, adjust quantities, and choose which materials to buy, craft, or provide. |
| **Bags** | Browse auctionable bag items, search their market, and select items into the AH selling interface. |

The drawer can be collapsed when you want more room. Toggle it anytime via **`/ms sidecar`** or `/sidecar`.

---

## Crafting & Materials Workstation

The **Crafting & Materials Manager** (`/ms craft` or `/mscraft`) is a double-wide 832x480 workstation organized into 3 balanced columns:

1. **Left Column (Craft Management & Queue)**: Displays pending and saved crafts, status indicators, and dedicated management controls (`Mark Crafted`, `Record Sale`, `Remove Craft`, `Craft History`).
2. **Middle Column (Recipe Breakdown Tree)**: Interactive hierarchical ingredient tree showing component recipes, quantity needed, and supply choices (`Buy`, `Craft`, `Provide`).
3. **Right Column (Purchase Plan)**: Calculated material shopping plan, right-click purchase prompt, and financial cost breakdowns.

Top preset toolbar buttons allow 1-click strategy evaluation: **Optimal** (smartest ground-up cost), **Buy Finished** (buy end item directly), **Craft All Raw** (recurse to base materials), and **Customer Craft** (zero-cost client provided materials).

---

## Modular Configuration & Settings Cards

MarketSync features an 8-card categorized settings interface under WoW's native AddOn Settings:

1. **Performance & Memory Management**:
   - **Low RAM Mode (Default: ON)**: Drops index tables and runs GC when browse windows close.
   - **Cache Build Speed Slider**: 1 (Conservative) to 4 (Maximum) yielding rates.
   - **Live RAM Footprint Estimator**: Informs you of exact index memory usage in MB.
2. **Professions & Crafting (Production Feature)**:
   - Live TradeSkill window margin calculations, vendor materials, and component trees.
3. **Auction House & Scanning**:
   - Scanner toggle, tooltip buyout prices, Expected Values (EV) for disenchant/prospecting/milling, and multi-character inventory counts.
4. **Audio & Notifications**:
   - Audio alerts with sound preview, volume slider, minimap flashing, and on-screen raid alert banners.
5. **Data Sync & Swarm**:
   - Guild sync and Neutral AH sync toggles, user blocking/unblocking, and smart rule bandwidth management.
6. **Beta & Experimental Features**:
   - **Processing Tab**: Production-ready module near general release for recursive crafting solver, vendor arbitrage, and batch shopping lists.
   - **Price Alerts Tab**: Production-ready module near general release for price threshold monitoring, watchlists, and raid warnings.
   - **Transactional Item Ledger (Auto-Disabled by Default)**: Experimental FIFO cost tracking, inventory reconciliation, and ledger logs. Kept auto-disabled (`EnableLedgerBeta = false`) to avoid overhead for non-testers. All UI buttons are dimmed/disabled until toggled on.
7. **Window Theme**:
   - Auto (client version), Forever (dark bronze), or Legacy (parchment/slate).
8. **Debugging & Diagnostics**:
   - Network Monitor and diagnostic chat output.

---

## Multi-Realm Sharding & Backend Scalability

On Forever, single playsets are distributed across numbered backend shards (e.g. `English 0` through `English 100+`, `ClassicBetaPvP1` through `ClassicBetaPvP100+`).

MarketSync automatically strips trailing numeric shard suffixes (`%d+$`) across arbitrary integer ranges (no ceiling at 100) and folds them into a canonical playset key (`english`).
- **Safe Network Limits**: Outgoing bandwidth is strictly governed by a Token Bucket ceiling (< 640 B/s), and only 1 broadcaster is elected per bucket.
- **Faction Isolation**: All shard operations strictly preserve faction boundaries (`@Horde` vs `@Alliance`).

---

## Commands

| Command | Action |
| :--- | :--- |
| `/ms` or `/marketsync` | Toggle the main MarketSync window |
| `/ms craft` (or `/mscraft`, `/craftmanager`, `/crafts`) | Open Crafting & Materials Manager |
| `/ms sidecar` (or `/sidecar`, `/mssidecar`) | Toggle AH Shopping & Bag Selling drawer |
| `/ms ledger` (or `/ledger`, `/msledger`) | Open Item Ledger (when Beta is enabled) |
| `/ms search` or `/ms browse` | Open the offline market browser |
| `/ms theme [forever\|legacy\|auto]` | Switch UI window styling |
| `/ms config` (or `/ms settings`, `/ms options`) | Open AddOn settings panel |
| `/ms block <player>` | Block a specific sync sender |
| `/ms unblock <player>` | Unblock a sync sender |

---

## Links & License

[Source and documentation](https://github.com/Bl4ut0/MarketSync) · [Release downloads](https://github.com/Bl4ut0/MarketSync/releases) · [Report an issue](https://github.com/Bl4ut0/MarketSync/issues)

MarketSync is licensed under **GPL-3.0**.
