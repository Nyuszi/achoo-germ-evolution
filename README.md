# Achoo! Germ Evolution

A Roblox game seen from a bird's-eye view: you are a germ inside a giant creature. Eat food and
smaller germs to grow, fight germs your own size, unlock mutations, and (from Phase 2) sneeze your
way into bigger hosts. The full design is in the Achoo! Germ Evolution design doc.

## What is in Phase 1

- Host 1 (Nibbles the Hamster) as a round dish with 4 ring zones: Nose Cave, Cheek Pouch, Tummy, Heart.
  Glowing membranes keep small germs out of deeper zones; germs above 750 are coughed out of zone 1.
- Eat-or-be-eaten PvP: swallow germs 25% smaller than you; same-size germs fight with damage.
  Eaten germs respawn in 2.5 s with 50% of their size and keep all DNA.
- Dash (Shift / button) and Split (Space / button, cells merge back after 8 s).
- Fairness: spawn bubbles, 5 s spawn shield, 10 min Quarantine for brand-new players
  (they can't be eaten; they can eat food and bot germs), revenge bonus, anti-feeding, crown + bounty.
- 4 mutations bought with DNA in the Lab: Jaws, Flagella Tail, Spikes, Shell Plates.
- Bot germs fill each server to 12 germs (Wanderer, Hunter, Coward, Bully). They leave as players join.
  They are never in the Roblox player list or player count.
- Top-down camera that zooms out as you grow (mouse wheel / pinch to adjust), golden food every 90 s,
  size board, kill feed, Bugs & Ideas button.

Not yet: sneezing into host 2, game passes and products, Germ Editor and flag skins, daily quests,
the Infinite Arena. The size stops at 2,500 (the sneeze size) until the sneeze arrives.

## Running it in Studio

1. Install the tools once with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
2. Open a new Baseplate place in Studio and install the Rojo plugin.
3. Run `rojo serve` in this folder and click Connect in the Rojo plugin.
4. Press Play. The map, bots and HUD are built by the scripts; there are no models to import.

For saving to work in Studio: Game Settings > Security > Enable Studio Access to API Services.

## Code

- `src/shared/Config.luau` – every tunable number (sizes, speeds, zones, food, mutations, bots, camera)
- `src/shared/Formulas.luau` – the pure maths (eat rules, zones, speed, camera height, DNA)
- `src/server/Services/World.luau` – the simulation: cells, food, eating, fights, dash, split, crown, snapshots
- `src/server/Services/PlayerService.luau` – players as germs, steering, mutations, DNA, respawns, HUD sync
- `src/server/Services/BotService.luau` – bot germs and their brains
- `src/server/Services/MapBuilder.luau` – builds the hamster's insides
- `src/server/Services/DataService.luau`, `FeedbackService.luau` – copied from Escape Bath Time
- `src/client/Main.client.luau` – camera, steering, keys; `Renderer.luau` draws germs and food; `Hud.luau` the interface

The server owns everything and simulates 20 times a second. Clients send only where they steer
(15 times a second) and draw the 10-per-second snapshots, smoothed.

## Checks without Studio

```
npm install
npm test                       # 47 checks of the formulas
npm run check                  # syntax check of every .luau file
node tools/sim-server.js 30    # runs the real World + bots for 30 simulated minutes
```

The simulation prints how long a careful grazing germ takes to reach each zone gate
(last run: 250 after ~3 min, 750 after ~8 min, 1,500 after ~15 min, 2,500 after ~26 min).
