---
title: Economy, Markets & Betting
description: One ledger with receipts, entry fees and payouts, the Market and Autofixer terminals, the player Exchange, NPC money and Billie's betting board.
---

# Economy, Markets & Betting

{{status:live}} money, receipts, Market, Autofixers &nbsp; {{status:experimental}} Exchange, Billie's board, NPC markets

## Money

- **Eddies (€$) live in one ledger.** Every payment is a ledger row with a reason. Your balance is computed from it,
  never stored loose, so it can always be explained.
- **A starting balance** is granted once.
- **Scheduled races charge entry and pay out.** Solo completion, contested placement and field bonuses are separate
  figures. Each settlement is an **itemised receipt**. Nothing is paid twice, and an aborted event refunds.
- **Practice, qualifying and custom street races mint nothing.**
- **Spending:** cars, parts, fuel, repairs, workshop labour, bets.
- Race Week's money spike is part of the lore: a flash craze. See [Race Week](race-week.md) for how wallets reset.

## The Market

- F6 → **MARKET** lists **serialized** cars and parts, filterable (ALL, CARS, PARTS, MINE, WANTED). Each listing is
  one real object.
- **Autofixer terminals** around the city are markets of their own. Stand at one and press <kbd>E</kbd> (pad
  <kbd>X</kbd>) to connect. After that, pick it in F6 Market and buy from anywhere.
- **NPCs buy too.** NPC teams buy race cars for reasons, from the same stock, and money circulates through the
  Paddock.
- A unit you produce in the Workshop can be listed on the Base Market; the buyer pays you.

## The Exchange {{status:experimental}}

F6 → **EXCHANGE** is direct driver-to-driver trade:

- One exact offer built from **machines (with their fitted parts), stored parts and eddies**, shown by identity on both
  sides.
- **Dual consent:** every edit creates a new revision, and both drivers must confirm that same revision. The whole
  trade settles together or not at all.
- **Both drivers must be online.** A machine carrying trunk cargo must be unloaded before it is traded. Persistent
  listings and escrow come later.

## Billie's Board {{status:experimental}}

**BookQueen Billie** takes positions on **NPC races**. F6 → PADDOCK → BILLIE'S BOARD.

- The board is open to read. **Writing paper takes an introduction**, and Rico knows a book (see MESSAGES).
- The price is locked when you sign. If it moved, Billie tells you to look again. There is no cancel: paper is
  paper.
- Slips have caps per slip, per day and on payout.

## For developers

- Ledger and settlement: `ncm/online/resources/ncm_league/server/economy.lua`; core `ncm/core/economy/*`. Authority:
  `docs/ncm-online/40_ECONOMY_V1.md`, L84 ("the ledger is the only balance truth").
- Market and Autofixers: `ncm_league/server/market.lua`; `docs/ncm-online/17_MARKET_NETWORK.md`.
- Exchange: `ncm_league/server/trade.lua`, core `ncm/core/economy/trade.lua`; DECISION_RECORD L194.
- Billie: `ncm_paddock/server/billie.lua`; doc 44 §9.
