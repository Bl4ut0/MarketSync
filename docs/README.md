# MarketSync Documentation Hub

This directory contains technical specifications, integration guides, and performance architecture for MarketSync.

## Core Documentation

* **[Observation API Specification](OBSERVATION_API.md)**
  In-game, real-time observation event stream (`MarketSync.ObservationAPI.v1`) for companion addons (e.g. ForeverLedgerSync, uploaders, external trackers). Details lifecycle states (`start`, `observation`, `finish`, `cancel`), realm time synchronization (`GetServerTime()`), time precision taxonomies, and the zero-lag asynchronous queue pattern.

* **[External Data Extraction & Web Import Guide](DATA_EXTRACTION_GUIDE.md)**
  Complete specification for external web services, desktop uploaders, websites, and Discord bots to extract the full 30,000+ item Auction House database directly from WoW's `SavedVariables/MarketSyncDB.lua` without downloading external programs (via the browser File System Access API, drag-and-drop, or lightweight scripts).

* **[Performance, Scaling & Architecture Guide](PERFORMANCE_AND_SCALE.md)**
  Technical deep dive into how MarketSync handles 30,000+ item catalogs with 60+ FPS: two-stage frame-sliced scanning (`READ_BATCH_SIZE = 250`, `WRITE_BATCH_SIZE = 150`), network bandwidth throttling (< 800 B/s), tiered time-series retention downsampling (Hot/Warm/Cold/Purge), and background coroutine maintenance.

* **[CurseForge Description](CURSEFORGE.md)**
  The live copy and feature overview used for the CurseForge project page.

---

## Archive

Historical release notes, prototype handoff checklists, and legacy integration documents are preserved in the **[archive](archive/)** directory:

* [`RELEASE-0.9.2.md`](archive/RELEASE-0.9.2.md) — Release notes for 0.9.2
* [`RELEASE-0.9.1.md`](archive/RELEASE-0.9.1.md) — Release notes for 0.9.1
* [`CURSEFORGE-0.9.0.md`](archive/CURSEFORGE-0.9.0.md) — 0.9.0 CurseForge copy
* [`CURSEFORGE-LEGACY.md`](archive/CURSEFORGE-LEGACY.md) — Legacy CurseForge draft
* [`GITHUB_RELEASE.md`](archive/GITHUB_RELEASE.md) — Historical release text
* [`IMPLEMENTATION_GUIDE.md`](archive/IMPLEMENTATION_GUIDE.md) — September 17 integration plan
* [`RESUME.md`](archive/RESUME.md) — September 18 migration handoff notes
