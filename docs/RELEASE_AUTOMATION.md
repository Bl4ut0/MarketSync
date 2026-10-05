# Forever release automation

`forever` is the development branch. Ordinary pushes to it run tests and create a downloadable Actions artifact, but do not publish to CurseForge. A `v<version>-beta.<number>` tag on a `forever` commit creates a **GitHub prerelease only**. `main` is the promotion branch. When a reviewed candidate with a **new TOC version** is merged or pushed to `main`, the same validation runs and the resulting ZIP is uploaded to the MarketSync CurseForge project as a **Release-type** file for Forever, with a `Pre-Release` display title. Later pushes with the same version do not upload a duplicate.

## One-time setup

1. The `curseforge-beta` environment exists, allows deployments only from `main`, and has a `CF_API_TOKEN` environment secret for CurseForge uploads. Do not commit the token into repository files. If it is rotated, replace that GitHub secret before the next release candidate.
2. Consider requiring a reviewer for that environment. With approval enabled, a push to `main` packages immediately but waits for approval before the CurseForge upload. No reviewer is currently required.
3. Protect `main` with a pull-request and passing-check requirement if you want promotion to require review. Neither branch protection nor environment approval is configured by the workflow file itself.

The workflow checks that the TOC and `package.json` versions agree, the TOC includes Forever interface `16001`, and `RELEASE-<version>.md` exists. It uses `tools/package.py` to build the same addon layout as local releases, and it requires an exact CurseForge Forever version match rather than silently choosing another game version. The CurseForge project ID is 1466264.

The CurseForge file is named `MarketSync-<version>.zip`, its display name is `MarketSync Pre-Release <version>`, its file type is `Release` (matching the existing CurseForge posting style), and the **What's New** section comes from `RELEASE-<version>.md`. The release notes must begin with `# MarketSync <version>` so the heading matches the posted version. Beta tags use the same ZIP and notes but are marked as GitHub prereleases; they never upload to CurseForge.

## Promotion sequence

1. Finish and test changes on `forever`; bump the TOC and package version plus `RELEASE-<version>.md`.
2. For an optional GitHub-only beta, tag the tested `forever` commit `v<version>-beta.1`, then use `.2`, `.3`, etc. for further beta builds of that version. These create GitHub prereleases and do not touch CurseForge.
3. When ready for a CurseForge posting, merge the reviewed `forever` candidate with its bumped version into `main`. Do not use `main` for ongoing development.
4. Check the **Forever release candidate** workflow. The build artifact is downloadable from Actions; the main-branch upload job creates a Release-type file on CurseForge using the Pre-Release title.

The workflow does **not** create a full GitHub release or create tags automatically. A GitHub beta prerelease requires an explicit beta tag. The full 1.0.0 release process remains a deliberate step after client validation. Check CurseForge before manually retrying a failed upload; the server may have accepted a request even if the workflow did not receive its response.
