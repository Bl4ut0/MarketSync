# Source Selector, Latest Index, and Partial Low RAM: Plan

Status: Phase 1 implemented (Main tab and Source selector), needs an in-game check. Phases 2 and 3 are planned. Target branch: `dev`.

## Decisions (confirmed)

- **"Latest"** means the newest scan across Personal and Guild combined. The
  newest record per item wins, using the scan timestamp already stored on each
  price record.
- **Tabs:** Personal Scan and Guild Sync merge into one **Main** tab with a
  **Source** selector: Latest, Personal, Guild, Data Pack, and timeframe
  picks. **Neutral AH** stays its own tab, with the same Source selector.
- **Low RAM:** only the Latest index stays resident. Every other source loads on
  demand, and per-sync-type toggles decide what stays loaded.

## Current code (what changes)

| Area | File | Notes |
|---|---|---|
| Main tab names and content | `MarketSync/UI_Main.lua` (`tabNames` at ~454, `titles` at ~532, `RefreshTabVisibility` at ~608) | Tab ids 1-7 are hard-coded in several callers. |
| Browse index build | `MarketSync/UI_Browse.lua` (`PersonalIndexReady`/`GuildIndexReady`/`NeutralIndexReady` at ~120, build at ~554-705) | Three separate indexes. No Latest index exists yet. |
| On-demand loading | `UI_Browse.lua` (`MarketSync.LoadPersonalCache`/`LoadGuildCache`/`LoadNeutralCache` at ~2397-2417) | Uses the `Force*` flags. |
| Low RAM settings | `MarketSync/Config.lua` (defaults at ~557-560, init at ~603-606) and `MarketSync/Core.lua` (`LowRamMode` checkbox at ~343) | `OnDemandPersonal`, `OnDemandGuild`, `OnDemandNeutral`. |
| Low RAM UI | `MarketSync/UI_Main.lua` (~841-870) | Existing Low RAM checkbox and sub-toggles. |
| Analytics page | `MarketSync/UI_Analytics.lua` | Source toggles go in the top dead space. Not started. |

## Phase 1: Main tab and Source selector (no memory change yet)

1. Add a `Main` tab in `UI_Main.lua` that reuses the Personal and Guild browse
   panels. Keep the old tab ids mapped so saved tab state still opens correctly.
2. Add a Source selector to the Main tab with the options above. Selecting a
   source re-filters the existing Personal, Guild, or Data Pack index. It does
   not change what is in memory yet.
3. Keep Neutral AH as its own tab, with the same selector.

Test: the existing `test_ah_features.js` and `test_theme_components.js` cover the
main-window tab layout. Update them for the new tab order. Add a test that every
Source option maps to an index that exists.

## Phase 2: Latest index and partial Low RAM

1. Build a `LatestIndex` from Personal and Guild, keeping the newest record per
   item. It is the only index that stays resident in Low RAM mode.
2. Personal, Guild, Neutral, and Data Pack indexes build on demand when the user
   selects that source. Each sync type has its own live-load toggle in Low RAM
   settings (for example, keep Guild loaded or not).
3. When a source is unloaded, its memory is released and its status shows as
   "on demand".

Test: a unit test for the Latest merge (newest-per-item across two sources, and
a tie break). Check that selecting a non-Latest source loads it once and that
Low RAM keeps only `LatestIndex` resident.

## Phase 3: Analytics source toggles

1. Add clickable source toggles in the empty top area of the Analytics page:
   Local scan + Sync data, Data Pack, and Neutral AH.
2. Wire Neutral AH analytics to the same toggles so the Neutral data can be
   viewed.
3. Make sure navigating between Analytics, Main, and the Auction House tabs
   keeps the selected source.

## Risks

- `UI_Browse.lua` is about 3,200 lines and the index builds are tightly coupled.
  Phase 2 should be built behind a flag so the current path still works if the
  new index has a bug.
- No in-game test has been run for any of this. Each phase needs a short in-game
  check before the next one starts.
- The Forever release notes mention a `forever` branch that no longer exists.
  Releases go through `main` and tags.
