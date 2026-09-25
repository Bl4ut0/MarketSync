# MarketSync 0.9.2 — Forever

MarketSync is a Forever-first Auction House addon for scans, price history, guild and neutral-AH synchronization, saved shopping lists, and item analytics. Auctionator is optional. If it is installed, MarketSync uses its scan updates by default and its own scanner can be re-enabled in Settings. Processing and Alerts are opt-in beta tabs; Analytics is enabled by default.

For external price sites, web dashboards, or Discord bots, see the **[Data Extraction & Web Import Guide](docs/DATA_EXTRACTION_GUIDE.md)** for importing the complete scan database (2,000 to 30,000+ items and history) directly from the game's SavedVariables file with zero software downloads via the browser File System Access API, drag-and-drop, or lightweight scripts.

Companion addons (ledgers, uploaders, and external trackers) can subscribe to real-time scan observations directly in memory. See the [MarketSync Observation API Guide](docs/OBSERVATION_API.md) for the event schema, lifecycle states, and timestamp precision rules.

For architecture, benchmarks, and safeguards scaling to 30,000+ items (frame-sliced batching, network bandwidth throttling, and tiered retention downsampling), see the **[Performance, Scaling & Architecture Guide](docs/PERFORMANCE_AND_SCALE.md)**. All guides and technical specifications are indexed in the **[Documentation Hub](docs/README.md)**.

Install the packaged `MarketSync` folder under the Forever client's `Interface/AddOns` directory. Open an auctioneer to scan, or use the MarketSync tabs to browse saved prices and history. Open each profession window once before expecting its known recipes to appear in Processing. The current release targets Forever 1.60.1 (build 69893); other game versions have not been validated for this release.

The sections below include technical details and historical notes from the separate native-scanner prototype. They are retained for development context, not as installation instructions for 0.9.2.

## Current MarketSync Forever processing work

The `MarketSync` addon is being completed for Forever first; older-client behavior remains in the codebase but is not the current feature target. Its Processing tab now offers an `ALL` profession view. Craft profitability uses only recipes captured from the current character's profession window, so open each profession window once (or resync it) before expecting its recipes to appear. Recipes or materials without complete auction pricing do not receive a profit estimate.

Disenchant processing uses item quality, item level, and weapon/armor class from the scanned item metadata. For every supported probability row it shows possible outputs, low/expected/high net material value, and low/expected/high profit after buying the item. The expected value is the sum of each outcome's probability times quantity times material price, with a 5% main-auction sale cut. The low and high figures are possible single-disenchant outcomes, **not confidence bounds**. The row is marked partial and no range is shown when a possible output has no price. The bundled legacy odds have not been independently validated for Forever custom gear; unsupported higher-level green items must not inherit TBC material odds. A fresh scan is needed to populate metadata for items scanned before this update.

Full Auction House scans keep random-suffix variants (such as “of the Boar”) as separate price records instead of folding them into the base item. Variant keys are preserved in guild transfers, so each suffix can be browsed and priced independently. This higher-fidelity history uses more SavedVariables space and increases the amount of data available to sync.
Earlier scans that stored only a base item ID cannot be split into suffix variants retroactively; run a new full scan to populate those prices.

Retention applies to each variant key independently: recent history keeps one observation per 30-minute bucket for seven days and is eligible for guild sync; days 8–30 become local daily summaries; days 31–180 become local weekly summaries. Repeated scans in the same bucket replace that variant's previous point, and fully expired variant records are removed without affecting other suffixes or the base item. Analytics reads the same exact variant key through all three history tiers. Retention runs after login and daily during a long session.

Alerts remain item-specific auction-price thresholds. Shift-Left-Click the MarketSync minimap button to mute all alert delivery for the current session; the first use asks for confirmation, and the same shortcut restores alerts. Mute state is not saved across logout or reload. Existing threshold requests are left intact while muted.

