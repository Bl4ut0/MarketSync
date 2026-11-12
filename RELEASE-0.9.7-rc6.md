# MarketSync 0.9.7-rc6

Release candidate for Forever 1.60.1 (Interface 16001), Classic Era / SoD 1.15.9, and TBC 2.5.6. Auctionator is optional.

## Authentic Blizzard Interface Reskin

- **Crafting & Materials Manager (`MarketSyncCraftManager`)**:
  - Re-architected with Blizzard's authentic `PortraitFrameTemplate`, featuring NineSlice frame borders, round metallic portrait ring with blacksmithing hammer emblem, title bar, and native close button.
  - Balanced 3-column workflow within standard 832x480 double-wide panel dimensions: Left column for Craft Management & Queue, middle column for hierarchical Recipe Breakdown Tree, and right column for the calculated Purchase Plan.
  - Integrated preset strategy buttons (`Optimal`, `Buy Finished`, `Craft All Raw`, `Customer Craft`) and docked bottom tabs (`Materials & Planning`, `Craft History`).
- **Auction House Breakout Sidecar Dual-Theme**:
  - Reskinned the breakout drawer (`MarketSyncAHSidecarFrame`) with authentic Blizzard dialog textures and dynamic theme detection.
  - **Forever / Modern (`_forever_`, `_retail_`)**: Dark bronze theme with Blizzard `UI-DialogBox-Background-Dark`, authentic `UI-DialogBox-Border`, amber-gold header accents, and bronze tab framing.
  - **Legacy / Classic Era (`_classic_`, `_classic_era_`)**: Authentic parchment / slate theme with `UI-DialogBox-Background`, silver/slate borders, and slate header accents.

## Unified Slash Command System

- Running `/ms` or `/marketsync` with no arguments now toggles the main MarketSync window instead of only printing help text.
- Added dedicated subcommands:
  - `/ms craft` (or `/ms crafting`, `/ms crafts`, `/ms mats`) — opens/toggles the Crafting & Materials Manager.
  - `/ms sidecar` (or `/ms drawer`, `/ms breakout`) — toggles the AH shopping and bag selling drawer.
  - `/ms ledger` (or `/ms items`) — opens the Item Ledger when enabled.
  - `/ms theme [forever|legacy|auto]` — changes UI theme dynamically.
  - `/ms config` (or `/ms settings`, `/ms options`) — opens the AddOn settings panel.
- Registered standalone slash commands: `/mscraft`, `/craftmanager`, `/crafts`, `/sidecar`, `/mssidecar`, `/ledger`, `/msledger`.

## Modular Configuration & Feature Status

- Integrated with WoW's native canvas settings panel (`Settings.RegisterAddOnCategory` on 10.0+ and `InterfaceOptions_AddCategory` on Classic), organized into 8 distinct settings cards.
- **Processing and Price Alerts Tabs**: Positioned as stable, production-ready modules nearing core release for day-to-day profit calculation and price threshold monitoring.
- **Transactional Item Ledger Beta Auto-Disabled**: `EnableLedgerBeta` defaults to `false` (`MarketSyncDB.EnableLedgerBeta = false`) to ensure zero memory or CPU overhead for users not testing the experimental FIFO ledger.
- When the Ledger Beta is disabled, all UI entry points (MainFrame title bar button, Craft Manager header button, row context menu option, and minimap icon shortcuts) are gracefully dimmed and disabled. Lightweight multi-character bag/bank tracking remains active for tooltips.

## Multi-Realm Sharding & Playset Scalability (100+ Backend Realms)

- Validated and documented backend realm sharding in `MarketSync.NormalizeSyncRealm`:
  - Automatically strips trailing shard numbers (`0` through `100+`) preceded by spaces, hyphens, underscores, or hash signs (e.g. `English 52`, `English-52`, `English 0`, `English 100`, `ClassicBetaPvP2`).
  - Pattern matching `%d+$` natively supports arbitrary integers with no ceiling at 100, folding all sharded instances into a single canonical playset for guild-sync communication.
  - Faction boundaries (`@Horde` / `@Alliance`) remain strictly isolated across all sharded realms.

## Upgrading and Testing

1. Deploy the release candidate to your client installations.
2. Type `/reload` in-game to apply the updated interface and slash commands.
3. Test opening the Crafting Manager via `/ms craft` or `/mscraft`.
4. Open the Auction House and expand the breakout drawer via the tab or `/ms sidecar`.
5. Check AddOn Settings under Game Menu → Options → AddOns → MarketSync.
