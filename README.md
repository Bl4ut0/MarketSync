# MarketSync 0.9.7-rc6 — Forever Release Candidate

**Scan once. Share prices with your guild. Browse the market away from the Auction House.**

MarketSync is a Forever-first Auction House companion for saved prices, guild synchronization, item history, shopping lists, crafting planning, and analytics. Release candidate 0.9.7-rc6 targets Forever 1.60.1 (Interface 16001), Classic Era / SoD 1.15.9, and TBC 2.5.6.

Auctionator is optional: MarketSync includes its own native, frame-sliced auction scanner, or can seamlessly capture Auctionator full scans when both addons are installed.

---

## What You Can Do

* **Browse Offline**: Search your personal scans, guild-synced prices, and neutral-AH data in separate views away from the auctioneer.
* **Authentic Warcraft Interface Styling**:
  * Main window, Crafting Manager, and Item Ledger are built on Blizzard's authentic `PortraitFrameTemplate` with native NineSlice borders, round portrait emblems, title bars, and docked bottom tabs.
  * Dual-theme support: Dark bronze on Forever/Retail (`UI-DialogBox-Background-Dark`) and parchment/slate on Classic Era (`UI-DialogBox-Background`).
* **Auction House Breakout Sidecar**: Dockable drawer beside the AH window with three synchronized tabs:
  * **Shopping**: Create custom shopping lists, add items, search individual entries, and scan lists.
  * **Craft**: Manage pending crafting requests, inspect recipe breakdowns, and choose whether components are bought, crafted, or provided.
  * **Bags**: Browse auctionable inventory grouped by bag container with market price recommendations for 1-click posting.
* **Crafting & Materials Choices**: Double-wide (832x480) 3-column crafting workstation providing hierarchical recipe breakdowns, ground-up material calculations, customer craft attribution, and shopping plan exports.
* **Share Verified Scans**: Compatible guild members automatically exchange compressed price observations in the background over hidden addon channels (`CHAT_MSG_ADDON`).
* **Keep Factions Separate**: Alliance and Horde maintain completely isolated saved prices, histories, alerts, and guild-sync markets.
* **Connect Across Forever Realm Shards**: Numbered backend realms within one playset share guild-sync data (e.g. `English 0` through `English 100+`, `ClassicBetaPvP1` through `ClassicBetaPvP100+`). PvP, PvE, RP, and HC stay separate; other clients retain exact realm matching.
* **Search a Whole Classic List**: The enhanced Classic Search page collects live price and stack groups for shopping lists and craft materials into one table, with source-page verification before buying.
* **Item Variant Fidelity**: Full scans track random-suffix items (e.g., *“of the Boar”*, *“of the Falcon”*) as distinct price records rather than flattening them into the base item.
* **Explore Analytics**: Inspect 30-minute bucket histories, daily/weekly price trends, scan age, and market breadth.
* **Check Prices from Chat**: Type `?` before an item link in supported party/raid/guild chat to request current market prices from online guildmates.

---

## Modular Configuration & Feature Status

MarketSync integrates directly into World of Warcraft's native AddOn Settings (`Settings.RegisterAddOnCategory` on 10.0+ and `InterfaceOptions_AddCategory` on Classic), organized into 8 clear settings cards:

1. **Performance & Memory Management**:
   * **Low RAM Mode (Default: ON)**: Drops search index caches and runs Lua garbage collection when windows close. Generates caches on-demand with live index footprint reporting.
   * **Pre-Build Search Index on Startup (Default: OFF)**: Optional early background indexing for high-memory systems.
   * **Cache Build Speed Slider**: 1 (Conservative) to 4 (Maximum) yielding rates.
2. **Professions & Crafting (Production Feature)**:
   * In-game TradeSkill window integration showing crafting costs, net profit margins (5% AH cut factored in), vendor reagent identification, and ground-up component trees.
3. **Auction House & Scanning**:
   * Scanner backend toggle (Native high-speed scanner vs. Auctionator scan import).
   * Tooltip price toggles, Expected Value (EV) for disenchanting/prospecting/milling, multi-character inventory counts, and details modifier key (`Shift`, `Ctrl`, or `Alt`).
4. **Audio & Notifications**:
   * Sound triggers with audio preview, custom sound IDs, volume slider, minimap flashing, and on-screen raid warning alerts.
5. **Data Sync & Swarm**:
   * Guild sync and neutral AH sync toggles, user blocking/unblocking manager, and smart rule bandwidth controls.
