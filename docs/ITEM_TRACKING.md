# Item and customer-craft tracking

> **Beta Status**: The Transactional Item Ledger is an experimental beta module and is **auto-disabled by default** (`MarketSyncDB.EnableLedgerBeta = false`). To enable it, navigate to **Game Menu → Options → AddOns → MarketSync → Beta & Experimental Features → Enable Transactional Item Ledger**. When disabled, all Ledger UI buttons (MainFrame title bar, Craft Manager header, item context menus, and minimap shortcuts) are dimmed and disabled. Lightweight multi-character inventory tracking continues running in the background for tooltip counts with zero ledger overhead.

This local preview adds a persistent local ledger alongside craft orders, organized in a dedicated modular subsystem (`MarketSync/Ledger/`). When enabled, open the Ledger directly via **Minimap Right-Click**, the **Ledger** button in the MarketSync header bar, the optional **2nd Ledger Minimap Icon** (`Settings → Show dedicated Ledger Minimap Icon`), `/ledger`, `/msledger`, or **Materials & Crafting Choices → Item Ledger** to inspect inventory, exchanges, cost lots, and unresolved movements. Nothing is sent through guild sync.

## Ledger Architecture & Design C Interface (`MarketSync/Ledger/`)

The Ledger subsystem is structured under `MarketSync/Ledger/` (`CraftLedger.lua`, `PurchaseList.lua`, `ItemLedger.lua`, `InventoryTracking.lua`, `UI_CraftManager.lua`, `UI_ItemLedger.lua`, and `UI_PurchaseList.lua`) and uses **Design C (Progressive Hybrid)**:
- **4 Top-Level KPI Cards**: Realized Net Profit, Active Character Stock & FIFO Value, Pending Craft Orders & Auto-Tagged Materials, and Needs Review / Unresolved count.
- **3 Progressive View Modes**:
  1. **In / Out Activity**: Chronological transaction stream with quick **Flow Filter (`Flow: In & Out`, `+In Only`, `-Out Only`)** and source filters.
  2. **Character Stock & Lots**: Aggregated item catalog across all characters with an inline **Per-Item In/Out History Drawer** when an item is selected.
  3. **Needs Review**: Filtered queue of ambiguous or unconfirmed exchanges requiring attention.
- **Automated Accounting Cards**: The right-hand detail inspector surfaces dedicated cards for **Auto-Tagged Craft Materials**, **Zero-Cost Guild Craft Round-Trips**, **Crafting Value Gained (vs. Raw Mat AH Value)**, and **30-Day Compacted Rollups**.

## Ownership and availability

Bags, equipped items, bank contents, and mailbox attachments are saved separately
for each observed character and client/market partition. Bank/mail counts update
when that storage is accessible. Offline characters show last recorded counts,
not live counts. Mailbox snapshots identify partial inbox loads.

Enter an item ID or link in Item Ledger to list characters, quantities, storage,
and snapshot ages. Item tooltips and craft materials also show other characters'
stock. **Settings → Show items on other characters** hides these extra displays
when a bag addon already provides them. The setting leaves bookkeeping active.

## Tooltip Presentation & Modifier Controls

To avoid oversized tooltips while keeping crucial data accessible, MarketSync splits
item information between a compact default view and an expanded details view triggered
by holding a modifier key (`Shift` by default, configurable to `Ctrl` or `Alt`).

### Compact View (Default)
When hovering over an item without the modifier key:
- **Multi-Character Inventory (Syndicator style)**: Shows a 1-line total followed by
  clean, consolidated character breakdowns (e.g., `Main: Bags 10, Bank 20`).
- **Auction House Price**: Clean 1-line current buyout price and scan freshness age.
- **Disenchant / Prospect / Milling Value**: Compact 1-line Expected Value (`Disenchant Value: 85s`).
- **Pending Craft Demand**: Summarizes materials needed across active craft ledger jobs
  (e.g., `Pending Crafts: Need 12 (3 jobs · 4 reserved)`), plus queued output items.
