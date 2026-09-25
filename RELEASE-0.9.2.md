# MarketSync 0.9.2 — Forever

This Forever-first update enhances the versioned `ObservationAPI.v1` for companion addons such as ForeverLedgerSync with authoritative server time synchronization and chronological scan tracking.

## What's new in 0.9.2

- **Authoritative Server Time**: Uses Blizzard's `GetServerTime()` API to align all scan timestamps and 30-minute bucket calculations with the realm clock, eliminating local PC clock skew.
- **Scan Timestamp Tracking (`scanTime`)**: `start`, `finish`, and `cancel` batch lifecycle events (and individual observations) now emit the Unix `scanTime`, enabling companion addons to determine chronological ordering and freshness between scans.
- **Calculated Realm Timestamps (`observedTime`)**: Synced price observations now include `observedTime` calculated from the source day and 30-minute bucket window in shared realm time ($\pm 15$ min precision).
- **Observation API Documentation**: [`OBSERVATION_API.md`](OBSERVATION_API.md) details the updated event schema, realm time alignment, and companion synchronization rules.

This release targets Forever 1.60.1 (build 69893). Other WoW client versions have not been validated for 0.9.2. Processing and Alerts remain opt-in beta features.
