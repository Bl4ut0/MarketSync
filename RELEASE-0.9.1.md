# MarketSync 0.9.1 — Forever

This Forever-first update adds a versioned observation callback for companion addons such as ForeverLedgerSync. It reports local and verified guild-synced price observations, preserves item variants and known quantities, and groups results under scan IDs with start, finish, and cancel events.

The [integration guide](FOREVERLEDGER_INTEGRATION.md) documents the callback and its precision limits. Native scan timestamps are exact; the existing guild protocol preserves main-AH time only to a 30-minute bucket and neutral-AH time to a day. Unknown values remain unknown rather than being guessed.

This release still targets Forever 1.60.1 (build 69893). Other WoW client versions have not been validated for 0.9.1. Processing and Alerts remain opt-in beta features.
