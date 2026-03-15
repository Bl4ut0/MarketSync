# MarketSync: EV Arbitrage & Auctionator Export Plan

## Execution Status (2026-03-07)

- Phase 1 foundation: implemented (`ProcessingData`, `CraftingData`, EV/craft calculators).
- Phase 2 UI: implemented (`Processing` tab with target/process/craft modes).
- Phase 3 export integration: implemented (Auctionator shopping-list export for arbitrage and craft mats, including capped craft-mat terms).

## 1. Feature Description
The goal is to provide a "Reverse Breakdown" tool. Instead of users calculating EV one item at a time, they will search for a desired *material* (e.g., "Arcane Dust", "Fel Iron Ore", "Netherbloom" to mill), and MarketSync will instantly generated a list of all raw items that can be probabilistically destroyed to yield that material cheaper than buying the material itself directly.

Crucially, **users can export this generated list directly into Auctionator as a Shopping List**. This allows them to seamlessly switch to the Auction house, run a Shopping List scan, and bulk-buy the underpriced inputs.

## 2. Core Implementation Strategy

### A. Data Schema & Yield Tables
We need an embedded dataset mapping input items (or categories like "Uncommon Weapons ilvl 35-40") to their probabilistic outputs.

**Schema Example:**
```lua
MarketSync.ProcessingData = {
    [INPUT_ITEM_ID] = {
        type = "PROSPECT", -- or "MILL", "DISENCHANT"
        yields = {
            { itemID = RESULT_ITEM_ID_1, prob = 0.50, min = 1, max = 2 },
        }
    }
}
```

### B. EV Valuation & Max Buy Price
When a user searches for a target material (e.g., `ITEM_ID_TARGET = 22445` for Arcane Dust):
1. Determine the current `TargetMaterialPrice` from the MarketSync index.
2. Iterate through `MarketSync.ProcessingData` to find all `INPUT_ITEM_ID`s that yield `ITEM_ID_TARGET`.
3. Calculate the **Max Buy Price** for each input:
   - `ExpectedYield = (min + max) / 2 * prob`
   - `MaxBuyPrice = TargetMaterialPrice * ExpectedYield`
4. If the input item requires a stack of 5 (Prospect/Mill), adjust the `MaxBuyPrice` accordingly.

### C. The Data Challenge: Obtaining Probabilities
To make this work, the addon requires a dataset of what breaks down into what, and at what probability. 

**How to gather this data:**
1. **Static Community Databases:** Projects like Wowhead, TSM (TradeSkillMaster), or open-source database dumps (e.g., TrinityCore DB) contain vast amounts of crowd-sourced or extracted loot tables for Prospecting, Milling, and Disenchanting.
2. **Hardcoded Initial Pass:** We do *not* need every item in the game to provide a powerful tool. We can start by hardcoding the most relevant items for the current expansion (or the most popular classic items) and expanding over time.
3. **Disenchanting Simplification:** DE is algorithm-based rather than item-specific. E.g., any level 36-40 Uncommon Weapon has the exact same DE table. We only need the formula/tables, not a list of 10,000 weapons.

### D. UI: The Arbitrage Finder
Create a new tab or panel in MarketSync: "**Processing Arbitrage**".

To make it as easy as possible, the UI will use **Dropdown Lists** populated by our internal dataset, rather than requiring the user to type in exact item names.

**Search Modes:**
1. **Target Material Search:** User selects a material from a dropdown (e.g., `Category: Enchanting > Material: Infinite Dust`). The list dynamically shows all source items (greens, herbs) that yield it, along with their `Max Buy Price`.
2. **Profession / Process Search:** User selects a process from a dropdown (e.g., `Category: Jewelcrafting > Action: Prospecting`). The system scans the current synced index for *all* input items (ores) currently listed *below* their calculated EV.

**Results Table:** 
- Input Item Icon/Name.
- `Calculated EV` (Total value of destroyed yields based on synced prices).
- `Max Buy Price` (Target price to guarantee a specific margin).
- `Live Market Price` (If processing search is used).

### E. The Auctionator Export Integration (The Core Loop)
Provide a prominent **"Export to Auctionator"** button on the Arbitrage results page.
1. When clicked, MarketSync formats the results into an Auctionator Shopping List payload.
2. It uses `Auctionator.API.v1.CreateShoppingList("MarketSync", listName)`.
3. The exported list items are formatted with max price qualifiers where supported by Auctionator (e.g., `Cobalt Ore /exact /price < MaxBuyPrice`).
4. **User Pipeline:** The user analyzes the best deals -> Clicks Export -> Opens AH -> Clicks Auctionator "Shopping" -> Runs the newly created "MarketSync Arbitrage" scan -> Buys everything returned by the scan -> Processes them for profit.

### F. Crafting Profitability Scanner (New)
In addition to reverse-breakdown (buying cheap items to mill/prospect), we can do **Forward Crafting Profitability**.

**How it works:**
1. **Recipe Knowledge Base:** The addon stores a database of popular endgame recipes (enchants, flasks, gems, crafted gear), or dynamically reads the user's currently known recipes by scanning their opened profession window (`GetTradeSkillLine()`).
2. **Profit Calculation:**
   - **Crafting Cost:** Sum of `Material_Quantity * Lowest_AH_Material_Price`
   - **Revenue:** `Lowest_AH_Crafted_Item_Price` (minus the 5% AH Cut).
   - **Margin:** `Revenue - Crafting Cost`.
3. **UI Integration:** A "Profitable Crafts" tab where users can select a profession (e.g., "Alchemy"). The UI lists all recipes where `Margin > X gold`.
4. **Export Flow:** The user clicks "Export Mats to Auctionator". MarketSync generates a shopping list of all the raw materials needed to mass-produce the profitable items, capping the buy price so the profit margin is guaranteed.

## 3. Phased Implementation

**Phase 1: Foundation & Probability Data**
- Build the core data structures for Prospecting, Milling, Disenchanting, and Crafting Recipes.

**Phase 2: EV Calculation & Arbitrage UI**
- Build the target-search UI where users input the material they want, or the profession they want to profit from.
- Wire the EV math to dynamically calculate Max Buy Prices / Profit Margins based on the synced index.

**Phase 3: Auctionator Export Integration**
- Implement the translation layer that converts both "Reverse Breakdown" results and "Profitable Crafting Mats" lists into Auctionator Shopping Lists.

## 4. Challenges & Edge Cases
- **Missing Market Data:** If the user hasn't synced or scanned recently, the price of the *resulting* gems/dusts might be 0 or heavily outdated, resulting in horribly inaccurate EV. The system must flag EVs derived from stale data or fall back gracefully.
- **DE Randomness Variations:** Disenchanting tables differ slightly between weapons and armor of the exact same item level. The DE table lookup must account for equipment slots.
- **Data Maintenance:** Blizzard occasionally tweaks drop rates or adds new items. We might consider crowd-sourcing or scraping this data rather than hand-coding thousands of rows.
