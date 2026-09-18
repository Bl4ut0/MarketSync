# MarketSync Forever implementation guide

Checkpoint date: September 17, 2026. Target observed in the client: **1.60.1 (69893), Beta x64**. The exact Interface number and native acceptance are pending. This plan is saved locally so work can resume after a week away.

## Agreed destination

MarketSync will collect prices through Forever's native auction APIs and offer two ways to use the same records and settings:

| Surface | Intended use |
| --- | --- |
| **MarketSync tab at the auctioneer** | Watch-list setup, explicit refresh/stop controls, scan progress, alert setup, source selection, and an entry to guild synchronization. |
| **Portable window** | Personal Scan, Guild Sync, and Neutral AH views; saved search, price/quantity history, freshness, and alert configuration away from the auctioneer. |

Keep the existing Processing, Notifications, and Settings features during the full addon migration. Blizzard's Buy, Sell, and Auctions tabs continue to handle transactions. Refreshed auction prices require an open auctioneer; viewing saved prices and editing rules can work anywhere. Guild observations retain their original observation time when received.

## What exists at this checkpoint

| Milestone | State |
| --- | --- |
| Native browse/detail capture, watched-key refresh, portable saved-price window | Implemented in the standalone scanner. |
| MarketSync control beside the native auction tabs | Implemented as a **launcher for the portable window** in 0.2.0. It is not an embedded settings panel. |
| Separate Main/Neutral stores | Implemented with manual classification. The auctioneer must be closed to change the selected store. |
| Provider export for complete item observations | Implemented; the full MarketSync addon does not consume it yet. |
| Embedded AH control panel and dedicated Personal/Guild/Neutral portable tabs | Planned. |
| Existing MarketSync notifications/alerts, processing, chat lookup, and guild protocol on native data | Planned. |
| Full-market replication | Planned probe; runtime availability is unverified. |
| Client install, native layout/event/loader acceptance | Pending. No beta addon installation was performed. |

The 0.2.0 entry uses `AuctionHouseFrameTabTemplate`, is parented to `AuctionHouseFrame`, and attaches after the native addon loads or an auctioneer opens. Clicking it opens the existing window without changing Blizzard's selected tab or initiating a scan. It is an initial access point for the later embedded controls.

## Working locations and source preservation

