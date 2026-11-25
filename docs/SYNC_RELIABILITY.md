# Send reliability and traffic diagnostics

The local `0.9.7-rc7-local1` preview keeps sync protocol revision 2 and its existing
wire format, source election, faction/playstyle boundaries and staged receiver
commits. The changes concern local transmission and diagnosis.

## Sending and retries

- BEGIN, DATA and END stay staged until the local addon-message API accepts them.
  Refusal never advances their sequence or accepted-record counter.
- Local API results `0`, `true`, and legacy `nil` are treated as acceptance.
  Nonzero results, `false`, and Lua errors count as refusal. This is **not** a
  delivery acknowledgment from another player.
- Failed queued frames use jittered exponential backoff, from about 0.7 seconds
  to 8 seconds, with at most six attempts and a 30-second retry deadline.
  A BEGIN also needs acceptance within 20 seconds of starting the sender.
- Controls have a 64-entry limit and expire after 30 seconds; PULLs expire sooner
  than their request timeout. New advertisements replace older queued copies.
  Session HOLDs and obsolete PULLs are pruned when their context is no longer valid.
- An accepted HOLD extends the sender's estimate of its receiver's lease.
  A transfer stops before that estimate expires, and after 120 seconds without
  accepted data progress even when HOLDs are still getting through. ABORT is a
  bounded queued control on the data prefix, not an unverified completion.

## Sharing the sender with other addons

The normal data target remains 640 payload B/s minus measured external attempts.
The existing 36 external API-calls/s flood threshold remains. Control slots remain
reserved. Under sustained byte pressure below that API threshold, one data frame
may be probed every 15 seconds after progress stalls. It must still pass the local
API check; refusals back off and sustained failures terminate the transfer.

The probe prevents measured background traffic from indefinitely starving a
healthy data stream. It does not assume that channel, guild and whisper traffic
have independent server quotas or that a local acceptance proves delivery.

## Reading the monitors

The Rate Limiter displays **send attempts and attempted payload**, normalized by
actual elapsed time, rather than labelling them delivered bandwidth. Its 800 B/s
gauge is an addon reference, not an asserted universal WoW network limit.

MarketSync's checked sends expose accepted/refused counts and rates. Other
addons remain attempt-only observations because a post-call hook does not expose
their return codes. Prefix rows show per-transport attempt rates on hover;
Battle.net's separate transport is explicitly excluded from this measurement.

The Task Manager and printed diagnostics report the current wait reason, pending
frame, retry delay, oldest queued control, expiry/drop totals, API results and last
sender failure. A waiting transfer is no longer labelled idle merely because no
item records went out in the most recent sample.

## Validation

`tests/test_sync_reliability.js` runs the existing sync tests and then exercises
the actual Lua sender with deterministic clocks and refused API results. It covers
each frame kind, unchanged retransmissions, accepted sequence/count integrity,
permanent rejection, elapsed-time sampling, transport accounting, legacy return
values, stale controls, retrying an immediate PULL, fair probes, flood pauses,
stall deadlines and receiver-lease expiry. Live server throughput and transport
limits still need in-game observation alongside Overlord's network report.
