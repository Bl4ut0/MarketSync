# Craft management implementation requirements

Status: implementation plan and handoff from the side conversation. This document does not indicate that the features are implemented.

Implementation update: the local preview now contains inventory snapshots, the
ownership-display setting, transaction/cost tracking, linked customer crafts,
reservations, corrections, and automated verification. See [Item tracking](ITEM_TRACKING.md)
for implemented behavior, manual attribution paths, and the remaining in-game
acceptance checks. The requirements below remain the specification; inaccessible
or ambiguous client events are intentionally unresolved rather than inferred.

## Confirmed interface direction

- Expand Materials & Crafting Choices using Option B: recipe breakdown, purchase plan, and a right-hand Craft Management pane.
- Replace Export to Shopping with Add to Craft List.
- Craft Management lists clickable pending master crafts and their quantities. Selecting one opens its saved material decisions and progress.
- Keep manual controls in Materials & Crafting Choices: Buy/Craft/Provide decisions, supplied quantities, progress corrections, and clearing a pending craft.
- Keep the craft breakout compact: a short status summary and a button opening Materials & Crafting Choices.

## Remaining implementation work

### Persistent craft orders

- Store each order with a stable ID, character/market ownership, master recipe, requested and completed quantities, recipe yield, saved decisions, material requirements, and fulfillment progress.
- Preserve orders across reloads and reconnects. Reopening an order must not create a duplicate order or shopping list.
- Give each order a linked temporary shopping list named for the craft and requested quantity, for example Nitro Boosts ×2. Use the stable order ID internally so identical names remain distinguishable.
- Include only remaining materials selected for purchase. Exclude provided materials and intermediate items selected for crafting; include the purchased ingredients needed to craft those intermediates.

### Purchase monitor

- Confirm successful purchases and quantities through the appropriate client auction APIs/events. A submitted purchase or button click alone is not proof of success.
- Handle partial purchases, stack quantities, failed purchases, and duplicate or repeated event delivery.
- Allocate shared-material purchases deterministically among eligible orders. Never credit the same purchased unit to multiple orders.
- Distinguish confirmed purchases from usable inventory/mail delivery, where the client exposes that distinction. Do not infer purchase completion solely from a matching item entering bags.
- Remove fulfilled material entries from the linked temporary shopping list. Delete the temporary list when its purchase requirements are fully fulfilled.
- Mark the master craft Purchased when its shopping requirements are fulfilled, but keep it pending until crafted or manually cleared. Purchased does not guarantee that mailed materials have been collected or that the recipe is currently craftable.
- Orders with no required purchases should not create empty shopping lists; represent their shopping requirement as already satisfied.

### Craft monitor

- Observe confirmed successful crafting using client-appropriate recipe/output events. Starting, cancelling, or failing a cast must not complete an order.
- Match the master recipe, character, and output quantity; account for multi-output recipes and partial batches.
- Track intermediate crafting separately from master completion. Making a component must not finish the master craft.
- Reduce the pending master quantity after each successful craft; remove or complete the order when its target is satisfied.
- Support profession actions without normal item outputs where reliable confirmation is available. Otherwise expose manual completion instead of guessing.
- Clear the order's linked temporary shopping state on completion or manual clearing, without deleting unrelated user lists.

### Reconciliation and corrections

- Persist idempotent fulfillment state and safely reconcile after reloads, reconnects, and delayed events. Where an event cannot be recovered reliably, retain known progress and offer correction rather than inventing completion.
- Editing quantity or Buy/Craft/Provide decisions must recalculate remaining requirements without losing valid fulfilled quantities or reusing allocated materials.
- Keep user-created shopping lists separate from generated lists. Establish the policy for manual deletion/editing of a generated list and preserve the master order until explicitly cleared or completed.
- Define how purchases outside MarketSync and existing bag materials are recognized; use manual Provide controls when attribution cannot be established reliably.

