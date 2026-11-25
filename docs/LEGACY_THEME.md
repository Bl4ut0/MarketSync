# Legacy theme coverage

Legacy restores the original MarketSync Classic Auction House design from the
0.4-0.7 beta archives and applies it to the current interface. The archived
release supplies the artwork; current features keep their current behavior.

| Area | Legacy styling |
| --- | --- |
| Main window, Craft Manager, Item Ledger, wide dialogs | Original Auction House shell, portrait surround, gold borders and footer; larger windows extend the middle without stretching the corners. |
| Personal, Guild and Neutral browse views | Textured insets, Classic category artwork, matching headers, alternating rows, filters and paging controls. |
| Auction House scanner and Search | Textured scanner background, Classic checkbox artwork, themed live result rows, progress tracks, selection summaries and scrollbars. |
| Analytics, history and item details | Matching graph backgrounds, grid lines, separators, history rows and paging controls. Price-series colors remain meaningful. |
| Processing, crafts and ledger | Matching headers, material trees, shopping plans, receipt/history rows and scroll controls. Item quality, status and profit colors retain their meaning. |
| Shopping/Craft/Bags breakout | Matching tabs, lists, insets and bag slots. |
| Alerts and bulk import | Matching filters, row stripes and Classic frame artwork for the import dialog. |
| Settings and network tools | Matching settings cards, slider tracks, monitor headers, reference gauges and scroll controls. |
| Buttons, input fields, dropdowns and confirmation prompts | Retain the game's Blizzard control artwork and behavior. Classic scrollbars use the knob and beveled arrows instead of modern flat thumbs. |

Themes affect MarketSync-owned controls. The native Auction House, profession
windows and game settings shell remain owned by the client. Small dialogs use
matching textured Warcraft frames; clients that reject the Classic Auction
House textures receive a complete dialog fallback.

Use `/ms theme legacy` and then `/reload`. Auto chooses Legacy for the Classic
Auction House client family. Choosing a theme does not change price data,
scanner mode, recipes, purchase confirmations or ledger accounting.

`tests/test_legacy_theme.js` checks the archived shell, sizing, fallback and
theme isolation. `tests/test_theme_components.js` constructs the current pages
under both themes and exercises category artwork, import dialogs, checkboxes,
scrollbars and page navigation. Final appearance still requires in-game visual
review on the target client.