6. **Beta & Experimental Features**:
   * **Processing Tab**: Production-ready module near general release for recursive crafting solver, vendor arbitrage, and batch shopping lists.
   * **Price Alerts Tab**: Production-ready module near general release for threshold price triggers, watchlist monitoring, and raid alert delivery.
   * **Transactional Item Ledger (Auto-Disabled by Default)**: Experimental FIFO cost tracking, vendor/trade/mail auditing, and inventory reconciliation. Auto-disabled (`EnableLedgerBeta = false`) to ensure zero memory or CPU overhead. When disabled, all ledger UI buttons and shortcuts are gracefully dimmed, while lightweight multi-character inventory tooltips continue functioning.
7. **Window Theme**:
   * Dynamic switching between `Auto` (client version), `Forever` (dark bronze), and `Legacy` (parchment/slate).
8. **Debugging & Diagnostics**:
   * Network Monitor, Swarm activity, task execution diagnostics, and debug log output.

---

## Commands

| Command | Action |
| :--- | :--- |
| `/ms` or `/marketsync` | Toggle the main MarketSync window |
| `/ms craft` (or `/mscraft`, `/craftmanager`, `/crafts`) | Open Crafting & Materials Manager |
| `/ms sidecar` (or `/sidecar`, `/mssidecar`) | Toggle the AH Shopping & Bag Selling drawer |
| `/ms ledger` (or `/ledger`, `/msledger`) | Open Item Ledger (when Beta is enabled) |
| `/ms search` or `/ms browse` | Open the offline market browser |
| `/ms theme [forever\|legacy\|auto]` | Switch UI window styling |
| `/ms config` (or `/ms settings`, `/ms options`) | Open AddOn settings panel |
| `/ms block <player>` | Block a specific sync sender |
| `/ms unblock <player>` | Unblock a sync sender |

---

## Multi-Realm Sharding & Backend Scalability

Forever distributes single playsets across numbered backend shards (e.g., `English 0` through `English 100+`, `ClassicBetaPvP1` through `ClassicBetaPvP100+`).

MarketSync's normalizer (`MarketSync.NormalizeSyncRealm`) automatically identifies any trailing number (`%d+$`) preceded by spaces, hyphens, underscores, or hash signs and collapses them into a single canonical playset identifier (e.g. `english` or `classicbetapvp`).
* **Arbitrary Shard Count**: The regex pattern matching has no hardcoded upper bound at 100; it natively scales to 100, 200, 1,000+ sharded instances.
* **Safe Bandwidth**: Network traffic remains capped below 640 B/s via token bucket rate limiting and single-broadcaster election, ensuring guild communication remains smooth regardless of how many members or shards participate.
* **Faction Isolation**: All shard normalization strictly preserves faction boundaries (`@Horde` vs `@Alliance`), ensuring cross-faction data never leaks.

---

## Documentation & Developer Guides

Complete technical specifications and integration guides are indexed in the **[Documentation Hub](docs/README.md)**:

* **[Observation API Specification](docs/OBSERVATION_API.md)**  
  In-game, real-time event stream (`MarketSync.ObservationAPI.v1`) for companion addons (e.g. ForeverLedgerSync, uploaders, and trackers). Details lifecycle states, server time synchronization, and zero-lag asynchronous queueing.
* **[External Data Extraction & Web Import Guide](docs/DATA_EXTRACTION_GUIDE.md)**  
  Step-by-step guide for external websites, dashboards, and Discord bots to extract the full Auction House database directly from `WTF/.../SavedVariables/MarketSync.lua` using the browser File System Access API without downloading external software.
* **[Performance, Scaling & Architecture Guide](docs/PERFORMANCE_AND_SCALE.md)**  
  Technical analysis of how MarketSync handles 30,000+ item catalogs: two-stage frame-sliced scanning (`READ_BATCH_SIZE = 250`, `WRITE_BATCH_SIZE = 150`), network bandwidth rate limiting (< 800 B/s), coroutine-driven tiered retention downsampling, and 100+ realm sharding.
* **[Item Tracking & Ledger Architecture](docs/ITEM_TRACKING.md)**  
  Architecture of the Transactional Item Ledger and multi-character inventory tracking.
* **[Crafting Management Specification](docs/CRAFT_MANAGEMENT_PLAN.md)**  
  Detailed workflow and architecture for ground-up crafting calculations, purchase plans, and customer craft tracking.

---

## Scanning Modes

MarketSync operates with or without Auctionator:
* When **Auctionator is detected**, MarketSync uses Auctionator's full scan by default.
* You can switch to MarketSync's **native scanner** at any time under **Settings → Use Auctionator scanning**.
* Both scanners feed the same underlying database, tiered retention engine, and Observation API.

---

## Installation

1. Copy the packaged `MarketSync` directory into your World of Warcraft directory under `Interface/AddOns/`.
2. Enable MarketSync in the AddOn list on the character selection screen.
3. Open an auctioneer and run a scan to populate initial prices.

---

## License

MarketSync is free and open-source software licensed under the **GNU General Public License v3.0** (GPL-3.0). See [LICENSE](LICENSE) for details.
