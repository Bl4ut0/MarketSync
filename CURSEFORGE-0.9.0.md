# MarketSync 0.9.0 — Forever

This is the first Forever-focused MarketSync release. It targets **Forever 1.60.1 (build 69893)**. Processing and Alerts are included as **opt-in beta features**; they are disabled by default. Auctionator is optional.

## Highlights

- Scan with MarketSync alone, or use Auctionator's scanner when Auctionator is installed. MarketSync automatically selects Auctionator scanning on first detection; you can change the setting later.
- Browse separate personal, guild, and neutral-AH price views, with filters, sorting, and saved shopping lists.
- Explore recent scans and price history in Analytics. Scanned items are not automatically added to your shopping lists or alert targets.
- Preserve exact random-suffix item prices and history when a full scan provides the raw item links.
- Share verified scan data with compatible guild members through bounded, compressed synchronization. Incomplete transfers do not advance scan freshness.
- Refresh only changed personal Browse entries after Auctionator scan updates; validate item metadata in small batches without altering price history.
- Use the optional Processing beta for captured-recipe craft costs and supported disenchant value ranges, or the Alerts beta for auction-price thresholds.

## Important notes

- Install on Forever. Other WoW versions are not validated for this 0.9.0 release.
- If you use Auctionator, MarketSync's own Scanner tab is hidden by default. Change **Settings → Use Auctionator scanning** to use MarketSync's scanner instead.
- Open your profession windows once before using recipe-based Processing estimates. Missing market prices prevent a complete profit estimate.
- Disenchant probability tables have not been independently confirmed for Forever custom gear. Unsupported green item levels do not receive inferred TBC results.
- Existing SavedVariables and price history are retained. A fresh scan is needed to populate exact suffix prices that earlier scans did not record.

Please include your Forever build, whether Auctionator was enabled, and any Lua error when reporting a problem.
