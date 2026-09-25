# MarketSync

**Scan once. Share prices with your guild. Browse the market away from the Auction House.**

MarketSync is a Forever-first Auction House companion for saved prices, guild synchronization, item history, and shopping lists. Version 0.9.0 targets Forever 1.60.1 (build 69893). Auctionator is optional: MarketSync can scan on its own, or use Auctionator's scans when both addons are installed.

## What you can do

- **Browse offline:** Search your personal scans, guild-synced prices, and neutral-AH data in separate views. Filters and sorting help narrow large scan databases.
- **Share verified scans:** Compatible guild members exchange compressed price observations in the background. Incomplete transfers do not replace a completed scan, and neutral-AH data stays separate from the main market.
- **Explore Analytics:** See recent scanned items, select a saved shopping list, and inspect item price history and scan age. Scanning does *not* automatically add an item to a shopping list or an alert watchlist.
- **Keep item variants distinct:** Full scans retain separate prices and history for random-suffix items when exact suffix data is available.
- **Check prices from chat:** Use a `?` before an item link in supported group chat to request a known price from guild members with compatible MarketSync data.
- **Use optional beta tools:** Enable Processing for craft-cost and supported disenchant-value estimates, or Alerts for item-price thresholds. Both tabs are off by default in Settings.

## Scanning with or without Auctionator

MarketSync works without Auctionator. When Auctionator is detected, MarketSync uses Auctionator scanning by default and hides its duplicate Scanner tab. You can switch back to MarketSync's native scanner under **Settings → Use Auctionator scanning**. Both modes feed MarketSync's saved prices and history; a scan's results are observations, not a guarantee that an auction is still available later.

## Getting started

1. Install MarketSync in the Forever client's `Interface/AddOns` folder and enable it at the character screen.
2. Open an auctioneer and run a full scan with the active scanner.
3. Open MarketSync from its minimap button or use `/ms search` to browse your saved data.
4. Use **Settings** to enable the Processing or Alerts beta tabs if you want to test them. Open each profession window once so Processing can discover that character's recipes.

Your scan database is stored in WoW SavedVariables. It is local to your installation; guild sync requires other compatible MarketSync users online and does not upload data to an external cloud service.

## Beta-feature notes

Processing estimates profit from known recipes and available prices. It does not invent prices for missing reagents. Disenchant low/high values are possible outcomes, not guaranteed returns or confidence intervals. The bundled legacy disenchant odds have **not** been independently validated for Forever custom gear, and unsupported green item levels do not inherit TBC odds.

Alerts trigger on configured price thresholds. **Shift-Left-Click** the minimap button to mute alert delivery until logout or until you use the shortcut again; the first mute asks for confirmation.

Version 0.9.0 targets Forever. Metadata for other WoW interface versions remains in the addon, but this release has not been validated on those clients. Please report the client build, scanner mode, reproduction steps, and any Lua error when filing a bug.

## Commands

| Command | Action |
| --- | --- |
| `/ms search` or `/ms browse` | Open the browse window |
| `/ms config` | Open settings |
| `/ms block <name>` | Block a sync sender |
| `/ms unblock <name>` | Unblock a sync sender |

MarketSync is licensed under GPL-3.0.
