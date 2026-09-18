# Resume MarketSync Forever

Saved September 17, 2026. This file is a handoff, not a scheduled reminder.

## First steps after returning

1. Read [IMPLEMENTATION_GUIDE.md](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/MarketSync-Forever/IMPLEMENTATION_GUIDE.md) and [the current status](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/MarketSync-Forever-Scanner-Status.md).
2. Check the isolated track's latest local `forever` commit and any changes before editing:

   ```powershell
   Set-Location 'C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20'
   git -C .\MarketSync-Forever status --short --branch
   git -C .\MarketSync-Forever log -1 --format='%H %s'
   ```

3. Check whether the beta is still **1.60.1 (69893)** and whether login/AH access is now possible. An updated build must be audited before changing the capture guard. Obtain the Interface/project values after login; do not guess them from the version screenshot.
4. If native access exists, execute the guide's standalone acceptance checklist. If access is still unavailable, continue the isolated full-addon source preparation and provider migration in Stage 2. This work can proceed without claiming native acceptance.
5. After each stage, record code revision, checks run, native results versus modeled results, and the single next unfinished task here or in the status file.

## Current checkpoint

- **0.3.0 standalone scanner & embedded panel:** published to GitHub branch `forever-standalone`. Embedded native AH tab using `SetDisplayMode` + unified browser `Browser.lua` + portable portrait window.
- **Stage 2 full addon provider decoupling:** MarketSync `0.8.0-rc2` working tree imported with source manifest; `Provider.lua`, `AuctionatorProvider.lua`, and `ForeverProvider.lua` implemented. Decoupled direct Auctionator calls in `Config.lua`, `Core.lua`, `Notifications.lua`, `Processing.lua`, `Chat.lua`, `UI_Browse.lua`, and `UI_Notifications.lua`.
- **Local verification:** 29 scanner runtime tests, 7 provider decoupling tests, 4 packaging tests, and contract checks all pass; all 22 MarketSync Lua files parse as Lua 5.1.
- **Next tasks:** Stage 4 alert rule migration on native snapshots, Stage 5 `ReplicateItems` runtime probe, and client acceptance in Beta 1.60.1 (69893).

## Paste this to resume in a later conversation

> Continue the MarketSync Forever migration from `C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20\MarketSync-Forever\RESUME.md`. The standalone 0.3.0 scanner is on GitHub branch `forever-standalone`. The full MarketSync addon has been imported on the `forever` branch and decoupled from Auctionator via the Provider architecture (`Provider.lua`, `AuctionatorProvider`, `ForeverProvider`), with all runtime and provider tests passing. Next tasks are Stage 4 alert rule persistence on provider snapshots, Stage 5 `ReplicateItems` probe, and native client verification when login is accessible.

## Other completed work to retain

The API audit and ItemRack track are separate completed checkpoints. [ItemRack migration status](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/ItemRack-Forever-Migration-Status.md) records local `forever` commit `de0ebc71c9b9709ffa0efe33323fc126f783330d`; its client promotion still needs exact Interface metadata and native manual-equipment acceptance. [The broader API audit](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/WoW-Beta-API-Audit.md) and [equipment-manager findings](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/Forever-Equipment-Manager.md) remain available. The unbuilt Auctionator adapter scaffolding is not the active implementation path.
