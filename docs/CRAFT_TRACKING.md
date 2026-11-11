# Tracked crafts (local preview)

Open Materials & Crafting from a profession recipe or the breakout's Craft tab.
Choose quantity and Buy/Craft/Provide decisions, then **Add to Craft List**.
Selecting a pending craft loads its recipe and purchases. **Update Craft** saves
changes without losing receipts. Changing quantity or material choices rebuilds
only outstanding purchases; already paid costs remain recorded.

Each pending craft owns a temporary shopping list named for its craft and quantity,
with an owner/job suffix to prevent collisions. Partial purchases reduce required
quantities; completed material purchases delete the temporary list and mark the
craft Purchased. Removing a craft also removes its temporary list. Other shopping
lists are untouched. Use **Import Saved Plans** once to copy older named craft
sets into tracked jobs; imports are repeat-safe and preserve the original sets.

Confirmed native classic buyouts and supported modern item/commodity purchases
record actual spending. Purchases shared by several jobs fill the oldest matching
pending demand first, without counting the same units twice. Ordinary bids are
not treated as completed purchases. Failed or expired requests record no expense.
If a client or addon supplies no usable confirmation, click a material in the
purchase plan (or its green + in Shopping) to record quantity and total gold paid.
For example, `2,3.5` means two units costing 3 gold 50 silver in total.
Materials marked Provide are excluded from paid cost; their historical acquisition
cost is not inferred from market prices.

Localized player creation receipts following a profession crafting action track
output progress. A fully completed master craft moves out of Pending into
**Craft History**. **Mark Crafted** is the manual fallback for a Purchased job.
It confirms all remaining output, so use it only after completing the batch.
Intermediate crafts do not complete unrelated master jobs. Recipes without an
output item ID cannot yet be persisted as tracked jobs.

History retains purchase receipts, quantities, timestamps, and sales. Select an
entry and use **Record Sale**: `quantity,gross gold,fees gold`, for example
`1,42,2.1`. This records one item sold for 42 gold with 2 gold 10 silver in fees.
Sales are manually linked to the selected craft in this first implementation;
automatic mailbox invoice import and cancelled-auction deposit accounting are
not included. Each record shows individual sale transactions and totals.

Estimated profit uses the current saved market quote, its auction-house cut,
and recorded spending. Realized profit uses actual recorded sale proceeds minus
fees and the proportional paid material cost of the sold output. Unsold output
does not count as revenue. Jobs with supplied materials show that those costs
are excluded, so this is recorded cash profit rather than a complete inventory
valuation. Market quotes remain observations, not guaranteed sale prices.

The separate Shopping/Craft/Bags breakout keeps a short pending-craft list. It
shows outstanding materials while shopping and just craft status once ready.
Its Materials & Crafting button opens the full manager. Profession shortcuts use
the active character's detected crafting professions and cannot open in combat.

This is a local preview. Verify native confirmation, partial purchases, completed
craft detection, profession shortcuts, and actual layout in-game before release.
