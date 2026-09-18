---
description: Full stable release — update version, changelog, package zip, tag, and publish GitHub Release with changelog body and zip asset
---

# /deploy — Stable Release & Deploy Workflow

This is the full end-to-end stable release workflow. It combines `/release` (prepare files) + `/commit` (push & tag) + zip packaging + GitHub Release creation with the changelog as the release body and the zip attached as an asset.

## Prerequisites

- All code changes for this release are complete.
- The `gh` CLI must be authenticated (`gh auth status`).

## Step-by-Step Procedure

### 1. Ask User for Version

- Read the current version from `MarketSync/MarketSync.toc` (`## Version:` line).
- Suggest the next patch version (e.g., `0.7.0` → `0.7.1`).
- Ask the user to confirm or specify a different version.
- Get the current date: `Date` (e.g., `2026-06-14`).

### 2. Gather & Categorize Changes

- Review all code changes made in the conversation.
- Categorize each as: `### Fixed`, `### Added`, `### Improved`, `### Changed`, or `### Removed`.

### 3. Update `CHANGELOG.md`

Add a new version entry at the **top** of the changelog (below the header):
```markdown
## [{Version}] - {Date}
### Fixed
- **Fixed**: Description with technical detail.
```

### 4. Bump Version in `MarketSync/MarketSync.toc`

Update the `## Version:` line to the new version number.

### 5. Generate `GITHUB_RELEASE.md`

Overwrite the file with a user-facing release summary:
```markdown
## What's Changed in v{Version} 🚀

### Section Name
* **Change Title**: User-friendly description of impact.

**Full Changelog**: https://github.com/Bl4ut0/MarketSync/compare/vPREVIOUS...v{Version}
```

### 6. Update `CURSEFORGE.md`

Review and update **only** sections affected by new changes. Do NOT rewrite the entire file.

### 7. Update `README.md`

Same as CurseForge — update **only** affected sections (features, protocol, throughput, etc.).

### 8. Build Release Zip Package

```powershell
# Create directories
New-Item -ItemType Directory -Force -Path ".Versions\Releases\v{Version}"
New-Item -ItemType Directory -Force -Path ".Versions\Compressed"

# Copy addon folder to Release backup
Copy-Item -Path MarketSync -Destination ".Versions\Releases\v{Version}" -Recurse -Force

# Compress into zip
Compress-Archive -Path MarketSync -DestinationPath ".Versions\Compressed\MarketSync-v{Version}.zip" -Force
```

### 9. Git Commit & Tag

```bash
git add -A
git status
```

Show staged changes to the user. If everything looks correct, proceed:

```bash
git commit -m "Release v{Version}"
```

Extract the changelog entry for this version from `CHANGELOG.md` and write it to `TAG_MSG.md`. Create an annotated tag:

```bash
git tag -a v{Version} -F TAG_MSG.md
```

Delete `TAG_MSG.md`. Push:

```bash
git push origin main
git push origin v{Version}
```

### 10. Create GitHub Release

- Write the changelog content for this version to `TEMP_NOTES.md`.
- Create the GitHub release with the zip attached:
  ```bash
  gh release create v{Version} ".Versions\Compressed\MarketSync-v{Version}.zip" --title "v{Version}" --notes-file TEMP_NOTES.md
  ```
- Delete `TEMP_NOTES.md`.

### 11. Deploy Locally (Optional)

Ask the user if they want to deploy to their local WoW AddOns folder. If yes, run the `/local` workflow.

### 12. Confirm

```
✅ Release v{Version} deployed!

Files updated:
  • MarketSync/MarketSync.toc (version bump)
  • CHANGELOG.md (new entry)
  • GITHUB_RELEASE.md (regenerated)
  • CURSEFORGE.md (updated)
  • README.md (updated)

Artifacts:
  • Zip: .Versions/Compressed/MarketSync-v{Version}.zip
  • Backup: .Versions/Releases/v{Version}/
  • Tag: v{Version} (annotated with changelog)
  • GitHub Release: https://github.com/Bl4ut0/MarketSync/releases/tag/v{Version}
```
