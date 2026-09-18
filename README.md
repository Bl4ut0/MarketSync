# MarketSync Forever native scanner prototype

**Built for an initial test of Forever beta 1.60.1 (69893).** This separate addon records native auction searches, refreshes a small watch list, and provides a draggable saved-price window. It requires neither Auctionator nor the existing MarketSync addon. The original MarketSync worktree and installed addons are unchanged.

**0.2.0 adds a MarketSync launcher beside Blizzard's auction-house tabs.** It opens the same portable window; the embedded alert/settings panel and full guild integration are later stages. The source track contains an [implementation guide](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/MarketSync-Forever/IMPLEMENTATION_GUIDE.md) and a [restart checklist/pasteable handoff](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/MarketSync-Forever/RESUME.md). Those development guides are stored with the source, outside the client ZIP.

The native Forever interface already covers grouped browsing, commodity quantity selection, buying, posting, and viewing your auctions. MarketSync can concentrate on collecting observations, preserving their identity and history, and displaying them away from an auctioneer.

## Initial test package

The draft TOC deliberately uses **11509 as an older Classic Era baseline**, not a claimed Forever Interface number. The screenshot establishes version/build, not the fourth `GetBuildInfo()` value. This draft requires **Load out of date AddOns** if it appears outdated. The `camelot` game-type gates follow the beta export's syntax and still require native confirmation. The runtime capture guard additionally requires the observed `1.60.1 (69893)` build and the modern `AuctionHouseFrame`.