### Character inventory and optional ownership display

- Show which of the user's characters owns an item, with per-character quantities and storage location (bags, bank, mailbox where observable), in item tooltips and material availability details.
- Add a Settings toggle named Show items on other characters, enabled by default. Disabling it hides MarketSync's additional ownership display so users can rely on their bag addon's display instead.
- Keep the ownership display toggle separate from internal inventory and reservation tracking; hiding duplicate information must not change craft fulfillment or shopping calculations.
- Store character identity, client/market partition, and snapshot timestamps. Offline inventory is last recorded information, not a live count; show its age. Unknown storage is unknown, not zero.
- Update snapshots only when the client exposes the relevant storage. Identify materials on another character as requiring transfer, rather than immediately usable by the crafting character. Do not count incompatible client or faction inventories as available without an explicit supported transfer policy.
- Reserve available quantities against individual craft orders so one physical unit cannot satisfy several pending requirements. Reconcile transfers without recording them as new purchases or duplicating stock.
- This section is planned work; it does not claim that inventory tracking or the setting already exists.

### Item movement ledger, mail, and value attribution

- Track observable item inflows, outflows, and storage movements for all items, independently of whether they belong to a craft order. Craft orders consume or reserve allocations from this broader ledger; an item does not need an assignment to be recorded.
- Include received and sent mail attachments and money, transfers between the user's characters, mail from other players, auction purchases and sales, trades, vendor transactions, loot, crafting inputs/outputs, use, destruction, and storage moves where the client provides reliable signals. Mark unsupported or ambiguous paths as unresolved rather than claiming complete event coverage.
- Record item/variant identity, quantity, character, source/destination, observed time, transaction type, and confirmation/reconciliation state. Preserve sender/recipient information when available. Reading mail, taking attachments, and deleting mail must not record the same items as separate acquisitions.
- Separate items observed in a mailbox, items actually collected into bags, and items sent but not yet observed at their destination. Report unopened or offline mail from its last observed snapshot; do not claim live knowledge of another character's mailbox.
- Match transfers between owned characters when evidence supports the match. Move quantity and known cost basis with the items instead of counting a second purchase, income, or profit. Include postage as a separately identified cost. Do not invent a reliable cross-character mail transaction ID if the API supplies none; retain ambiguous matches for reconciliation.
- Record attachments and money received from other players even when no craft is selected. Keep these in unassigned inventory/transactions until explicitly allocated or reserved by a documented rule. Receiving materials must not fabricate an AH purchase or automatically attribute unrelated mail to a craft.
- Preserve separate value fields: confirmed acquisition cost, confirmed sale proceeds, fees/postage, and estimated market value with quote source and timestamp. Unknown acquisition cost remains unknown; gifts may be explicitly classified as gifts, but ordinary incoming mail must not silently acquire zero cost or an estimated purchase cost.
- Handle COD mail separately: observing the mail is not payment. Record actual COD payment when confirmed; if a single payment covers several attachments, keep the shared cost unresolved until an allocation rule or manual correction establishes per-item cost.
- Support partial attachment collection, returned/expired mail, stack splits/merges, partial transfers, and partial consumption. Reconcile paired storage events rather than treating bag-to-bank moves as acquisitions or losses.
- Maintain quantity and cost-lot allocations with a documented deterministic policy. Reservations and downstream crafting must not consume the same units or their cost twice; unresolved costs must remain visible in profit reports.
- Persist the ledger and reconcile storage snapshots after reloads/reconnects. Snapshot differences can identify an unresolved movement, but cannot establish its source, transaction price, or successful craft without supporting evidence.
- Provide a transaction history view for unassigned receipts, movement details, value provenance, and manual attribution/corrections. Keep inventory facts separate from craft-plan edits.
- This is an expansion of the planned scope, not a claim that every movement can already be monitored or that every client exposes all required events.

### Customer-supplied crafts and linked exchanges

