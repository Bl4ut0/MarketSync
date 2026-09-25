# MarketSync Documentation Hub

This directory contains technical specifications, integration guides, and performance architecture for MarketSync.

## Core Documentation

* **[Observation API Specification](OBSERVATION_API.md)**
  In-game, real-time observation event stream (`MarketSync.ObservationAPI.v1`) for companion addons (e.g. ForeverLedgerSync, uploaders, external trackers). Details lifecycle states (`start`, `observation`, `finish`, `cancel`), realm time synchronization (`GetServerTime()`), time precision taxonomies, and the zero-lag asynchronous queue pattern.

* **[External Data Extraction & Web Import Guide](DATA_EXTRACTION_GUIDE.md)**
  Complete specification for external web services, desktop uploaders, websites, and Discord bots to extract the full 30,000+ item Auction House database directly from WoW's `SavedVariables/MarketSync.lua` without downloading external programs (via the browser File System Access API, drag-and-drop, or lightweight scripts).

* **[Performance, Scaling & Architecture Guide](PERFORMANCE_AND_SCALE.md)**
  Technical deep dive into how MarketSync handles 30,000+ item catalogs with 60+ FPS: two-stage frame-sliced scanning (`READ_BATCH_SIZE = 250`, `WRITE_BATCH_SIZE = 150`), network bandwidth throttling (< 800 B/s), tiered time-series retention downsampling (Hot/Warm/Cold/Purge), and background coroutine maintenance.

* **[CurseForge Description](CURSEFORGE.md)**
  The live copy and feature overview used for the CurseForge project page.

