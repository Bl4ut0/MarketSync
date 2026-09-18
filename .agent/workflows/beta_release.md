---
description: Prepare a beta or release candidate, package it, optionally deploy locally, and publish only when explicitly requested
---

# /beta — Prerelease Workflow (Beta or RC)

This workflow prepares and packages the current working tree as a beta or release candidate. Local packaging and client deployment do not imply permission to commit, tag, push, or publish a GitHub prerelease; perform remote steps only when the user explicitly requests them.

## Prerequisites

- Review all local changes and preserve unrelated user work before preparing the artifact.
- A clean, committed tree and authenticated `gh` CLI are required only for the optional remote publication steps.

## Step-by-Step Procedure

### 1. Determine Prerelease Details

- Determine the **Base Version Number** from the scope of the changes. Use a minor bump for a wire-protocol change (for example, `0.7.0` to `0.8.0`).
- Determine the prerelease label and number: `{BaseVersion}-betaN` or `{BaseVersion}-rcN` (for example, `0.8.0-rc1`).
- Get the current date:
  - `Date` (e.g., `2026-06-14`)
  - `Date_Compact` (e.g., `20260614`)

### 2. Verify Clean State

- Run `git status` and identify the exact files belonging to the prerelease.
- Before an optional tag/push, ensure the intended release commit is on `main` and the tree is clean.

### 3. Update Version in TOC

- Update `## Version:` in `MarketSync/MarketSync.toc` to `{Version}`.

### 4. Update `CHANGELOG.md`

- If the current top entry is **not** already `## [{Version}]`, add a new entry at the top using the changes gathered from conversation context or by asking the user:
  ```markdown
  ## [{Version}] - {Date}
  ### Fixed / Added / Improved
  - **Fixed**: Description of changes...
  ```
- If a matching entry already exists (from a prior `/release`), leave it as-is.

### 5. Generate `GITHUB_RELEASE.md`

- Overwrite the file with a prerelease-specific release summary:
  ```markdown
  ### Prerelease Test Build (v{Version})
  This is a prerelease for testing. State the primary WoW product, build/interface, dependency version, and the issues testers should report.

  ---

  ## What's Changed in v{Version}

  {Changelog_Changes}

  **Full Changelog**: https://github.com/Bl4ut0/MarketSync/compare/vPREVIOUS...v{Version}
  ```

### 6. Build and Verify Prerelease Zip Package

Run the following PowerShell commands:
```powershell
# Create directories
New-Item -ItemType Directory -Force -Path ".Versions\Beta\v{Version}"
New-Item -ItemType Directory -Force -Path ".Versions\Compressed"

# Copy addon folder to prerelease backup
Copy-Item -Path MarketSync -Destination ".Versions\Beta\v{Version}" -Recurse -Force

# Compress into zip
Compress-Archive -Path MarketSync -DestinationPath ".Versions\Compressed\MarketSync-{Version}.zip" -Force

# Confirm one top-level MarketSync/ folder and record the artifact hash
tar -tf ".Versions\Compressed\MarketSync-{Version}.zip"
Get-FileHash -Algorithm SHA256 -LiteralPath ".Versions\Compressed\MarketSync-{Version}.zip"
```

### 7. Git Commit & Tag (Only When Explicitly Requested)

```bash
git add -A
git commit -m "Prerelease v{Version}"
git tag -a v{Version} -m "Prerelease v{Version}"
git push origin main
git push origin v{Version}
```

### 8. Create GitHub Pre-Release

- Extract the changelog content for this version from `CHANGELOG.md`.
- Write it to a temporary file `TEMP_NOTES.md` with a prerelease header:
  ```markdown
  ### Prerelease Test Build (v{Version})
  This is a prerelease for testing. Please report any issues or Lua errors.

  ---

  {Changelog_Changes}
  ```
- Create the GitHub pre-release:
  ```bash
  gh release create v{Version} ".Versions\Compressed\MarketSync-{Version}.zip" --title "v{Version} (Prerelease)" --notes-file TEMP_NOTES.md --prerelease
  ```
- Delete `TEMP_NOTES.md`.

### 9. Optional Local Deployment

- Keep the prerelease suffix in `MarketSync/MarketSync.toc` so the test client advertises its exact build.
- Deploy to one explicitly selected WoW product. TBC Anniversary is the default RC target:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .tools/install_local.ps1 -Product _anniversary_
  ```
- Do not deploy one RC to every installed WoW product automatically.

### 10. Confirm

```
Prerelease v{Version} prepared!

  • Local client: explicitly selected product only
  • Zip: .Versions/Compressed/MarketSync-{Version}.zip
  • SHA256: <verified artifact hash>
  • GitHub: https://github.com/Bl4ut0/MarketSync/releases/tag/v{Version} (only if published)
```
