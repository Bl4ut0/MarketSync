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

- **0.2.0 standalone scanner:** native observed searches + up to 50 watched keys; draggable saved-price window; manual isolated Main/Neutral stores; complete-item provider API.
- **Auction-house access:** MarketSync launcher beside the native tabs, opening the portable window. The embedded control panel is planned.
- **Local verification:** 23 production-Lua runtime cases, four packaging tests, five Lua files parsed as Lua 5.1, 16 auction function references and 13 registered events checked against the exported beta docs; frame/tab templates verified present.
- **Not implemented yet:** the full addon provider refactor, dedicated Personal/Guild/Neutral views, existing alerts/processing/chat migration, full-market replication, and guild transfers.
- **Waiting on native evidence:** exact Interface number, loader acceptance, real server/event/restriction behavior, market topology, and UI layout. The draft has not been installed.
- **Data:** separate `MarketSyncForeverScanDB`; no original `MarketSyncDB` or Auctionator store changes.
- **Full addon source:** `C:\Dev Projects\MarketSync` has rc2 uncommitted changes on release commit `33107fcb3f04d5a267e40865e166b30bf47db58b`; preserve and copy the current working tree for integration.

The local branch checkpoint is separate from the original repository and has not been pushed. Packages and their hashes are listed in the status file; 0.1.0 is retained as the earlier baseline.

## Paste this to resume in a later conversation

> Continue the MarketSync Forever migration from `C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20\MarketSync-Forever\RESUME.md`. Read the implementation guide and current scanner status, then inspect the local `forever` branch before changing files. The agreed design is a MarketSync auction-house tab for scan/watch/alert setup plus a portable window retaining Personal Scan, Guild Sync, and Neutral AH. The standalone 0.2.0 has native capture, watched refresh, saved browsing, isolated manual Main/Neutral stores, and an AH launcher; embedded panels, alerts, full-market replication, and guild transfers are still planned. Native acceptance and exact Interface metadata are pending. Preserve the dirty rc2 worktree in `C:\Dev Projects\MarketSync` and keep existing client providers working. First establish current beta build/access; test the scanner if possible, otherwise prepare a separate copy of the current addon and implement the Stage 2 provider boundary. Do not mark a watched-key refresh as a completed full-market scan.

## Other completed work to retain

The API audit and ItemRack track are separate completed checkpoints. [ItemRack migration status](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/ItemRack-Forever-Migration-Status.md) records local `forever` commit `de0ebc71c9b9709ffa0efe33323fc126f783330d`; its client promotion still needs exact Interface metadata and native manual-equipment acceptance. [The broader API audit](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/WoW-Beta-API-Audit.md) and [equipment-manager findings](C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/outputs/Forever-Equipment-Manager.md) remain available. The unbuilt Auctionator adapter scaffolding is not the active implementation path.
