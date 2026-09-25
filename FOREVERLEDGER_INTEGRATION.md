# ForeverLedgerSync observation callback (v1)

MarketSync publishes scan observations directly to companion addons. Load ForeverLedgerSync after MarketSync (`## Dependencies: MarketSync` in its TOC), then register a callback:

```lua
local function OnMarketSyncEvent(event)
    if event.event == "start" then
        -- Open a local batch keyed by event.scanId.
    elseif event.event == "observation" then
        -- Save item/variant, unitPrice, quantity, and source metadata.
    elseif event.event == "finish" then
        -- Close and persist this batch; it can now be uploaded later.
    elseif event.event == "cancel" then
        -- Mark this batch incomplete; do not import it as a full scan.
    end
end

MarketSync.ObservationAPI.v1.Register(OnMarketSyncEvent)
-- On your own teardown: MarketSync.ObservationAPI.v1.Unregister(OnMarketSyncEvent)
```

Each callback receives a fresh Lua table. Listener errors are contained and logged to MarketSync debug output; one listener cannot stop MarketSync or another listener. Register once per addon load. Callbacks run synchronously, so copy the data into your own compact table and defer expensive formatting or serialization until after `finish`.

Common fields on every event:

| Field | Meaning |
| --- | --- |
| `event` | `start`, `observation`, `finish`, or `cancel` |
| `scanId` | Identifier tying one scan/transfer together; treat as opaque, not a globally unique permanent database key |
| `source` | `local` for scans on this client; `synced` for a verified guild transfer |
| `scope` | `main` or `neutral` AH |

`cancel` also has a human-readable `reason`. Only `finish` marks a complete batch. A `start`/`finish` pair with zero observations is valid.

Observation-only fields:

| Field | Meaning |
| --- | --- |
| `key` | MarketSync variant key, such as `12345` or `p:12345:-17`; preserve this exact key |
| `itemID` | Numeric item ID when parseable |
| `itemSuffix` | Random suffix when parseable (zero for base items) |
| `unitPrice` | Copper per unit |
| `quantity` | Actual quantity when known, otherwise `nil`; never treat `nil` as 1 or 0 |
| `observedAt` | Original Unix-second observation time when preserved, otherwise `nil` |
| `timePrecision` | `exact`, `30m`, `day`, or `unknown` |
| `observedDay` | Original source scan day for historical/synced observations |
| `observedBucketOffset` | 0–47 within `observedDay` when 30-minute precision is available |

Native MarketSync scans emit an exact `observedAt`. Auctionator-backed scans emit its `latest.seenAt` if available; otherwise time is `unknown`. Existing guild protocol v2 carries main-AH history in 30-minute buckets and neutral history by day, **not exact original seconds**. Synced events therefore leave `observedAt=nil` and provide the original day/bucket fields instead. Do not substitute the receiver's clock or the transfer completion time. A future wire-protocol revision would be needed for exact per-observation sync timestamps.

MarketSync records one price observation per item/variant result, not every individual auction listing. Full-scan observations are aggregated by variant; `quantity` is the observed total when available, and `unitPrice` is the lowest observed unit buyout. The callback does not provide the raw auction listings. Guild callbacks replay verified transfer records after commit; they can include historical buckets already seen locally, so ForeverLedgerSync should deduplicate by source/scope/key/day/bucket/price as appropriate.

ForeverLedgerSync should collect realm, faction, client build, and upload consent itself as planned. This API does not upload data or write to ForeverLedgerSync's saved file.