- **Modifier Hint**: Displays `<Hold Shift for full details>` (or the configured key)
  whenever hidden data is available.

### Expanded View (Modifier Held)
Holding the modifier key dynamically refreshes the open tooltip without requiring
re-hovering (`MODIFIER_STATE_CHANGED`), revealing:
- **Per-Storage Snapshot Details**: Exact storage locations with per-storage timestamps
  and partial mailbox warnings (`Main (bags): 10 [12m ago]`).
- **FIFO Cost Basis**: Average unit cost and units tracked across recorded acquisition lots.
- **Detailed Job Requirements**: Individual craft order names, quantities, and customer attribution.
- **Disenchant / Milling Odds**: Complete drop probability tables, output item names, and
  quantity ranges.
- **Ground-Up Craft Breakdown**: Full tree of intermediate components and farm vs. buy options.

### Settings Configuration
- **Show items on other characters**: Toggles character holdings display on tooltips.
- **Show Pending Craft Demand on Tooltips**: Toggles active job requirement lines.
- **Details Modifier Key**: Configures the key used to expand tooltips (`Shift`, `Ctrl`, or `Alt`).

Available on an alt does not mean ready on the crafting character. Transfer the
materials first. Save a **Provide** decision and use **Reserve own stock** to
assign the saved quantity from observed local inventory. Reservations cannot
claim the same units twice, and their known costs follow intermediate crafts.
Unexplained inventory losses invalidate affected reservations/cost assumptions.

## Transactions and values

The ledger records confirmed mail sends, attachment/money collections, completed
trades, supported auction purchases, self-loot receipts, supported vendor
purchases/sales, and tracked crafting output. Other inventory changes remain
unresolved observations rather than invented purchases, revenue, or craft events.

Mail collection requires both mailbox change and matching inventory/money change.
A trade requires acceptance and the server's completion message. Clicking Buy,
Send, Take, or Accept alone does not establish a completed exchange. Duplicate
notifications and repeated requests do not create another confirmed receipt.

Each exchange retains quantities, counterparties, evidence, gold in/out, and
postage/fees. Confirmed acquisition cost and estimated saved market value are
separate. Unknown cost is shown as unknown, not zero. **Set actual cost** corrects
an intact, unreserved acquisition lot; consumed/customer lots require review.

Matching mail between observed owned characters carries the original cost lots
without creating another acquisition expense. Partial attachment collections can
be linked to the same send. Unique matches are automatic; ambiguous matches need
**Link own-character mail**, using transaction IDs. A returned mail can also be
linked explicitly to its original outgoing record. This is local history, so
old mail sent before tracking began has no recoverable original cost record.

Auction purchase confirmations record spending even with no selected craft.
Collected buyer invoices can connect delivered items to an unambiguous purchase.
For sales, select the associated craft and a collected seller invoice, then use
**Link sale invoice**. Values must reconcile with collected gold, including the
returned deposit. Ambiguous invoices use **Record Sale** and manual review.

COD charges are separate from observing COD mail. A charge spanning several
attachments is recorded once, with per-item allocation left unresolved. Deposit
refunds, earned-payment refunds, postage and actual service payments stay distinct.

## Customer-supplied crafting

1. Save the craft, select **Customer Craft**, and enter the customer's name.
2. Open Item Ledger for that order. Select confirmed received materials and
   click **Customer materials**. They become customer property, reduce the
   outstanding shopping requirement, and stay separate from owned inventory.
3. Craft the components and master output. A unique matching intermediate order
   retains customer custody; ambiguous intermediates require review. Confirmed
   creation receipts and inventory changes advance output progress. Professions
   without a normal output item use manual completion.
4. Return the output by mail or trade. Select that confirmed exchange and use
   **Output returned**. Partial deliveries remain linked to the order. For an
   outgoing exchange containing only excess supplied materials, **Customer
   materials** links their return instead.
