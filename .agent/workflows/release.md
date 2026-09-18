---
description: Prepare a new release — update changelog, docs, version number, and GitHub release notes (does NOT commit)
---

# /release — Prepare a New Release

This workflow prepares all files for a new release version. It does **NOT** commit or push — use `/commit` for that.

## Context & File Locations

All paths are relative to the MarketSync project root:
- **Version source of truth**: `MarketSync/MarketSync.toc` → line starting with `## Version:`
- **Changelog**: `CHANGELOG.md` — [Keep a Changelog](https://keepachangelog.com) format
- **GitHub Release Notes**: `GITHUB_RELEASE.md` — short, user-facing summary for GitHub Releases page
- **CurseForge Description**: `CURSEFORGE.md` — full addon description page for CurseForge
- **README**: `README.md` — full project README for GitHub repo landing page
- **Beta Zips (Git Ignored)**: Stored in `.Versions/` as `MarketSync.<version>-beta.zip`
- **Release Backups (Git Ignored)**: Stored in `.Versions/Releases/` as `MarketSync-v<version>-backup-<timestamp>.zip`


## Steps

### 1. Determine the Next Version

Read the current version from `MarketSync/MarketSync.toc` (the `## Version:` line). The version follows semver (`MAJOR.MINOR.PATCH`). Increment the **PATCH** number by 1 to get the next version. For example, `0.5.2` → `0.5.3`.

If the changes include breaking protocol changes or major new features, ask the USER whether to bump MINOR instead.

### 2. Gather Changes

Review all code changes made in this conversation (or ask the USER to describe what changed). Categorize each change as one of:
- `### Fixed` — Bug fixes
- `### Improved` — Performance, code quality, or UX improvements
- `### Added` — New features
- `### Changed` — Behavioral changes
- `### Removed` — Removed features

### 3. Update `CHANGELOG.md`

Add a new version entry at the **top** of the changelog (below the header), using today's date. Format:

```markdown
## [X.Y.Z] - YYYY-MM-DD
### Fixed
- **Fixed**: Description of fix with technical detail.

### Improved
- **Improved**: Description of improvement.
```

Each entry should include enough technical detail that a developer can understand *what* changed and *why*, including the root cause for bug fixes.

### 4. Bump Version in `MarketSync/MarketSync.toc`

Update the `## Version:` line to the new version number.

### 5. Generate `GITHUB_RELEASE.md`

**Overwrite** the entire file with a fresh release summary for the new version. Format:

```markdown
## What's Changed in vX.Y.Z 🚀

### Section Name
* **Change Title**: User-friendly description of what changed and why it matters. Keep it concise but informative. Non-developers should be able to understand the impact.

**Full Changelog**: https://github.com/Bl4ut0/MarketSync/compare/vPREVIOUS...vNEW
```

Rules:
- Write for end users, not developers — focus on impact, not implementation details
- Group related changes under descriptive section headers (e.g., "Bug Fixes", "Performance", "Price Check System")
- Keep it short — this is a summary, not the full changelog
- Always include the Full Changelog comparison link at the bottom

### 6. Update `CURSEFORGE.md`

Review the existing CurseForge description and update **only** the sections that are affected by the new changes. For example:
- If throughput changed, update the throughput numbers
- If a new feature was added, add it to the features list
- If protocol details changed, update the protocol section

Do NOT rewrite the entire file — only touch what's actually stale.

### 7. Update `README.md`

Same approach as CurseForge: review the existing README and update **only** the sections affected by the new changes. Common areas to check:
- Feature bullet points
- Protocol architecture table
- Bandwidth/throughput numbers
- How Sync Works section
- Usage examples

### 8. Confirm

After all changes are made, print a summary:

```
✅ Release vX.Y.Z prepared!

Files updated:
  • MarketSync/MarketSync.toc (version bump)
  • CHANGELOG.md (new entry)
  • GITHUB_RELEASE.md (regenerated)
  • CURSEFORGE.md (updated)
  • README.md (updated)

Ready to commit — use /commit to push to GitHub.
```