1. Close the beta. Extract `MarketSyncForeverScanner` into `_classic_beta_\Interface\AddOns\`. The generated ZIP contains one addon folder, its documentation, and license.
2. Start the beta, enable this addon, and enable **Load out of date AddOns** for the draft if needed. Enable errors using `/console scriptErrors 1`.
3. After login, run `/msf report`. This prints the actual Interface number and saves diagnostics on logout. An absent modern frame before visiting an auctioneer is expected.
4. Open an auctioneer. Browse/search with Blizzard's interface, then open individual commodity and equipment listings. The scanner records those native results without initiating purchases or listings.
5. Click **MarketSync** beside the native tabs or run `/msf` to open the portable window. The launcher leaves the native tab selection unchanged and repeated clicks keep the window open. Use `+` beside an item to watch its exact native key. Select **Refresh watched** while the auctioneer is open. The list is limited to **50 keys** and requests are at least **1.1 seconds apart**, also waiting for native throttle readiness. Ordinary native searches stop the watch queue.
6. Close the auctioneer and open `/msf` again elsewhere. Saved prices, result quantities, observation ages, coverage, price depth, and recent complete observations remain available. Quantities are observations at their stated time.
7. Reload/relog and confirm persistence. Data is in `MarketSyncForeverScanDB` in the account's beta `SavedVariables\MarketSyncForeverScanner.lua`. Its schema is independent of `MarketSyncDB` and Auctionator's stores.

**Main / Neutral** selects separate, manually classified stores. Close the auctioneer before changing this bucket, then choose the appropriate store before collecting observations. This prevents outstanding responses crossing stores during an open session. The prototype does not infer neutral/shared/commodity market topology from Retail behavior. The initial partition includes product, region, realm, faction, and selected bucket; this is conservative separation until the actual server topology is verified.

Commands: `/msf` or `/msforever` opens the window; `/msf report` prints diagnostics; `/msf scan` refreshes watched keys; `/msf stop` stops the queue.

To replace draft metadata after observing the real Interface number:

```powershell
python .\MarketSync-Forever\tools\package.py --output .\outputs\MarketSync-Forever-interface-test.zip --interface NUMBER
```

The builder labels a supplied number as supplied for local testing, not validated in the client. It refuses the known build ID `69893` as an Interface number. New beta builds need their API/loader contracts checked and the runtime target updated before capture is enabled.

## What this prototype establishes

- Native `itemID`, `itemLevel`, `itemSuffix`, and `battlePetSpeciesID` form each price key. Native commodity metadata comes from `GetItemKeyInfo`; `GetItemCommodityStatus` takes an **ItemLocation**, not an item ID.
- Browse observations retain the native advertised price and query quantity but are always marked **partial**. Item/commodity detail results are complete only when the native completeness flag is true and their row data is available.
- `GetNum*SearchResults` counts rows; `Get*SearchResultsQuantity` measures units. Ordinary item buyout totals are divided by stack quantity. Bid-only rows do not become buyout quotes. Other item variants do not enter the key's price summary.
- A partial refresh retains the previous complete snapshot. A timeout or cancelled watch scan does not advance completed-watch freshness. Complete empty results record zero availability and no buyout quote.
- History keeps up to **96 observed 30-minute buckets** per key. This is a bounded history of observations, not an assertion that every interval was scanned. Price depth keeps up to 20 levels.
- The window uses the beta's existing basic frame and button templates, with categories, saved search, watched items, prices, result quantities, observation age/coverage, and a detail pane. Its actual layout still needs native visual testing.
- No auction transaction, addon-message, or chat-message API is called. No legacy price globals are rewritten.

## MarketSync integration after the native test

Current local MarketSync is `0.8.0-rc2`, based on commit `33107fc` with uncommitted changes. It declares Auctionator as a required dependency and uses Auctionator price/age helpers, scan epoch, private database hooks, personal/neutral capture, and shopping-list exports. Making that dependency optional alone is insufficient.

The prototype exposes `MarketSyncForeverScanner.Provider` with `name`, `schema`, `GetMarketID()`, and `GetSnapshot(nativeItemKey)`. `GetSnapshot` returns a copy of the latest complete snapshot, including source, observation time, coverage, unit price, available/priced quantities, and bounded depth. It returns nil when only partial browse data exists.

Integrate through a provider boundary in MarketSync's price helpers and personal capture, then adapt offline browsing/history to provider-native keys. Keep Classic/Retail's existing Auctionator provider. Give Forever its own market identity and protocol compatibility rules. A successful watched-item refresh must not be advertised as a complete market snapshot; receiving/importing it must preserve per-item completeness and timestamps. Neutral detection, scan attribution, chat lookups, crafting prices, shopping-list exports, and the wire encoder/decoder need provider-aware tests before guild transfers are enabled.

## Full-market scans

Full-market replication is **not implemented in this first test**. The exported `SendSearchQuery` documentation specifies **100 calls/minute** and says item searches should not query the entire auction house. A crawl through every item would be the wrong full-market implementation.

`ReplicateItems` is documented and the diagnostic report records its presence. A separate manual replication probe must establish that Forever actually returns data, its cooldown/error behavior, row completeness, commodity quantity semantics, and variant identity. Only then should a staged full-snapshot importer commit personal data and mark a market scan complete. Request errors, missing data, leaving the auctioneer, and stale callbacks must retain the previous complete market snapshot. Automatic scans remain a later integration choice.

## Validation

Run from the shared workspace:

```powershell
node .\MarketSync-Forever\tests\runtime.js
python .\MarketSync-Forever\tools\validate_contract.py --blizzard 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\BlizzardInterfaceCode\Interface\AddOns'
python -m unittest discover -s .\MarketSync-Forever\tests -p 'test_*.py' -v
```

The runtime harness uses the existing Lua parser/Fengari development dependencies in `../ItemRack-Forever/node_modules`. There is no in-game dependency on ItemRack. Mock tests establish local lifecycle/calculation behavior; they do not establish server availability, native event order, loader acceptance, market topology, restrictions, or visual layout.

The 0.2.0 checkpoint passes **23 runtime cases**, four packaging tests, and Lua 5.1 parsing for five production modules. Contract checks cover 16 referenced auction functions, 13 registered events, and the physical window/tab templates. Runtime tests include late AH addon loading, a single launcher across reopen events, native selection preservation, and the portable window remaining open after auctioneer closure.

## Auctionator research

Checked September 17, 2026. [Auctionator's official project listing](https://www.curseforge.com/wow/addons/auctionator) shows release **336**, updated September 13, and Retail, MoP Classic, Titan Reforged Classic, Classic, and Classic TBC support. I did not find a verified Forever-specific release in the official listings/searches. That does not establish that no experimental build exists.

The installed 336 package contains both modern and legacy auction-house implementations. Forever's modern UI makes its modern implementation the more relevant comparison, but matching the UI does not establish addon loader support or identical server behavior. The independent scanner now has priority over the unbuilt adapter scaffolding in `../Auctionator-Forever`.

License: GPL-3.0-or-later; see `LICENSE`. This prototype contains original code and native API calls, not Auctionator's implementation.