The remainder of this README documents the earlier standalone `MarketSyncForeverScanner` prototype and should be read as historical implementation context, not as the current MarketSync feature list.

**Built for an initial test of Forever beta 1.60.1 (69893).** This separate addon records native auction searches, refreshes a small watch list, and provides a draggable saved-price window. It requires neither Auctionator nor the existing MarketSync addon. The original MarketSync worktree and installed addons are unchanged.

**0.3.0 embeds a MarketSync control panel directly beside Blizzard's auction-house tabs.** It uses Blizzard's `SetDisplayMode` and `AuctionHouseFrameTabTemplate` while sharing a unified browser (`Browser.lua`) with the portable portrait window. The repository contains an [implementation guide](docs/archive/IMPLEMENTATION_GUIDE.md) and a [restart checklist/pasteable handoff](docs/archive/RESUME.md). Those development guides are preserved in `docs/archive/`, outside the client ZIP.

The native Forever interface already covers grouped browsing, commodity quantity selection, buying, posting, and viewing your auctions. MarketSync can concentrate on collecting observations, preserving their identity and history, and displaying them away from an auctioneer.

## Initial test package

The draft TOC deliberately uses **11509 as an older Classic Era baseline**, not a claimed Forever Interface number. The screenshot establishes version/build, not the fourth `GetBuildInfo()` value. This draft requires **Load out of date AddOns** if it appears outdated. The `camelot` game-type gates follow the beta export's syntax and still require native confirmation. The runtime capture guard additionally requires the observed `1.60.1 (69893)` build and the modern `AuctionHouseFrame`.

1. Close the beta. Extract `MarketSyncForeverScanner` into `_classic_beta_\Interface\AddOns\`. The generated ZIP contains one addon folder, its documentation, and license.
2. Start the beta, enable this addon, and enable **Load out of date AddOns** for the draft if needed. Enable errors using `/console scriptErrors 1`.
3. After login, run `/msf report`. This prints the actual Interface number and saves diagnostics on logout. An absent modern frame before visiting an auctioneer is expected.
4. Open an auctioneer. Browse/search with Blizzard's interface, then open individual commodity and equipment listings. The scanner records those native results without initiating purchases or listings.
5. Click **MarketSync** beside the native tabs to display the embedded MarketSync browser pane, or run `/msf` to open the portable window. Both views share watched keys, price records, and scanning state. Use `+` beside an item to watch its exact native key. Select **Refresh watched** while the auctioneer is open. The list is limited to **50 keys** and requests are at least **1.1 seconds apart**, also waiting for native throttle readiness. Ordinary native searches stop the watch queue.
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

Historical note: the older `0.8.0-rc2` MarketSync build required Auctionator. The current 0.9.2 Forever build uses an optional provider boundary and can run without Auctionator.

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

The 0.3.0 checkpoint passes **29 runtime cases**, four packaging tests, and Lua 5.1 parsing for six production modules. Contract checks cover 16 referenced auction functions, 13 registered events, and the physical window/tab templates. Runtime tests include late AH addon loading, a single launcher across reopen events, native selection preservation, and the portable window remaining open after auctioneer closure.

## Auctionator research

Checked September 17, 2026. [Auctionator's official project listing](https://www.curseforge.com/wow/addons/auctionator) shows release **336**, updated September 13, and Retail, MoP Classic, Titan Reforged Classic, Classic, and Classic TBC support. I did not find a verified Forever-specific release in the official listings/searches. That does not establish that no experimental build exists.

The installed 336 package contains both modern and legacy auction-house implementations. Forever's modern UI makes its modern implementation the more relevant comparison, but matching the UI does not establish addon loader support or identical server behavior. The independent scanner now has priority over the unbuilt adapter scaffolding in `../Auctionator-Forever`.

License: GPL-3.0-or-later; see `LICENSE`. This prototype contains original code and native API calls, not Auctionator's implementation.
