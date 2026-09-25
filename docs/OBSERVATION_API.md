# MarketSync Observation API v1

`MarketSync.ObservationAPI.v1` is an in-game, real-time event stream allowing companion addons—such as ledgers, uploaders, price trackers, and analytics tools (e.g. ForeverLedgerSync)—to subscribe to auction price observations directly in memory without modifying MarketSync's database or polling disk files.

MarketSync emits observations as they occur; companion addons own their own persistence (`SavedVariables`), realm/faction/build metadata tagging, deduplication, formatting, user consent, and any external upload workflows.

## Load and Subscribe

Declare `## Dependencies: MarketSync` (or `## OptionalDeps: MarketSync`) in your companion addon's TOC file so MarketSync loads first. Register your listener during addon initialization before scans begin. There is **no replay** for events that occurred prior to registration.

```lua
local API = MarketSync and MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1
if not API then return end

local function OnObservationEvent(event)
    if event.event == "start" then
        -- Begin a new batch using event.scanId, event.source, event.scope, and event.scanTime.
    elseif event.event == "observation" then
        -- Record price observation into your companion addon's data store.
    elseif event.event == "finish" then
        -- Mark this batch complete and eligible for storage or upload.
    elseif event.event == "cancel" then
        -- Discard or mark this batch incomplete (check event.reason).
    end
end

assert(API.Register(OnObservationEvent))
-- To unsubscribe later: API.Unregister(OnObservationEvent)
```

`Register(callback)` accepts a Lua function and returns `true`; invalid values return `false`. Re-registering the same function does not produce duplicate callbacks. `Unregister(callback)` removes the listener.

Each subscriber receives a fresh, shallow copy of the event table, so mutating values does not affect other subscribers. Callbacks execute synchronously under `pcall`; errors are safely caught and logged to MarketSync's debug facility. Subscribers should keep callbacks lightweight (e.g. buffering fields and deferring heavy serialization).

## Source and Market Classifications

`source` and `scope` are independent fields present on **every** event (`start`, `observation`, `finish`, `cancel`):

