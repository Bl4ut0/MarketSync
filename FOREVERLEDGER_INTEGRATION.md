# MarketSync observation callback API v1

This is the in-game addon-to-addon interface intended for ForeverLedgerSync. MarketSync emits observations; ForeverLedgerSync owns persistence, realm/faction/build metadata, deduplication, formatting, user consent, and uploads. This API neither writes ForeverLedgerSync's SavedVariables nor contacts the website.

## Load and subscribe

Declare `## Dependencies: MarketSync` in ForeverLedgerSync's TOC so MarketSync loads first. Register once during addon initialization, before starting a scan. There is **no replay** for events that happened before registration.

```lua
local API = MarketSync.ObservationAPI.v1

local function OnObservationEvent(event)
    if event.event == "start" then
        -- Begin a batch using event.scanId, event.source, and event.scope.
    elseif event.event == "observation" then
        -- Copy fields into your own SavedVariables-backed table.
    elseif event.event == "finish" then
        -- Mark this batch complete and eligible for import.
    elseif event.event == "cancel" then
        -- Mark this batch incomplete.
    end
end

assert(API.Register(OnObservationEvent))
-- If needed later: API.Unregister(OnObservationEvent)
```

`Register(callback)` accepts a Lua function and returns `true`; invalid values return `false`. Registering the same function again does not duplicate events. `Unregister(callback)` removes it and returns nothing. Each subscriber receives a fresh, shallow event table, so mutating it does not affect another subscriber. Callbacks run synchronously under `pcall`; failures go to MarketSync's debug logger. Keep the callback lightweight—copy fields and defer heavy serialization. `HasListeners()`, `NewScanID()`, and `Emit()` exist for MarketSync's internal producers; companion addons do not need to call them.

## Source and market classifications

`source` and `scope` are independent fields on **every** event, including `start`, `finish`, and `cancel`:

| `source` | `scope` | Meaning |
| --- | --- | --- |
| `local` | `main` | This client observed prices at a faction/main AH using MarketSync's native scanner or an Auctionator full scan. |
| `local` | `neutral` | This client observed prices at a neutral AH through the isolated Auctionator full-scan path. |
| `synced` | `main` | A verified guild transfer of main-AH history was committed on this client. These are **not** this client's personal scans. |
| `synced` | `neutral` | A verified guild transfer of neutral-AH records was committed on this client. These are **not** this client's personal scans. |

These are the only `source` and `scope` values emitted by v1 today. `local` does not distinguish MarketSync's scanner from Auctionator; there is no provider field. `synced` means the receiver accepted a verified transfer, **not** that it freshly scanned the AH. Preserve both fields rather than inferring provenance from the market alone.

## Event lifecycle

The only `event` values are `start`, `observation`, `finish`, and `cancel`.

```text
start ──► zero or more observation events ──► finish
      └─────────────────────────────────────► cancel
```

All events in one batch share its `scanId`, `source`, and `scope`. `finish` is the sole successful terminal event; `cancel` marks an incomplete or failed batch. A `start`/`finish` pair with zero observations is valid. A canceled batch may already contain observations; do not import it as a complete scan. `cancel.reason` is a human-readable diagnostic string, **not** a stable enum. Scan IDs are opaque identifiers for correlating events during a session, not globally unique permanent database keys. They can be reused across clients or reloads; create your own durable import identity.

A native manual single-item result emits `start → observation → finish` immediately. A native list or full scan emits a batch over the scan's lifetime. An Auctionator full scan emits a batch when exact scanned keys can be identified; failure or unavailable exact keys produces `cancel`. A guild transfer starts on an eligible inbound `BEGIN`, emits observations **after the verified transaction commits**, and then finishes. Incomplete, rejected, aborted, or superseded eligible transfers cancel. A finished guild transfer can be a delta rather than a complete AH snapshot. `finish` means the batch/transfer finished, **not** that every AH item was included.

If the client reloads or exits abruptly, no terminal callback is guaranteed. Treat a persisted batch without `finish` as incomplete. A listener registered mid-scan is not guaranteed to receive its `start` or earlier observations.

## Event fields

Fields on every event:

| Field | Type | Meaning |
| --- | --- | --- |
| `event` | string | One of the four lifecycle values above. |
| `scanId` | string | Opaque batch identifier; compare for equality within the current session. |
| `source` | string | `local` or `synced` as defined above. |
| `scope` | string | `main` or `neutral` as defined above. |

