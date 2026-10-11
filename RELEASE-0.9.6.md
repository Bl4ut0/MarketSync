# MarketSync 0.9.6

Release for Forever 1.60.1 (build 70205), tagged `v0.9.6`. Promoted to `main` for CurseForge publication as a Release-type file titled `MarketSync Pre-Release 0.9.6`.

## What's New

- Craft requests have their own saved lists, quantities, and editable Buy/Craft/Provide choices. Raw-material purchases can be exported separately from ordinary shopping lists.
- Scanner list items and Analytics rows/header now expose the shared right-click item menu: price alerts, shopping lists, AH search, chat links, and removal from the active list when applicable.
- Addon settings are centralized in the AddOns settings page, with roomier controls, text-aware button padding, minimap visibility, and optional Debugging access. The Task Manager and diagnostics expose background work and resource estimates.
- Theme coverage, portable/auction-house sidecar access, alert controls, and material-dropdown sizing have been refined.

## Reliability Fixes

- Broad Processing searches consume the built market cache and saved profession recipes rather than scanning the entire item database. Work yields across frames and cancels on hide or mode change.
- Processing chooses fresher cached observations before comparing prices. The Network Monitor batches log and peer rendering and stops rendering while hidden.
- Browse placeholders recover their localized names and icons when item data arrives later, including after tooltip hover. Fallback retry work remains batch-limited.
- Output-less SoD profession actions no longer index a nil output item ID. Current-character profession filtering and sync self-identity handling have been tightened.
- Changing themes saves the preference without attempting a protected automatic reload. Type `/reload` to apply the theme.

## Candidate Testing

Automated regression, network simulation, and packaging checks accompany this candidate; they do not replace live-client validation. Re-test large-cache Processing, tab switching, sync with the monitor open/closed, and late item resolution. The reported execution-time warning is not yet confirmed resolved in-game.

Processing and Alerts remain opt-in beta features. Era, SoD, and TBC archives are Actions test artifacts, not promoted multi-flavor releases. No saved auction data is reset by this update.