| `source` | `scope` | Origin & Meaning |
| --- | --- | --- |
| `local` | `main` | Observed by this client at a faction/main Auction House (via MarketSync's native scanner or an Auctionator full scan). |
| `local` | `neutral` | Observed by this client at a neutral/Goblin Auction House. |
| `synced` | `main` | Verified guild transfer of main-AH observations received and committed on this client. These are **not** this client's personal scans. |
| `synced` | `neutral` | Verified guild transfer of neutral-AH records received and committed on this client. |

`source` identifies provenance (`local` vs `synced`), while `scope` identifies the market (`main` vs `neutral`). `synced` means the local client accepted a verified transfer from a peer, not that it conducted a fresh scan. Preserve both fields rather than inferring provenance from the market alone.

## Event Lifecycle

The lifecycle values are `start`, `observation`, `finish`, and `cancel`:

```text
start ──► zero or more observation events ──► finish
      └─────────────────────────────────────► cancel
```

* All events in one batch share `scanId`, `source`, `scope`, and `scanTime`.
* **`finish`** is the terminal success event indicating the scan or transfer finished cleanly.
* **`cancel`** marks an aborted, superseded, or failed batch. `cancel.reason` provides a human-readable diagnostic string (e.g. `"request failed"`, `"exact keys unavailable"`, `"replaced by new scan"`). Any observations received prior to `cancel` must not be treated as a complete snapshot.
* A native manual single-item result emits `start → observation → finish` immediately.
* A native list or full scan emits a batch over the duration of the scan.
* An Auctionator full scan emits a batch when exact scanned keys can be identified; failure or unavailable exact keys emits `cancel`.
* A guild transfer starts on an eligible inbound `BEGIN`, emits observations **after the verified transaction commits**, and then finishes. Incomplete, rejected, or superseded transfers emit `cancel`.

## Event Fields

### Fields on Every Event (`start`, `observation`, `finish`, `cancel`):

| Field | Type | Meaning |
| --- | --- | --- |
| `event` | string | Lifecycle event: `"start"`, `"observation"`, `"finish"`, or `"cancel"`. |
| `scanId` | string | Opaque batch identifier for correlating events within the current session. |
| `source` | string | `"local"` or `"synced"`. |
| `scope` | string | `"main"` or `"neutral"`. |
| `scanTime` | number | Unix timestamp of the overall scan batch. For `local` scans, this is the authoritative realm time (`GetServerTime()`) when executed. For `synced` transfers, this is the sender's advertised `scanTime` from protocol negotiation. Use this to determine freshness between scans. |

`cancel` additionally includes `reason` (string).

### Fields on `observation` Only:

| Field | Type | Meaning |
| --- | --- | --- |
| `scanTime` | number | Unix timestamp of the scan batch this observation belongs to. |
| `key` | string | Exact MarketSync database key for the item/variant. Preserve verbatim; encodings vary by provider (e.g. `12345` or `p:12345:-17`). |
| `itemID` | number or `nil` | Parsed numeric item ID when possible. |
| `itemSuffix` | number or `nil` | Parsed random suffix when present (`0` or `nil` for base items). |
| `unitPrice` | number | Copper per unit; MarketSync's recorded price for this item/variant. |
| `quantity` | number or `nil` | Recorded available quantity when positive and known; `nil` when unknown. Never coerce unknown to zero or one. |
| `observedAt` | number or `nil` | Exact Unix-second observation time when recorded locally; `nil` for synced historical buckets where only the 30-minute window was transmitted. |
| `observedTime` | number or `nil` | Calculated Unix-second timestamp for the observation. Exact for local scans; for synced 30m buckets, represents the start of the 30m window in shared realm time ($\pm 15$ min precision). |
| `timePrecision` | string | `"exact"`, `"30m"`, `"day"`, or `"unknown"`. |
| `observedDay` | number or `nil` | Source scan-day number for historical/day-bucket observations. |
| `observedBucketOffset` | number or `nil` | Half-hour slot within `observedDay`, from `0` to `47`. |

## Timestamp and Quantity Fidelity

| Path | Time fields | Quantity |
| --- | --- | --- |
| Native MarketSync main-AH scan | `observedAt` and `observedTime` are authoritative realm seconds (`GetServerTime()`); `timePrecision="exact"`. `scanTime` matches `PersonalScanTime`. | Aggregated available quantity when positive; otherwise `nil`. |
| Auctionator-backed main-AH full scan | Auctionator `latest.seenAt` if supplied (`exact`); `observedTime` is `seenAt` or `scanTime`. `scanTime` matches `PersonalScanTime`. | Auctionator's recorded daily availability when positive; otherwise `nil`. This is not a raw per-listing count. |
| Auctionator-backed neutral-AH full scan | `observedAt=nil`, `observedDay`, `observedTime` (start of day), `timePrecision="day"`. `scanTime` matches scan completion. | Recorded neutral quantity when positive; otherwise `nil`. |
| Verified main-AH guild transfer | `observedAt=nil`, `observedDay`, `observedBucketOffset`, `observedTime` (start of 30m window, $\pm 15$ min precision), `timePrecision="30m"`. `scanTime` is sender's advertised scan time (`SwarmTSF`). | Transmitted bucket quantity when positive; otherwise `nil`. |
| Verified neutral-AH guild transfer | `observedAt=nil`, `observedDay`, `observedTime` (start of day), `timePrecision="day"`. `scanTime` is sender's advertised neutral scan time. | Transmitted quantity when positive; otherwise `nil`. |

Guild protocol v2 transmits main-AH history in 30-minute buckets and neutral history by day; it does **not** transmit each original sub-minute Unix second over in-game chat to prevent chat throttles. The calculated `observedTime` provides the realm timestamp for that 30-minute interval ($\pm 15$ minutes). The batch-level `scanTime` field is always available on all events (`start`, `observation`, `finish`, `cancel`) and should be used to establish chronological ordering and freshness between different scans.

## Performance, Rate Limits, and Companion Guidelines

### Rate Characteristics by Source

| Source / Trigger | Ingestion Rate | Burst Size | Throttling / Debouncing |
| --- | --- | --- | --- |
| **Manual Item Browse** | Real-time | 1–5 events / sec | Debounced: identical observations within 2 seconds are dropped. |
| **Native Full AH Scan** | Incremental per page | 1,000–3,000+ events over scan | Paged and bounded by Blizzard's AH server query throttle (~0.5–1.0s/page). |
| **Auctionator Full Scan** | Post-scan burst | 1,000–3,000+ events in a single batch | Delivered when Auctionator finishes scanning all pages. |
| **Guild Swarm Sync** | Chunked batches | 50–200 events / chunk | Bounded by Blizzard's `CHAT_MSG_ADDON` bandwidth budget (~800–1000 B/s). |

### Performance Impact and Execution Model

* **Zero Idle Cost**: If no companion addons are registered (`API.v1.HasListeners()` returns `false`), the Observation API bypasses all event table allocations and callback loops entirely. MarketSync incurs **zero runtime overhead** when idle.
* **Synchronous Callback Execution**: Callbacks run on the main World of Warcraft UI thread. When a full scan finishes, thousands of items may be emitted in rapid succession. Performing heavy work (e.g. string formatting, JSON serialization, regex matching, or disk table conversions) synchronously inside the callback will cause a momentary frame drop (FPS stutter).
* **Fault Isolation (`pcall`)**: Every subscriber callback is isolated in a `pcall`. If a companion listener raises a Lua runtime error, it is trapped and logged to `MarketSync.Debug`; it cannot crash MarketSync, break the auction scanner, or taint the user's interface.

### Recommended Zero-Lag Pattern (Queue + Frame Slicing)

To maintain 60+ FPS during large scan bursts, companion addons should push incoming events into a lightweight FIFO queue during the callback and drain them in small batches across multiple frames using `C_Timer.After`:

```lua
local eventQueue = {}
local isProcessing = false

local function ProcessQueue()
    local BATCH_SIZE = 50 -- Process 50 items per frame tick
    local processed = 0

    while #eventQueue > 0 and processed < BATCH_SIZE do
        local obs = table.remove(eventQueue, 1)
        -- Perform heavier work here (e.g. updating internal SavedVariables,
        -- calculating moving averages, or building export structures)
        processed = processed + 1
    end

    if #eventQueue > 0 then
        C_Timer.After(0.01, ProcessQueue) -- Yield to the next frame
    else
        isProcessing = false
    end
end

local function OnObservationEvent(event)
    if event.event == "observation" then
        eventQueue[#eventQueue + 1] = event
        if not isProcessing then
            isProcessing = true
            C_Timer.After(0.01, ProcessQueue)
        end
    end
end

MarketSync.ObservationAPI.v1.Register(OnObservationEvent)
```

## Coverage and Ingestion Guidance

* **Price Results vs. Raw Listings**: This is an item/variant price-result stream, not a raw individual auction listing stream. Native full scans aggregate listings by variant: `unitPrice` is the lowest observed unit buyout, and `quantity` is aggregated availability when known.
* **Deduplication**: Synced events can replay historical buckets or data already seen locally. Companion addons should validate and deduplicate by provenance (`source`), market (`scope`), `key`, source day/bucket, and price.
* **Real-time Only**: The Observation API emits active scans and inbound sync transfers in real time. It does not automatically replay old history on addon load. For a full offline import of existing history from disk, see the [SavedVariables Data Extraction Guide](DATA_EXTRACTION_GUIDE.md).

## Example Observation Event

```lua
{
    event = "observation",
    scanId = "sync-example-session",
    source = "synced",
    scope = "main",
    scanTime = 1789725600,   -- sender's advertised scanTime (used for freshness comparison)
    key = "p:12345:-17",
    itemID = 12345,
    itemSuffix = -17,
    unitPrice = 25000,       -- copper per unit (2g 50s)
    quantity = 4,
    observedAt = nil,        -- exact sub-minute second was not on the sync wire
    observedTime = 1789724400, -- start of the 30-minute bucket window in shared realm time
    observedDay = 20714,
    observedBucketOffset = 19,
    timePrecision = "30m",
}
```