- Support a customer-supplied/commission craft classification alongside crafts made for the user's own stock. Link incoming materials, the successful craft, outgoing finished items, and any actual gold exchanged to a service order.
- Accept linked legs across completed trades or observed mail transactions: materials traded in and output traded back, materials mailed in and output mailed back, or mixed delivery methods. Preserve counterparty, item quantities, and event evidence for each leg.
- Record every physical movement for inventory reconciliation, but exclude the estimated value of customer-owned materials and returned outputs from the user's sales revenue, material spending, inventory valuation, and profit totals. Maintain a separate custody quantity for customer property.
- Materials received for a service are not free inventory acquired by the user. Creating the output converts the customer's supplied materials into customer-owned output until it is returned or ownership is explicitly changed.
- A completed service with no monetary payment contributes no sales revenue or monetary gain from the returned goods. If the user supplies materials, pays postage, or incurs other confirmed costs, report those costs separately and do not imply that a zero-payment service was cost-free.
- Record gold actually exchanged, in either direction, only after trade/mail confirmation. Classify linked amounts as service payment, reimbursement, deposit, refund, change, or payment to the customer as appropriate; do not count deposits or refunds as earned crafting revenue by default.
- Calculate service profit from earned payment/reimbursement minus the user's attributable acquisition costs and fees/postage. Customer-supplied materials contribute neither a fabricated acquisition expense nor market-value revenue. Unknown user costs make the result incomplete rather than silently zero.
- Retain unassigned trades/mail and payments until their purpose is established. Offer suggested links using counterparty, recipe, quantities, and timing, but require explicit attribution when ambiguous. Unmarked item receipts alone must not create sale income or infer a paid commission.
- Handle partial material delivery, partial batches, multiple customers supplying the same item, partial returns, excess material returns, and mixed user/customer materials without crossing custody or cost allocations between orders.
- Show the linked service in Craft History with supplied materials, user contributions, output delivered, outstanding returns, actual payments, and monetary result. An unpaid/zero-payment service must remain traceable without inflating aggregate gains.
- Keep overall cash movement reporting distinct from earned revenue/profit: unassigned gold can be recorded as a cash movement while remaining unclassified for craft profitability.

## Acceptance checks

- Partial purchases update the correct order and shopping quantities; failed purchases do not advance progress.
- Two orders needing the same material never receive duplicate credit for one purchase.
- Repeated events and reopening the window do not duplicate orders, purchases, or completion.
- Completing shopping deletes only the linked generated list and leaves the master craft marked Purchased.
- Crafting components does not complete the master. Partial and multi-yield master crafts update quantities correctly.
- Reloading preserves progress. Clearing an order removes its generated list without affecting other orders or ordinary shopping lists.
- Verify supported legacy, Forever, and modern client event paths separately; do not assume their purchase/craft signals are interchangeable.
- Ownership displays identify the correct character, quantity, storage, and snapshot age. Disabling the display removes the added information without disabling craft bookkeeping.
- Moving materials between characters does not create purchase receipts or duplicate reserved stock; offline or unobserved storage never appears as confirmed current inventory.
- Unassigned mail from other players appears in the ledger without creating a craft order or a fabricated purchase cost.
- Observing mail, collecting individual attachments, reopening the mailbox, and reloading do not duplicate acquisitions. Sent/received owned-character transfers preserve quantities and known cost basis.
- COD, postage, returned mail, ambiguous transfer matches, unknown costs, and estimated values remain distinguishable; profit never silently substitutes market estimates for actual acquisition costs.
- Receiving customer materials, crafting them, and returning the output without payment records a complete linked service without adding market-value revenue or gain.
- A paid service counts the earned payment and the user's own attributable costs once; customer materials, deposits, refunds, and returned excess supplies do not inflate profit.
- Ambiguous or partial trade/mail exchanges stay attributable and reconcilable without assigning one customer's materials or payment to another customer's order.
