---
description: Build and safely deploy addon files to one local WoW product for testing (TBC Anniversary by default)
---

# /local — Local Build & Install Workflow

This workflow copies the MarketSync addon from the development project into one explicitly selected World of Warcraft AddOns folder for in-game testing. It defaults to TBC Anniversary and never loops over every installed client.

## Prerequisites

- PowerShell available.
- World of Warcraft installed at the default path, or an explicit `-WowRoot` supplied.
- `MarketSync/MarketSync.toc` present in the project source.

## Step-by-Step Procedure

1. **Deploy to TBC Anniversary**:
   Run the pre-configured script from PowerShell. `_anniversary_` is both the default and the explicit RC test target:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .tools/install_local.ps1 -Product _anniversary_
   ```

   A different installed client must be named explicitly, for example `-Product _classic_`. Never deploy an RC to multiple products in one command.

2. **Verify Installation**:
   The installer stages the source, compares every file's length and SHA256 hash, retains the previous install under `.tools/backups/<product>/`, and restores it automatically if deployment or verification fails. Confirm the installed version if desired:
   ```powershell
   Get-Content "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\MarketSync\MarketSync.toc" | Select-String "^## Version:"
   ```

3. **Confirm**:
   ```
   ✅ MarketSync deployed locally!

     Reload your WoW UI (/reload) to pick up the changes.
   ```
