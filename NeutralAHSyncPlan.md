# Neutral AH Sync Plan (Core-First)

## Execution Status (2026-03-07)

- Core scope: implemented (neutral isolation, guild-only neutral sync path, neutral tab, notifications, Auctionator list import).
- Deferred protection scope: intentionally deferred (multi-source confirmation + scan fingerprinting).

## Locked Requirements

1. Neutral data must remain fully isolated forever.
2. Neutral data must never pollute the main Auctionator realm database used for normal AH.
3. Neutral sync is guild channel only (no whisper/direct burst path).
4. Neutral UX is one combined tab (not split Personal vs Guild like main AH).
5. Leaderboard logic is removed from neutral scope.

## Scope Split

### Core Scope (Build Now)

1. Neutral isolation and neutral-only storage.
2. Guild-only neutral sync path.
3. Single neutral tab with price, age, source.
4. Notification Requests with threshold alerts.
5. Import Notification Requests from Auctionator Shopping Lists.

### Deferred Protection Scope (Keep in Plan, Build Later)

1. Multi-source confirmation and contested tuple handling.
2. Scan fingerprint corroboration and duplicate replay detection.

## Data Isolation Model (Core)

Use a dedicated neutral store under MarketSync DB:

- `NeutralData`: current merged neutral snapshot shown in the neutral tab.
- `NeutralMeta`: source, scan time, age, and state.
- `NeutralSync`: neutral-specific sync/session state.
- `NeutralNotifications`: requests and runtime alert state.

Do not write neutral records into Auctionator main pricing tables.

## Neutral Ingest Strategy (Core)

1. Detect neutral AH scan context.
2. Route neutral rows into `NeutralData` only.
3. If neutral rows are observed in live Auctionator writes during scan, capture and mirror into `NeutralData`, then restore/undo those live writes before finalizing.
4. Mark neutral snapshot complete on scan close, then rebuild only neutral browse index.

This preserves strict separation even when Auctionator internals are active.

## Swarm Queue States for Neutral

Add/retain explicit states for user visibility:

- `Idle`
- `Sending Neutral`
- `Receiving Neutral`
- `Awaiting Neutral Data`
- `Version Mismatch (Neutral Disabled)`
- `Paused (Smart Rules: <reason>)`
- `Blocked (Busy: <send|receive|pull pending>)`
- `Error (Neutral Sync)`

## Notification Requests (Core)

Allow users to track items and get alerted when price <= threshold, even if they did not scan personally.

### Data Model

- `NotificationRequests[itemKey or itemID]`:
  - `thresholdCopper`
  - `scope` (`main`, `neutral`, `all`)
  - `variantMode` (`exact key` or `any suffix`)
  - `cooldownSec`
  - `enabled`
  - `createdAt`
- `NotificationState`:
  - `lastAlertAt`
  - `lastAlertPrice`
  - `armed` (re-arm flag to prevent spam loops)

### Trigger Flow

1. Any commit (personal scan, guild sync, neutral sync) emits changed item keys.
2. Evaluate matching requests for those keys only.
3. If price <= threshold and cooldown/re-arm checks pass, fire alert.
4. Alert channels: UI toast + chat line (+ optional sound).

### Re-Arm Logic (Anti-Spam)

- After alert fires, request disarms.
- It rearms only when price rises above threshold by a configurable buffer (for example +5%) or after a time window.
- Prevents repeated alerts at the same stale price.

## Auctionator Shopping List Import (Core)

Use Auctionator list data as a fast way to seed Notification Requests.

### Integration Points

- Saved variable source: `AUCTIONATOR_SHOPPING_LISTS`.
- Preferred API path:
  - `Auctionator.Shopping.ListManager:GetCount()`
  - `Auctionator.Shopping.ListManager:GetByIndex(index):GetName()`
  - `Auctionator.API.v1.GetShoppingListItems("MarketSync", listName)`
  - `Auctionator.API.v1.ConvertFromSearchString("MarketSync", searchString)`

### Import Flow

1. User clicks `Import Auctionator List`.
2. MarketSync displays available list names.
3. User selects one or more lists.
4. Each list entry is parsed with `ConvertFromSearchString`.
5. A Notification Request is created per entry.
6. Imported requests start as:
   - `enabled = false` if no threshold was provided
   - `enabled = true` if threshold preset/import rule exists

### Mapping Rules

- `searchString` -> `displayName` or name-based matcher.
- If item key is not resolvable immediately, keep as name query and auto-resolve on next cache/index pass.
- `quantity` from Auctionator is stored as optional `quantityHint`.
- No writes back to Auctionator lists unless explicitly requested later.

### Optional Auto-Sync Toggle

If enabled, MarketSync listens for Auctionator shopping list changes and prompts:

- `shopping list item change`
- `shopping list meta change`
- `shopping list import finished`

Prompt text: `Auctionator list changed. Re-import notifications?`

## Deferred Protection Pack (Post-Core)

Keep this section in plan but do not gate core release on it.

### Multi-Source Confirmation

Use confirmation-by-agreement instead of outlier rules or source reputation scores.

Evidence key:

- `itemKey + day + price + quantity`

Evidence value:

- Distinct source set within a short window (for example 30 minutes)

Status rules:

- `Confirmed`: tuple seen from at least 2 sources
- `Single-source`: tuple seen from 1 source
- `Contested`: conflicting tuples with no quorum

Example:

- Source A: `95g` -> `Single-source`
- Source B: `95g` -> `Confirmed`
- Source C: `140g` -> `Contested`
- Source D: `140g` -> new `Confirmed`

### Scan Fingerprinting

Fingerprint is for correlation and replay/duplicate detection, not truth validation.

Payload:

- `scanDay`
- `itemCount`
- `sampleDigest`
- `bucketDigest`
- protocol version

Use:

1. Ignore duplicate payloads from same source/session.
2. Correlate similar scans from multiple sources.
3. Mark scan as corroborated when fingerprint matches across sources.

## Phased Implementation

1. Neutral storage and hard isolation (no Auctionator pollution).
2. Neutral guild-only protocol path and queue states.
3. Neutral tab/index wiring with source+age fields.
4. Notification Request UI + evaluator + alert delivery.
5. Auctionator Shopping List import and mapping.
6. Deferred protections (multi-source + fingerprint) after core stability.

## Acceptance Criteria

1. Neutral scans never persist in Auctionator main tables after scan completion.
2. Neutral tab displays prices, age, and source.
3. Neutral sync uses guild only; whisper sync is unavailable.
4. No leaderboard dependency in neutral path.
5. Notifications fire from synced data without requiring local scans.
6. Repeated stale conditions do not spam alerts.
7. Users can import Auctionator shopping lists into Notification Requests.
