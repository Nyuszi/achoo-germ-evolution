# Achoo! Germ Evolution

A Roblox game seen from a bird's-eye view: you are a germ inside a giant creature. Eat food and
smaller germs to grow, fight germs your own size, mutate in the Lab, and sneeze your way through six
ever-bigger hosts. Finish all six and The Infinite Petri opens: an endless PvP Arena.
The full design is in the Achoo! Germ Evolution design doc.

## What is in the game

**Hosts.** Six hosts, each a round dish with 4 ring zones and its own colours and hazard:

| # | Host | Hazard |
|---|------|--------|
| 1 | Nibbles the Hamster | Whisker sweep knocks germs sideways |
| 2 | Big Barkley the Dog | Drool wave pushes everything one way |
| 3 | Grandma Trunk the Elephant | Trunk suction pulls everyone to the middle |
| 4 | Ember the Dragon | Fire burp: after a warning the outer ring burns |
| 5 | The Deep Kraken | Ink clouds hide germs inside them |
| 6 | Zorb the Alien Titan | Warp holes teleport you across the dish |

Each host is 10x bigger than the last (sneeze sizes 2.5K, 25K, 250K, 2.5M, 25M, 250M). The size
number keeps growing but the germ is drawn at size / scale, so it looks small again in every host.

**Sneezing.** Reach the sneeze size and touch the Sneeze Nerve in the middle: ACHOO! You land in the
next host with +1 Germ Point, bonus DNA and +25% growth forever. Finishing host 6 makes you a
Mutant (+50% DNA per tier) and sends you back to host 1. Mutant I unlocks the Arena.

**PvP and fairness.** Swallow germs 25% smaller than you, fight germs your size. Spawn bubbles,
spawn shield, 10 minute Quarantine for brand-new players, revenge bonus, anti-feeding, crown + bounty.

**Immune system** (every host): Whitey hunts the inner zones, antibodies slow you (+2 DNA), Macrophage
Mama (a boss with health; everyone who did 5% of the damage shares the reward), Fever (double food
and DNA) and Medicine (the wall closes in for a minute).

**The Lab.** 12 mutations in 4 slots, each with 5 levels; Front and Special mutations give Q / E
abilities (Chomp, Vacuum, Pierce, Ghost, Gravity Well, Blast). Two level-5 mutations fuse into one of
8 fusions. 6 cores (body shapes) unlock by reaching hosts. Germ Points buy permanent skills.
Builds can be saved (3 with the Extra Loadouts pass).

**The Infinite Petri.** Everyone starts each floor at size 100. Reach 700 and touch the Exit Pore to
go down a floor. Eaten = back to your checkpoint (every 10 floors). Floors roll modifiers (Low
Gravity, Fog, Fever, Spike Field, Tiny Dish, Golden Rain, Mirror, Magnet Storm, Clone Party, Giant
Whitey), go into sudden death every 4 minutes, and have 28-day seasons with ranks (Sniffle, Cough,
Fever, Flu, Plague). Paid boosts don't work there; Arena looks are bought with Arena Tokens only.
Bots fill floors 1-9.

**Germ Editor.** Bodies, patterns, eyes, mouths, hats, trails, sneeze effects, any colour, bundles,
3 outfits, and all 195 country flags (49 R$ each, a continent 199 R$, the world 499 R$).

**Coming back.** 3 daily quests, a weekly goal, login streak (day 7 = a sneeze effect), codes
(ACHOO, BLESSYOU, GERMSQUAD), invite rewards, cards (earned, never sold), global leaderboards,
a favourite prompt after your first sneeze.

**Bots** fill each dish to 12 germs, dress like players (some wear flags) and leave as players join.
They are never in the Roblox player list or player count.

## Testing in Studio (the quick way)

1. `rokit install` once, open a Baseplate place, install the Rojo plugin, run `rojo serve`, Connect.
2. Press Play. In Studio you get the **🛠 Dev** button (left side, bottom). Useful buttons:
   - **SneezeSize** puts you at the goal size next to the middle: swim in to sneeze.
   - **Host1 / Host3 / Host6** jump to a host, **Hazard** starts its hazard right away.
   - **Dna**, **MaxLab** (all mutations to level 5, try fusions), **GermPoints**.
   - **Mutant** unlocks the Arena (then 🏟️ Arena > Enter), **ArenaFloor** skips 9 floors.
   - **Whitey**, **Macrophage**, **Fever**, **Medicine**, **Golden**, **EndQuarantine**, **CompleteQuests**.
   - **Reset** wipes your progress so you can play as a brand-new player.
3. In Studio every pass and product with id 0 is free: the 🛒 Shop toggles passes on and off and
   gives products for free, the 🎨 Editor "buys" skins and flags for free. Online they stay hidden
   until you put real ids in `Config.luau`.

For saving to work in Studio: Game Settings > Security > Enable Studio Access to API Services.
The live game owner (and group rank 254+) also gets the Dev button; add friends' user ids to
`EXTRA_DEVS` in `DevService.luau`.

## Before publishing: passes and products to create

Create these in the Creator Hub (Monetization) and paste the ids into `Config.luau`:

- Game passes: 2x DNA (199), Vaccine (99), Fast Growth (249), Auto Collect (149), VIP Germ (299),
  Extra Loadouts (79), Sneeze Cam (49)
- Developer products: Revive at Size (25), Growth Potion (39), DNA Pack S/M/L (49/149/399),
  Server Fever (99), Immune Strike (79)
- Skin products, one per price: Skin25, Skin49, Skin79, Skin99, Skin149, Skin199, Skin399, Skin499
  (any skin, flag, bundle or pack of that price uses that product)

## Code

- `src/shared/Config.luau` – every number: hosts, zones, food, mutations, immune system, Arena, shop, quests
- `src/shared/Formulas.luau` – pure maths (eat rules, zones, speed, DNA, Arena helpers)
- `src/shared/Stats.luau` – turns a build (mutations, levels, fusions, core, skills, passes) into numbers
- `src/shared/Flags.luau` – the 195 countries and their flag emoji
- `src/server/Services/World.luau` – the simulation of every dish: cells, food, eating, fights, moves, snapshots
- `DishService` opens and closes dishes; `MapBuilder` builds their look; `HazardService`, `ImmuneService`
- `PlayerService` (players as germs, sneezing, respawns, HUD), `BotService`, `LabService`, `ShopService`
  (shop + Germ Editor), `ArenaService`, `QuestService` (quests, streak, codes, invites, cards, leaderboards),
  `DevService`, `DataService`, `FeedbackService`, `Bus` (game events)
- `src/client/Main.client.luau` – camera, steering, keys; `Renderer` draws germs and food, `Fx` the hazards,
  `Hud` the game screen, `Menus` every menu, `Ui` the building blocks

The server simulates 20 times a second; each dish only sends its snapshots to the players in it.

## Checks without Studio

```
npm install
npm run all                     # syntax, unknown variables, 97 formula checks, client smoke test
node tools/sim-server.js 45     # the whole server (all services, bots, a test player) for 45 minutes
EXERCISE=1 node tools/sim-server.js 4   # presses every Dev, Lab, Shop, Editor, Quest and Arena action
ARENA_AT=1 node tools/sim-server.js 12  # a test player enters the Arena after 1 minute
```

Last full run: the test player sneezed into host 2 after about 35 minutes of grazing (before the
food-decay tweak that makes it a bit faster); an Arena floor takes a few minutes.
