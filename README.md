# MarketSync 0.9.2 — Forever

**Scan once. Share prices with your guild. Browse the market away from the Auction House.**

MarketSync is a Forever-first Auction House companion for saved prices, guild synchronization, item history, shopping lists, and analytics. Version 0.9.2 targets Forever 1.60.1 (build 69893). 

Auctionator is optional: MarketSync includes its own native, frame-sliced auction scanner, or can seamlessly capture Auctionator full scans when both addons are installed.

---

## What You Can Do

* **Browse Offline**: Search your personal scans, guild-synced prices, and neutral-AH data in separate views away from the auctioneer.
* **Share Verified Scans**: Compatible guild members automatically exchange compressed price observations in the background over hidden addon channels.
* **Item Variant Fidelity**: Full scans track random-suffix items (e.g., *“of the Boar”*, *“of the Falcon”*) as distinct price records rather than flattening them into the base item.
* **Explore Analytics**: Inspect 30-minute bucket histories, daily/weekly price trends, scan age, and market breadth.
* **Check Prices from Chat**: Type `?` before an item link in supported party/raid/guild chat to request current market prices from online guildmates.
* **Optional Beta Tools**:
  * **Processing**: Crafting cost profitability (single-tier and recursive ground-up recipes) and disenchant expected value calculators.
  * **Alerts**: Configurable price threshold alerts with session-level minimap muting.

---

## Documentation & Developer Guides

Complete technical specifications and integration guides are indexed in the **[Documentation Hub](docs/README.md)**:

* **[Observation API Specification](docs/OBSERVATION_API.md)**  
  In-game, real-time event stream (`MarketSync.ObservationAPI.v1`) for companion addons (e.g. ForeverLedgerSync, uploaders, and trackers). Details lifecycle states, server time synchronization, and zero-lag asynchronous queueing.
* **[External Data Extraction & Web Import Guide](docs/DATA_EXTRACTION_GUIDE.md)**  
  Step-by-step guide for external websites, dashboards, and Discord bots to extract the full Auction House database directly from `WTF/.../SavedVariables/MarketSync.lua` using the browser File System Access API without downloading external software.
* **[Performance, Scaling & Architecture Guide](docs/PERFORMANCE_AND_SCALE.md)**  
  Technical analysis of how MarketSync handles 30,000+ item catalogs: two-stage frame-sliced scanning (`READ_BATCH_SIZE = 250`, `WRITE_BATCH_SIZE = 150`), network bandwidth rate limiting (< 800 B/s), and coroutine-driven tiered retention downsampling (Hot/Warm/Cold/Purge).

---

## Commands

| Command | Action |
| :--- | :--- |
| `/ms search` or `/ms browse` | Open the offline market browser |
| `/ms config` | Open MarketSync settings |
| `/ms block <player>` | Block a specific sync sender |
| `/ms unblock <player>` | Unblock a sync sender |

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
