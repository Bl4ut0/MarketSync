# Overlord / MarketSync communication review

Reviewed 2026-11-13, using installed Overlord Forever 2.5.1 from
`C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/Overlord`.
This is a static source review. No installed addon or saved data was changed,
and no live traffic capture was performed.

## Main finding

High Overlord readings are plausible: it synchronizes a faction/playstyle-wide
network, rather than just a guild. MarketSync also counts attempted sends as
traffic, whether the game accepts or refuses them. Its displayed B/s is not a
measurement of delivered network bytes.

The combination can defer MarketSync's data transfers for long periods. It does
not establish that Overlord is malfunctioning or that either addon is exceeding
the game's actual transport limits.

## What Overlord communicates

`Sync.lua:14` uses the main prefix `OverlordF`. State includes captures, outposts,
zone maps, kills, rankings, and history/catch-up. It uses group/raid, custom-channel,
guild, addon-whisper, and Battle.net paths. Additional feature prefixes also exist.

`SyncRelay.lua` fragments larger logical packets and forwards them along selected
routes. A single logical update can therefore cause several local API calls: one
per fragment and recipient. Relay envelopes and repeat attempts add overhead.
It suppresses known echoes and duplicate content and has a bounded queue, packet
lifetime/path limits, priority lanes, and backpressure. The code specifically
tries to prevent every peer answering a catch-up request with a full dump.

When custom-channel delivery is unavailable, `SyncDirectory.lua` discovers peers
from the channel membership list and uses whispers to exchange news and request
catch-up. Comments describe Forever observations; these are the author's findings,
not independent verification of current server behavior.

## Configured budgets and cadence

| Path | Installed source configuration |
| --- | --- |
| Relay | 1,000 accounting bytes/s, 500-byte token capacity; `SyncRelay.lua:1703–1714` |
| Relay accounting | Each transport task charges payload length plus 64 bytes; `SyncRelay.lua:1847` |
| Channel/group | Shared 0.8 messages/s allowance, capacity 1; critical sends have special handling; `Sync.lua:2499` onward |
| Guild lane | Token every 12 seconds, capacity 3, plus additional soft/hard limits; `SyncGuild.lua:43` onward |
| Directory live-news chain | 0.75 whisper-token/s, capacity 30; also subject to routing/relay constraints; `SyncDirectory.lua:856` |
| Passive sync | 120-second ticker with election/suppression and startup jitter; `SyncAux.lua:1519` onward |
| Active-front periodic work | 30-second configuration, with election, cooldown and jitter; `SyncAux.lua:23`, `Sync.lua:12396` |
| Prepared catch-up response | Producer ticks every 0.2 seconds normally or 0.45–0.5 in large events; actual sending can be limited by relay queues; `Sync.lua:6825` onward |

These are separate controls, not proof of a single addon-wide 1,000 B/s ceiling.
Direct sends and other lanes have their own rules. Nor does a producer's timer
rate prove that all of its messages reach the network at that rate.

## How MarketSync interprets it

`MarketSync/Sync.lua:134–143` hooks `C_ChatInfo.SendAddonMessage`. It adds message
payload length and one API call for every invocation. It does not inspect the
return code, record channel/target, or distinguish accepted calls from refusals.
Its per-prefix breakdown is local outgoing attempted traffic, not incoming
traffic from all Overlord users or a count of successful deliveries.

It excludes prefix/protocol overhead. It also does not hook Battle.net's separate
`C_BattleNet.SendGameData` transport, which Overlord uses in `Sync.lua:2905` onward.
Thus the monitor can overstate accepted WoW-addon traffic while missing other
transport traffic; it should not be interpreted as total bandwidth.

The one-second ticker reports raw counter differences without dividing by actual
elapsed time (`MarketSync/Sync.lua:909–951`). A delayed sampling interval can
distort the B/s display.

`MarketSync/Sync.lua:770–773` subtracts measured external attempted bytes from its
640 B/s data budget and stops refilling that budget at 36 external API calls/s.
For example, a sustained measured 700 B/s leaves zero refill for MarketSync data,
regardless of which channel Overlord used or how many attempts were refused.
Short bursts can be absorbed by existing tokens; sustained readings can starve
data transfers. Control traffic has separate handling.

Overlord's `SendAddonChecked` does distinguish accepted calls from refused calls
(`Overlord/Sync.lua:2417` onward). Its network report therefore provides useful
evidence that MarketSync's generic hook cannot supply.

## Recommended next step

Compare the MarketSync Overlord prefix reading with **`/ov network`** while idle,
during catch-up, and during an active front. This command builds a local diagnostic
report; `/ov relay` is a different probe and is not needed for this comparison.
Look for send refusals, queued work, and relay drops alongside the displayed rate.
No runtime readings were available for this review, so the dominant message type
in the user's session remains unconfirmed.

Before changing Overlord, improve MarketSync's measurement labels, elapsed-time
normalization, and transport breakdown. Accepted-versus-refused accounting needs
a return-code-aware approach; the existing post-call hook does not provide that
information. Then reassess whether MarketSync's conservative cross-addon budget
is unnecessarily starving its data stream. Do not simply remove throttling or
assume that the same server limits apply to every transport.