`cancel` additionally has `reason` (string). There is no progress event, completion count, scan type, provider name, realm, faction, game build, sender name, or upload status in v1.

Fields on `observation` only:

| Field | Type | Meaning |
| --- | --- | --- |
| `key` | string | Exact MarketSync database key for the item/variant. Preserve verbatim; encodings vary by provider. |
| `itemID` | number or `nil` | Parsed item ID when possible. |
| `itemSuffix` | number or `nil` | Parsed random suffix when possible. Base items may be `0` **or `nil`**, depending on the producer. |
| `unitPrice` | number | Copper per unit; MarketSync's recorded price for this item/variant. |
| `quantity` | number or `nil` | Recorded available quantity when positive and known; `nil` means unknown. Never coerce unknown to zero or one. |
| `observedAt` | number or `nil` | Unix-second observation time when retained; `nil` means exact seconds are unavailable. |
| `timePrecision` | string | `exact`, `30m`, `day`, or `unknown`, described below. |
| `observedDay` | number or `nil` | Source scan-day number for historical/day-bucket observations. |
| `observedBucketOffset` | number or `nil` | Half-hour slot within `observedDay`, from `0` to `47`. |

Optional fields are absent in Lua when unknown (`nil`). Do not identify an item by `itemID` alone when `key` contains a variant. Native keys can be `12345` or `p:12345:-17`; Auctionator may use other encodings. Preserve `key`, with `itemID` and `itemSuffix` as conveniences.

## Timestamp and quantity fidelity

| Path | Time fields | Quantity |
| --- | --- | --- |
| Native MarketSync main-AH scan | `observedAt` is the Unix second at result recording; `timePrecision="exact"`. | Aggregated available quantity when positive; otherwise `nil`. |
| Auctionator-backed main-AH full scan | Auctionator `latest.seenAt` if supplied (`exact`); otherwise `observedAt=nil` (`unknown`). | Auctionator's recorded daily availability when positive; otherwise `nil`. This is not a raw per-listing count. |
| Auctionator-backed neutral-AH full scan | `observedAt=nil`, `observedDay`, `timePrecision="day"`. | Recorded neutral quantity when positive; otherwise `nil`. |
| Verified main-AH guild transfer | `observedAt=nil`, `observedDay`, `observedBucketOffset`, `timePrecision="30m"`. | Transmitted bucket quantity when positive; otherwise `nil`. |
| Verified neutral-AH guild transfer | `observedAt=nil`, `observedDay`, `timePrecision="day"`. | Transmitted quantity when positive; otherwise `nil`. |

Guild protocol v2 transmits main-AH history in 30-minute buckets and neutral history by day; it does **not** transmit each original Unix second. Do not substitute local receive time, transfer completion time, or `scanTime` as an observation time. Scan-day numbers use the active provider's epoch; do not blindly multiply `observedDay` by 86,400 without accounting for that provider. Exact timestamps for synced records would require a future wire-protocol revision.

## Coverage and import guidance

This is an item/variant **price-result** stream, not a raw auction-listing stream. Native full scans aggregate listings by variant: unit price is the lowest observed unit buyout and quantity is aggregated availability when known. Synced events can replay historical buckets or data already seen locally. ForeverLedgerSync should validate and deduplicate by provenance, market, `key`, source day/bucket, and price as appropriate. One event is not necessarily one individual auction or one website row.

Current coverage is native main-AH scans and manual results, Auctionator **full** scans with identifiable keys, and verified protocol-v2 guild transfers. Auctionator's incremental/targeted database refreshes are **not currently emitted** through this callback. Generic SavedVariables re-reads and old history are not automatically replayed on addon load. For a full existing-history import, see the [SavedVariables extraction guide](DATA_EXTRACTION_GUIDE.md).

## Example observation

```lua
{
    event = "observation",
    scanId = "sync-example-session",
    source = "synced",
    scope = "main",
    key = "p:12345:-17",
    itemID = 12345,
    itemSuffix = -17,
    unitPrice = 25000,       -- copper per unit
    quantity = 4,
    observedAt = nil,        -- exact second was not on the sync wire
    observedDay = 20714,
    observedBucketOffset = 19,
    timePrecision = "30m",
}
```

This example is illustrative, not fixture data. The `nil` entry would be absent when iterating an actual callback table.
