# Axe to Empire: logic prototype

Grey-box prototype of the Core Game Logic Spec v2. Logic first; every visual is a placeholder box or dot.
Godot 4.7.2, GDScript, Android (portrait).

## Layout

| Path | What it is |
|---|---|
| `scripts/sim/economy_sim.gd` | Economy sim (spec 2-6): 4 Hz deterministic ticks, production chain, 4 channels, staff, upgrades, gates, hint scorer, offline maths. No nodes. |
| `scripts/sim/rng.gd` | Seeded PRNG (mulberry32), one seed per in-game day |
| `scripts/sim/meta.gd` | Daily jobs + 7-day streak (spec 7.1-7.2) |
| `scripts/game/world_view.gd` | Placeholder "visual sim": draws sim state, turns taps into commands |
| `scripts/game/main.gd` | Tick loop, binary save/backup, offline popup, HUD, tabs, debug tools |
| `data/config.json` | Every number (prices, rates, growth, chapters, quests). Tune here, not in code. |
| `tests/balance_bot.gd` | Headless bot that follows the hint; prints pacing and checks determinism, save round-trip and offline |

## Commands

```sh
G=E:/Work/tools/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --script res://tests/balance_bot.gd          # balance + invariants
$G --headless --path . --export-debug Android builds/AxeToEmpire-debug.apk
adb install -r builds/AxeToEmpire-debug.apk
```

## What's in

- Chop trees (HP, regrow, golden oak with bad-luck protection), saplings, lumberjacks
- Wood pile -> campfire/oven (slots, cook time, flavor by wood type) -> dish rack cap
- Ingredients: manual crates, supplier (ch3), soft-lock free crate
- Log truck with falling sell price (exp-decayed S_recent) and a wood reserve setting
- Dine-in (queue, balk, renege, tables, eat, tips by patience, dirty/clean, waiters), takeaway, drive-through (order -> pickup in series), delivery (board -> packers -> bikes)
- Demand = base x rating x marketing x daypart x weather (Poisson, seeded per day); rushes, rain, power cut, celebrity, VIP, critic
- Rating (rolling 200) vs Fame (cumulative) split; chapter gates = rating + fame + quests + move cost
- Upgrades with Cost = C0 x g^n and x2/x1.5 milestones; best-next-action hint (blockers > gate > coins/h per coin, with 2-step lookahead)
- Offline: 60 s coarse steps with stock tracking, 50% efficiency, 2 h cap (upgradeable), "ad" doubles (placeholder)
- Daily jobs sized from your own rate, reroll, chest; streak that pauses instead of resetting
- New Venture prestige after chapter 4 (LP = floor(sqrt(lifetime / divisor)), +2% each)
- Debug tab: speed x1-x64, coins, fame, rating, complete quests, simulate 2 h / 4 days away, reset

## Not in (by design for this prototype)

Real art and animation, walking agents, server time (uses the device clock with a rollback guard), cloud save,
real ads/IAP, notifications, live events, chapters 5-9 (prestige unlocks after ch4 instead of ch9), and balance
(numbers are starting values, tuned only roughly with the bot).
