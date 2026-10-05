# Forever release automation

`forever` is the development branch. Pushes to it run tests and create a downloadable Actions artifact, but do not publish to CurseForge. `main` is the promotion branch. When a reviewed release candidate with a **new TOC version** is merged or pushed to `main`, the same validation runs and the resulting ZIP is uploaded to the MarketSync CurseForge project as a **beta** file for Forever. Later pushes with the same version do not upload a duplicate.

## One-time setup

1. The `curseforge-beta` environment exists, allows deployments only from `main`, and has a `CF_API_TOKEN` environment secret for CurseForge uploads. Do not commit the token into repository files. If it is rotated, replace that GitHub secret before the next release candidate.
2. Consider requiring a reviewer for that environment. With approval enabled, a push to `main` packages immediately but waits for approval before the CurseForge upload. No reviewer is currently required.
3. Protect `main` with a pull-request and passing-check requirement if you want promotion to require review. Neither branch protection nor environment approval is configured by the workflow file itself.

The workflow checks that the TOC and `package.json` versions agree, the TOC includes Forever interface `16001`, and `RELEASE-<version>.md` exists. It uses `tools/package.py` to build the same addon layout as local releases, and it requires an exact CurseForge Forever version match rather than silently choosing another game version. The CurseForge project ID is 1466264.

## Promotion sequence

1. Finish and test changes on `forever`; bump the TOC and package version plus `RELEASE-<version>.md`.
2. Merge a reviewed `forever` release candidate into `main`. Do not use `main` for ongoing development.
3. Check the **Forever release candidate** workflow. The build artifact is downloadable from Actions. Once the `curseforge-beta` gate and token are in place, the upload job creates a beta file on CurseForge.

The workflow does **not** publish a stable CurseForge release or create a GitHub release/tag. Those remain deliberate release steps after client validation. Check CurseForge before manually retrying a failed upload; the server may have accepted a request even if the workflow did not receive its response.
