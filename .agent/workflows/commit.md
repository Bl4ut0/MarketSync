---
description: Commit and push the current release to GitHub with proper tagging
---

# /commit — Commit & Push to GitHub

This workflow commits all staged changes, creates a version tag, and pushes to GitHub. Each step is a **separate command** — no `&&` chaining.

## Prerequisites

- The `/release` workflow should have been run first to prepare version bump, changelog, and docs.
- The working directory is `c:\Dev Projects\MarketSync`.

## Steps

### 1. Read the Current Version

Read `MarketSync/MarketSync.toc` to get the current version from the `## Version:` line. This will be used for the commit message and tag.

### 2. Stage All Changes

Run:
```
git add -A
```
// turbo

### 3. Review Staged Changes

Run:
```
git status
```
// turbo

Show the output to the USER. If something looks wrong, stop and ask before committing.

### 4. Commit

Run:
```
git commit -m "Release vX.Y.Z"
```

Replace `X.Y.Z` with the actual version from step 1. The commit message should be exactly `Release vX.Y.Z` — keep it clean.

### 5. Extract Changelog & Create Annotated Tag

Read `CHANGELOG.md` and extract the changes listed under the new version header `## [X.Y.Z]`. Write these changes to a temporary file `TAG_MSG.md`.

Create an annotated git tag containing the extracted changelog as its message:
```bash
git tag -a vX.Y.Z -F TAG_MSG.md
```

Then delete the temporary `TAG_MSG.md` file.

### 6. Push Commit

Run:
```
git push
```

### 7. Push Tag

Run:
```
git push origin vX.Y.Z
```

Replace `X.Y.Z` with the actual version.

### 8. Confirm

After all commands succeed, print:

```
✅ Release vX.Y.Z pushed to GitHub!

  • Commit: Release vX.Y.Z
  • Tag: vX.Y.Z
  • Remote: origin

GitHub Release page: https://github.com/Bl4ut0/MarketSync/releases/tag/vX.Y.Z
```
