# Axe to Empire — Game Design

Arcade-idle cooking tycoon. You run, chop, cook and serve yourself; your crew keeps a venue
ticking while you're elsewhere. The player is always the engine of growth: playing beats idling.

## 1. Story: "Axe to Empire"

**Old Mags** ran the Forest Camp for 40 years and hands you her axe. **Victor Grayline**
(Grayline Lumber Co.) is buying up the valley, clear-cutting it and running every place into
the ground. You win the valley back the other way: chop *and replant*, feed people well,
hire locals. Each chapter wins over one place and one ally; each ends with a **Big Day**.
Each new place is the plot next door on the same road: you expand one business, you don't start over.

| # | Venue | Guests | Ally | Story | Big Day |
|---|---|---|---|---|---|
| 1 | Forest Camp | hikers (patient) | Ranger Doyle | Prove the trail brings visitors so Grayline can't log it | **Trail Festival**: a crowd of hikers |
| 2 | Roadside Shack | truckers (impatient) | Rosa | Win the truckers away from Grayline's vending stops | **The Convoy**: trucks at the counter and the drive-thru |
| 3 | Lakeside Diner | anglers (very patient, big orders) | Finn | Raft logs to Finn's free mill instead of Grayline's | **Fishing Tournament**: big hungry crowd |
| 4 | Mountain Lodge | skiers (cold, low patience) | Ingrid | Grayline cut the windbreak; keep the lodge warm | **Blizzard**: patience crashes unless the fire burns |
| 5 | Autumn Smokehouse | fairgoers | Fair committee | Grayline's rival stand steals guests from long lines | **Fair Finale**: out-serve the rival stand |
| 6 | Grand Timber Hotel | hotel guests + VIPs | Mr. Bell | Buy back the hotel Grayline ruined | **The Critic**: a VIP party decides the review |

After chapter 6 Grayline leaves the valley; **New Empire** sends you to the next valley
(prestige, +50% income per empire).

Story is delivered as short portrait cards (`data/story.json`): chapter intro, ally lines on
milestones, Grayline moments, first walkout / low rating warnings, Big Day intro / win / fail.
Each card shows once per venue.

## 2. Moment-to-moment loop

Chop → carry logs to the woodpile → fires cook → carry dishes to the counter → guests pay →
collect cash → build / upgrade. Logs can also be sold at the truck (player only).

### Customers: crowds, moods, walkouts
- New guest every ~3 s (scaled by demand), group arrivals every 2–3 min.
- The line holds up to 12 and snakes in two rows. A full line means new guests walk past ("Too busy!").
- Mood over each head follows the share of patience used:
  - 😊 happy (<50%): pays +20%, 5★
  - 😐 impatient (50–80%): pays normally, 4★
  - 😠 angry (80–100%): pays normally, 2★
  - walks out (>100%): 1★, sale lost, and the 2 guests behind lose 10% patience
- Patience per chapter: 30–42 s, plus dining upgrades and the lodge fireplace.
- **Hands-on bonus:** guests served while *you* stand at the counter pay +25%.
- Rating below 3.5★ means fewer guests (and a warning from Mags).

### Player vs crew
| Job | Crew | You |
|---|---|---|
| Chop | Slow (1.6 s per swing), fills the woodpile only | Fast, better tools |
| Sell logs at the truck | Never; waits at a full pile | Yes |
| Carry dishes | 2 at a time | 4 |
| Signature station | From station level 5 | Always |
| Golden trees, Big Day | Can't | You |

Crew costs (chapter 1, scaled by chapter):
- Lumberjack: 600 / 1,800 / 4,500
- Waiter: 900 / 2,800
- Cook: 1,200 / 3,500

**Golden tree:** every ~2.5–3.5 min one tree near the camp glows for 25 s. Fell it for a cash
burst (15× dish price). Only the player can chop it.

## 3. Long-term depth (the Clash-of-Clans layer)

### Station levels (1 → 25, per venue)
| Station | Effect per level |
|---|---|
| Kitchen | −5% cook time |
| Menu | +12% dish price, ×1.25 at every 5th level; recipe names change at levels 7, 13, 19 |
| Dining | +2% patience, +1% seated tip |
| Signboard | +4% guests |
| Signature station | +6% station bonus; at level 5 the crew starts using it |

Costs grow ×1.3 per level. **Levels 5, 10, 15, 20 and 25 are renovations**: they take real
time (2 min, 10 min, 30 min, 1 h, 2 h), one at a time per venue. The station keeps working
during a renovation, and timers keep running while you're away.

### Chapter stars ★★★ (per venue)
- ★1: win the Big Day.
- ★2: hold a 4.5★ rating after serving twice the gate's guest count.
- ★3: every station at level 15 or higher, and the Big Day won with no walkouts.

Each star gives +4% income everywhere.

### Chapter task chain
Each chapter has an ordered list of 8–12 tasks (build X, hire Y, serve N, reach level L, chop a
golden tree, win the Big Day…). The current task shows on screen with progress and a cash
reward, so there is always a clear next job.

### One world, earn while you play
- The six places sit side by side along one road. Winning a Big Day lets you buy the land next
  door and expand; you walk over (or jump there with MAP). Nothing is "from scratch": your cash,
  tools, bag and boots come with you, and every place you own keeps running.
- While you play, each place you're not at earns 50% of its crew rate (`Game.VENUE_EFFICIENCY`).
  That cash piles up on that place's own counter (its *till*), up to 20 minutes of its rate
  (`Game.TILL_CAP_MIN`). Walk over to collect it.
- The HUD shows a "$X waiting at <place>" chip (the place with the most) under the task card;
  tapping it opens MAP, which lists each place's till, its cap and what it earns per minute.
- No away earnings: nothing piles up while the app is closed (`offline.enabled = false`). The game
  truly pauses when the phone locks or the app goes to the background (audio stops, nothing ticks).
  Renovation timers use real time, so they still finish.

### Daily layer
Daily jobs, a 7-day streak chest, renovation timers finishing.

## 4. Pacing targets
- Chapter 1: ~25–30 min to the Big Day.
- Chapters 2–6: ~40–50 min each to the gate.
- Then days to weeks of renovations and stars.
- First crew hire around minute 8–10; full automation near the end of a chapter.

## 5. Roadmap (post-launch updates)
| Update | Content |
|---|---|
| 1.1 | **This build**: crowds and moods, crew rebalance, cash, station levels, renovations, stars, story, Big Days, task chain |
| 1.2 | New Valleys (endless prestige with modifiers: heat, storms, fast-burning fires) and an Empire Token upgrade tree |
| 1.3 | Google Play Games: leaderboards, cloud save, achievements |
| 1.4 | Seasonal events (Halloween camp, winter festival), collections (recipes, outfits, axe skins) |
| 1.5+ | A new chapter per update (Desert Diner, Island Fish Market, Railway Dining Car, City Steakhouse) |
| 2.0 | Online co-ops (clans) and Grayline Raids (co-op weekend event) |
