# MarketSync text export (MSX v1)

Run `/ms export` in game. The window prepares a read-only snapshot of the **current realm's** MarketSync main and neutral price records. Click **Select All**, press **Ctrl+C**, and paste each numbered part into the receiving site in order. MarketSync never uploads the data itself. The export can be large after a full scan; parts are kept near 12 KB so each can be copied from WoW's edit box. Do not expect a single chat-sized string for a full Auction House database.

This is a data interchange format, not a SavedVariables restore format. It excludes account settings, character names, guild-member names, alert rules, profession data, and the global item-info cache. It may include realm, faction, and market identity in the header, plus every retained price observation for the current realm. Share it only with a site you trust.

## Part framing

Each copied part starts with a tab-separated header:

```text
MSX\t1\t<part-number>\t<part-count>\t<market-id>\t<exported-at>\t<record-count>
```

`part-number` is one-based. `record-count` is the count of `I` and `H` rows across the complete export, not just this part. `exported-at` is Unix seconds. All parts in one export have the same market ID, time, part count, and record count. A website should reject missing/duplicate part numbers or inconsistent headers, then concatenate the data rows in part-number order.

The market ID and all nonnumeric row fields use percent-encoding over their UTF-8 bytes: every byte outside ASCII letters, digits, `-`, `.`, `_`, and `~` becomes `%HH`. Decode percent escapes **after** splitting each row on tabs. Never interpret the decoded key as markup or executable code.

## Rows

Every data row is tab-separated. Numeric prices are integer **copper per unit**; blank numeric fields mean unknown, not zero.

```text
I\t<scope>\t<key>\t<latest-price>\t<scan-day>\t<observed-at>\t<quantity>\t<latest-bucket>\t<verified-price>\t<verified-day>\t<verified-quantity>
H\t<scope>\t<key>\t<scan-day>\t<kind>\t<value>
```

`scope` is `M` (main market, including observations received through guild sync) or `N` (neutral Auction House). Keep the scopes separate. `key` is the exact MarketSync database key: plain item IDs, variant keys such as `p:4471:12`, and other provider keys must be treated as opaque strings. Do not merge suffix variants into base item IDs.

`I` is the current summary of a stored key. `scan-day` is the provider's day number, and `latest-bucket` is the provider's 30-minute bucket number. For Forever these use Unix-based days/buckets; do not apply that assumption to a future export from another client. `verified-*` fields are present only when a full scan or completed sync established verified neutral data. A blank field is not verification.

`H` carries one retained history value for a key and scan day. The `kind` values mirror the saved schema:

| Kind | Meaning |
| --- | --- |
| `h` | Main-market hot 30-minute points or compact older summary; neutral-market daily high price |
| `vh` | Verified hot 30-minute points eligible for sync |
| `l` | Neutral daily low-price history, where present |
| `a` | Neutral quantity history, where present |

For scope `M`, `h` and `vh` are **not** raw decimal prices. Hot histories are compressed comma-separated `bucket-offset:base36-price:base36-quantity` tokens. The offset is `0`–`47` within the scan day; prices are copper and quantities are units. Older main-market `h` entries use `D:min:max:avg:volume` or `W:min:max:avg:volume`, with all four values in base 36. `D` is a daily summary and `W` is a weekly summary. For scope `N`, `h` and `l` are daily high/low prices in decimal copper. Importers should preserve unknown history tokens losslessly. A site can use `I` rows immediately for latest-price tracking without decoding `H`.

## Importer checklist

1. Validate the `MSX` magic and version `1` in every part. Reject unsupported versions.
2. Require exactly one copy of each part number from `1` through `part-count`, with matching market ID and export time.
3. Split rows on tabs before percent-decoding string fields. Preserve keys exactly, including case and suffix.
4. Parse prices as nonnegative integer copper. Treat blank values as missing. Preserve unknown `H` kinds/values rather than guessing.
5. Partition records by market ID **and** scope. Do not combine main and neutral prices or unrelated realms.
6. Count `I` and `H` rows and compare with `record-count`; reject a truncated paste.
7. Treat every export as a snapshot. Imports should use an explicit merge/upsert policy rather than assuming missing keys were deleted.

The exporter is read-only and does not change MarketSync's scan history or guild-sync state.
