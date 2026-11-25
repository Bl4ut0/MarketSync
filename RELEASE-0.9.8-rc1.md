# MarketSync 0.9.8-rc1

Release candidate for Forever 1.60.1 (Interface 16001). The addon TOC also lists Classic Era / SoD 1.15.9 (Interface 11509) and TBC 2.5.6 (Interface 20506); those legacy packages remain CI test artifacts until installed-client checks pass. Auctionator is optional.

## Shopping List Import & Export

- Shopping lists export as `!MS1!` strings with a CRC32 check. Imports are strictly validated, so a corrupted or malformed string is rejected instead of partially saved.
- `/ms import <string>` imports directly; `/ms import` with no text opens the import dialog.

## Posting Warning

- Before posting, MarketSync asks for confirmation when the unit price is at or below 60% of the median of recent comparable listings. It needs at least three recent listings seen within five minutes. The price can still be kept.

## Inventory and Ledger Split

- Character inventory tracking stays in the core addon for tooltips.
- The optional **MarketSyncLedger 1.0.1** companion holds transactions, FIFO costs and craft jobs. Install it alongside MarketSync if you want the ledger; it is off by default and its controls are under **Options → AddOns → MarketSync Ledger**.

## Sync Reliability

- Refused BEGIN, DATA and END frames are retried with the same payload and sequence, using bounded backoff.
- A BEGIN still refused after its 20-second acceptance window aborts the transfer without claiming completion, and the sender lane is released.
- Control messages are capped at 64 queued entries and expire after 30 seconds.

## Upgrading and Testing

1. Deploy the release candidate to your client installations.
2. Type `/reload` in-game to apply the updated interface.
3. Import a shopping list string with `/ms import` and confirm it appears under Shopping Lists.
4. Post an auction well below recent prices and confirm the posting warning appears.
5. Install MarketSyncLedger only if you want transaction tracking, then check AddOn Settings under Options → AddOns.