5. Link actual gold using **Service payment**, **Own expense**, **Deposit**, or
   **Refund**. One trade can contain both materials and a payment; each role is
   counted once. Deposits do not become earned revenue automatically.

Customer materials and returned goods contribute no market-value income or
expense. An unpaid craft creates no monetary gain. Real payment minus the user's
recorded contributions and attributable expenses determines service profit.
Unknown user costs keep profit incomplete. Normal sale recording is disabled for
customer output to prevent also counting the returned item as a sale.

Incoming items/gold from other players stay unassigned until explicitly linked, with two automated lifecycle enhancements:
- **Automatic Material Tagging (`I.AutoTagMaterials`)**: Confirmed incoming material purchases or receipts are automatically tagged against active pending craft orders that require that item (`autoTaggedJobs`), keeping material acquisition connected to your active crafting queue.
- **Automatic Zero-Cost Guild Craft Round-Trip Linking (`I.AutoMatchGuildCraft` / `I.LinkGuildCraft`)**: When a player receives materials from a counterparty for `0c` (free trade or mail), crafts a matching recipe, and returns the crafted output to that same counterparty within 30 minutes (`1800s`), the ledger automatically links the round-trip as a **Zero-Cost Guild Craft** (`guild_craft`). Material cost is recorded as `0c` (preventing false negative expense against personal profit), and any tip included in the trade/mail is captured as pure service gain.
- **Crafting Value Gained vs. Raw Material AH Sell Value (`I.EvaluateValueGained` & `L.Totals`)**: In addition to tracking Actual Realized Profit against FIFO Paid Cost, the ledger calculates the opportunity value of the raw materials if sold directly on the Auction House (`matMarketValue` and `matNetAH` after the 5% AH cut) and reports `valueGainedVsMats` so crafters can see whether crafting added value over selling raw materials.

If an outgoing item could belong to the user or a customer and does not match an automatic round-trip, attribute it explicitly with the service controls or **Outgoing: own stock**.

## Tiered Ledger Compaction (`I.TrimLedger`)

To prevent `SavedVariables` bloat over months of trading and crafting while preserving long-term financial history:
- **Hot Granular Window**: Full transaction records, evidence trails, and audit metadata are kept for the configured retention period (`MarketSyncDB.LedgerRetentionDays`, default **30 days**, configurable to **14 / 30 / 60 / 90 days** in Settings).
- **Primary `+/-` Rollup Archive (`store.rollups`)**: Records older than the retention window are compacted by `MarketSync.ItemLedger.TrimLedger()` into lightweight per-item (`qtyIn`, `qtyOut`, `goldSpent`, `goldEarned`, `guildCraftCount`) and overall gold `+/-` rollup summaries (`I.GetRollupSummary()`).
- **Safety Preservation**: Active unconsumed FIFO cost lots, reserved stock, active craft job links, and unresolved records are never trimmed until settled.

## Corrections and recovery

Use **Record crafted qty** for confirmed output missed by automatic detection.
The ledger's **Correct** control accepts `crafted,total` or
`itemID,totalPurchasedQuantity,totalGoldPaid` and retains an audit record. Lowering
completion cannot erase sold/delivered output and marks uncertain material costs
for review; it does not pretend that game inventory was physically rolled back.

Saved transactions, jobs, cost lots, reservations and ownership survive reloads.
In-flight actions lacking confirmation remain unresolved; a later snapshot does
not fabricate their origin or price. A reload cannot reconstruct events that the
client never exposed. Review those records and correct the relevant order.

## Verification and client limits

Automated tests cover lifecycle and isolation, unknown versus known costs,
reservations, owned-character transfers, customer custody, free and paid services,
deposits/refunds, duplicate craft messages, partial mail collections, cancelled
trades/mail, bank visibility, settings, and persistent saved facts.

Before a public release, test actual client event ordering, bank/mail access,
tooltips, and layout in-game on Forever, Era/Anniversary, and modern clients.
Storage or transactions with no reliable accessible API stay unknown/unresolved.
Shared account/guild storage is not silently attributed to a specific character.