- Development track: `C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20\MarketSync-Forever`.
- Original addon: `C:\Dev Projects\MarketSync`, version `0.8.0-rc2`, with uncommitted changes on top of `33107fcb3f04d5a267e40865e166b30bf47db58b` (`Release v0.7.0`). Preserve those changes.
- Native export: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\BlizzardInterfaceCode\Interface\AddOns`.
- Test packages, logs, manifests, and previous audits: the workspace's `outputs` directory.

For the full integration, first copy the **current working-tree** `MarketSync` addon directory, project license, and required development tooling into a separate workspace track. Record source file hashes and the original Git status. A clone from the release commit alone would omit the rc2 changes. Exclude the original `.git`, embedded `.Auctionator`/`.BlizzardInterfaceCode`, old archives, private configuration, and generated dependencies. Do not apply native scanner data to the original `MarketSyncDB` during development.

## Stage 1 — accept the standalone scanner in the native client

- [x] Original scanner and portable window implemented.
- [x] Auction-house launcher implemented with late-load and duplicate-entry coverage.
- [x] Local Lua/runtime/package/contract checks pass.
- [ ] When login is possible, capture `/msf report` and the fourth `GetBuildInfo()` return value.
- [ ] Confirm the `camelot` loader filters actually accept the addon.
- [ ] Test the checklist below and record the actual client build used.

The screenshot's **69893 is a build ID**, not the Interface number. Draft `11509` is an explicitly unverified older Classic Era baseline. Do not infer a Forever TOC number from `1.60.1`.

Useful offline work while native access is unavailable: provider extraction, isolated source preparation, portable view models, alert-rule persistence, and encoder/decoder fixtures. Native acceptance remains a separate gate for enabling those features in the client.

## Stage 2 — add a provider boundary to the full MarketSync addon

- [ ] Preserve the rc2 working tree in the separate integration track.
- [ ] Put existing Auctionator behavior behind a provider for clients that already use it.
- [ ] Add a Forever provider using the scanner's `GetMarketID()` and `GetSnapshot(nativeItemKey)` contract.
- [ ] Replace direct price/age and scan-completion assumptions before changing the required Auctionator dependency.
- [ ] Review `Config.lua`, `Core.lua`, `Neutral.lua`, `Chat.lua`, `Processing.lua`, `Notifications.lua`, `Sync.lua`, and the portable UI modules.

Current coupling includes `GetAuctionPrice`/`GetAuctionAge`, Auctionator-relative scan buckets, private `SetPrice`/`ProcessScan` hooks, scan-complete notifications, neutral capture, and shopping-list imports/exports. Making the TOC dependency optional alone leaves those paths unported.

The existing scanner provider returns copies of **complete per-key** observations. Its snapshot contains `seenAt` (Unix seconds), `marketID`, `source`, `coverage`, `complete`, `minUnitPrice`, `available`, `pricedQuantity`, `priceLevels`, and client metadata. Browse-only observations have a separate advertised price and are not complete quotes. A complete empty result has zero availability and no buyout price.

Normalize item links to native keys without dropping `itemLevel`, `itemSuffix`, or `battlePetSpeciesID`. Define a deliberate rule for item-ID-only requests with multiple variants; do not silently substitute one variant's price. Native time buckets are Unix 30-minute buckets and must not be reinterpreted as Auctionator-relative buckets.

Acceptance: existing client/provider behavior remains valid; Forever runs without Auctionator; missing, partial, stale, or wrong-variant data cannot produce a fresh usable quote; receiving guild data cannot overwrite a personal observation.

## Stage 3 — restore the portable views and build the embedded AH panel

- [ ] Add source-aware view models for **Personal Scan**, **Guild Sync**, and **Neutral AH**.
- [ ] Make the portable and auctioneer panels use the same watch list, saved rules, selected market, and scanner state.
- [ ] Build an embedded AH panel for watch-list management, scan/stop, progress, source selection, and alert setup.
- [ ] Replace the launcher's click behavior only after the embedded panel's show/hide/selection lifecycle is covered.
- [ ] Retain a separate command/button that opens the portable window, even while the AH panel is active.

Blizzard's exported `SetDisplayMode` controls subframes and Buy/Sell/Auctions selection. Inspect that contract again for the installed build before extending the panel controller. Keep tab IDs, native titles, and visibility changes in one integration module. Test moving between every native tab and MarketSync, reopening, closing mid-refresh, Escape, and another addon adding a tab. Avoid relying on a tab template alone as proof of a supported extension API.

Acceptance: editing a watch/rule from either surface is reflected in the other; the portable window remains usable after the auctioneer closes; native transaction dialogs and posting behavior still work; Guild Sync controls accurately show their capability state before transfer is enabled.

## Stage 4 — migrate alerts and related consumers

- [ ] Port Notifications rule persistence and evaluation to provider observations.
- [ ] Give rules an explicit market, native key, data source, threshold/quantity condition, and freshness limit.
- [ ] Record the observation identity used for an alert to suppress duplicates on reread/reload.
- [ ] Test personal, guild, and neutral rule isolation, partial results, stale records, bid-only rows, empty results, repeated updates, and missing item metadata.
- [ ] Adapt processing/crafting costs, chat lookups, and import/export controls to the selected provider.

An alert may use a complete observation that meets its source/freshness rule. Receiving an old guild observation does not refresh its `seenAt`. A partial browse hint must not trigger a fresh-price alert. Configuration can be edited while offline; evaluating cached data does not establish current auction availability. Shopping-list controls need a native implementation or an accurate disabled state when their provider does not support them.

Acceptance: existing notification rules are migrated deliberately with a reversible schema change; the chosen personal/guild/neutral source and age are visible; unsupported consumers do not call absent Auctionator globals.

## Stage 5 — establish full-market scan availability

- [ ] Implement a separate, explicit `ReplicateItems` probe with runtime diagnostics when the server is accessible.
- [ ] Record successful/failed response events, cooldown, row cache completeness, commodities, quantities, and variant fields.
- [ ] If usable, import into staging storage and commit a complete market snapshot atomically.
- [ ] Invalidate pending work on closure, timeout, error, or a new generation; keep the previous complete snapshot.

The exported documentation includes replication, but it does not establish Forever server behavior. Do not implement a whole-market item-search crawl. `SendSearchQuery` documentation specifies 100 calls/minute and discourages querying the whole AH through item searches. The current explicit watch queue is limited to 50 keys and waits at least 1.1 seconds between requests plus native readiness.

If replication is unavailable, ship observed/watched-key scanning with accurate coverage labels. That need not prevent a protocol designed to exchange per-key observations. It must prevent claims of a completed full-market scan and any dependent whole-market freshness counter.

## Stage 6 — migrate guild and neutral synchronization

- [ ] Version the Forever protocol and declare compatible product, schema, epoch, and coverage semantics.
- [ ] Encode all native key fields, original `seenAt`, market identity, completeness, price/quantity semantics, and attribution.
- [ ] Keep personal observations, guild observations, and neutral observations distinct; retain sender/source metadata on guild records.
- [ ] Reject incompatible products, malformed/oversized payloads, implausible timestamps, unknown schemas, wrong-market records, and incomplete snapshot commits.
- [ ] Exercise encoder/decoder and merger fixtures before enabling a real transfer.
- [ ] Test with two participating clients after native scanner acceptance.

The current conservative market identity is product + region + realm + faction + manual Main/Neutral bucket. Verify actual Forever market topology before merging any partitions, including commodities. Existing Retail/Classic peers must not accept native keys or Unix buckets as their old wire format. Explicit per-key/watch coverage and verified full-market completion are separate protocol facts.

Acceptance: an old or duplicate packet cannot make data newer; a guild observation does not replace the user's own scan; neutral data never enters the main-market view; partial transfers cannot advance full-scan freshness.

## Stage 7 — native acceptance and promotion

- [ ] Capture build/Interface/project ID and save diagnostics with the test date.
- [ ] Confirm watch, browse, ordinary item, commodity, partial-cache, empty-result, close/reopen, persistence, and manual market-switch behavior.
- [ ] Check layout at the user's UI scale and coexistence with their other addons.
- [ ] Confirm source-aware alerts and two-client sync only after those stages are implemented.
- [ ] Commit the tested source and export a fresh package with manifest and SHA-256.

Keep the old standalone draft and original SavedVariables for comparison. A supplied Interface number is metadata for local testing; promotion requires actual loader/server/UI acceptance. New beta builds need their exported API/UI contracts checked and the strict runtime build guard updated before capture is enabled.

## Standalone 0.2.0 native checklist

1. Close the beta; extract the draft's single `MarketSyncForeverScanner` directory into `_classic_beta_\Interface\AddOns\` when ready to test.
2. Enable the addon and **Load out of date AddOns** if needed; use `/console scriptErrors 1`.
3. After login, run `/msf report`. If the addon cannot load, `/run local v,b,d,t=GetBuildInfo(); print(v,b,t,WOW_PROJECT_ID)` obtains the client values independently.
4. Open an auctioneer and verify one **MarketSync** entry beside Buy/Sell/Auctions. Clicking repeatedly should keep the portable window open and leave the native selected tab unchanged.
5. Search/open an ordinary item and a commodity in Blizzard's UI. Verify captured variant, unit price, result quantity, age, and coverage in `/msf`.
6. Watch a few saved keys with `+`, explicitly click **Refresh watched**, then try a native search and leaving the auctioneer during refresh. Confirm cancellation retains earlier complete records.
7. Close the auctioneer; the portable window and saved data should remain available, while refresh requires an auctioneer.
8. With the auctioneer closed, switch Main/Neutral and confirm isolated records/watch lists; a switch during an open session must be refused.
9. Reload/relog and check persistence in `MarketSyncForeverScanDB`. Record errors, diagnostics, screenshots, and the action that triggered a failure.

Mock tests do not prove native loader acceptance, actual server events, taint/protected behavior, market topology, or visual layout.

## Local commands

Run from `C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20`:

```powershell
node .\MarketSync-Forever\tests\runtime.js
python -m unittest discover -s .\MarketSync-Forever\tests -p 'test_*.py' -v
python .\MarketSync-Forever\tools\validate_contract.py --blizzard 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\BlizzardInterfaceCode\Interface\AddOns'
```

Package a new filename after the real Interface is known (replace `NUMBER` with its fourth return value):

```powershell
python .\MarketSync-Forever\tools\package.py --output .\outputs\MarketSync-Forever-interface-test.zip --interface NUMBER
```

The builder refuses overwrites. Development tests currently use the Lua parser and Fengari under `ItemRack-Forever\node_modules`; the client addon has no ItemRack dependency. Preserve that development installation or relocate the test dependencies deliberately before moving the source to another computer.

For resuming, start with [RESUME.md](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/MarketSync-Forever/RESUME.md). Earlier API findings are in [Forever-Auction-House-Accessibility.md](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/Forever-Auction-House-Accessibility.md).
