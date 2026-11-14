# LiteRotation

A light rotation helper for WoW Forever. It suggests your next spell by simulating a few casts ahead using only the
spells you know, scored by the damage in their tooltips. Because it reads your spellbook, it adapts as you level and
learn new spells or ranks, with no per-level priority lists to maintain.

It is meant for leveling. At level 60, a tuned priority helper such as Hekili Forever (which uses wowsims-derived
priority lists) will do better, because it accounts for talents, procs and gear that a tooltip-based model ignores.

Supported classes: **Warlock** (first kit). Other classes load the addon but stay idle.

## How it works

1. **Your spells.** On login, and whenever your spellbook changes, it finds the highest rank you know of each spell in
   the class kit and reads its cost, cast time and cooldown from the game.
2. **Tooltip damage.** It reads damage from each spell's tooltip text: direct damage ("13 to 18 Shadow damage"),
   damage over time ("40 damage over 12 sec"), per-tick effects ("10 health every 1 sec … Lasts 5 sec") and Life Tap's
   "Converts X health into Y mana". English client only.
3. **What it tracks.** WoW Forever hides many values from addons, so the addon keeps its own record from your casts:
   - your cast in progress, the global cooldown and your cooldowns
   - your DoTs on each target (the target's debuffs can't be read in combat)
   - your mana: the game's value when readable, otherwise an estimate kept within the range implied by which spells
     the game says you can afford
   - how long the target will live: target health is hidden, so this is a guess per mob type that you can tune
4. **The simulation.** It tries every sequence of 3 actions from your enabled spells (plus your wand) and picks the one
   with the best damage per second:
   - direct hits count if they land before the target is expected to die
   - DoT ticks count up to the DoT's end or the target's death; refreshing a DoT early loses its remaining ticks
   - spending mana counts against a sequence and regenerating it counts for one, valued at your filler spell's damage
     per mana and more heavily as your mana runs low
   - healing (Drain Life, Siphon Life) counts for a sequence and health spent (Life Tap) against it

On a Warlock this typically means keeping Bane of Agony, Corruption and Immolate up, then wanding or casting Shadow
Bolt depending on mana, with Life Tap when you are nearly out.

## The display

One large icon shows the spell to cast next, with a cooldown swirl until it can be cast. Two smaller icons show the
rest of the planned sequence. While the display is unlocked, hover over it to see the plan and its score (when
locked it ignores the mouse, so clicks pass through to the game; use `/lrot why` instead).

It shows while you have an attackable target that isn't dead. Use `/lrot unlock` to drag it, then `/lrot lock`.

## Commands

| Command | What it does |
|---|---|
| `/lrot` | List the commands. |
| `/lrot lock` | Lock the display in place. |
| `/lrot unlock` | Unlock the display so you can drag it. |
| `/lrot scale <n>` | Set the display scale, e.g. `/lrot scale 1.2`. |
| `/lrot spells` | List your known spells as the simulator sees them: rank, spell ID, cost, cast time, cooldown, tooltip damage, and whether each is turned off or skipped because its tooltip couldn't be read. |
| `/lrot why` | Explain the current recommendation: mana (read or estimated), expected target lifetime, time until you can act, the value of mana, the score of each possible next spell, and the planned sequence. |
| `/lrot toggle <spell>` | Turn a spell on or off for recommendations, using the names `/lrot spells` shows, e.g. `/lrot toggle death_coil`. |
| `/lrot ttl <sec>` | Set how long a normal mob is expected to live, in seconds (default 18). |
| `/lrot ttl <type> <sec>` | Set it for one mob type: `normal`, `elite`, `rare`, `rareelite` or `worldboss` (defaults 18, 45, 45, 60, 180). `/lrot ttl` on its own prints the current values. |
| `/lrot mana <w>` | Mana weight (default 1.0). Higher saves mana (more wanding, fewer Shadow Bolts); lower spends it more freely. |
| `/lrot health <w>` | Health weight relative to mana (default 0.8). Lower makes Life Tap more attractive; higher values Drain Life's healing more. |
| `/lrot depth <n>` | How many actions to look ahead, 1 to 4 (default 3). Higher is slower. |
| `/lrot probe` | Show which game values this client lets addons read; hidden ones print as SECRET. Useful for diagnosing bad mana or DoT tracking. |
| `/lrot rescan` | Re-read your spells and tooltips. |

Settings are saved per account in `LiteRotationDB`.

### Spells that start turned off

Death Coil, Shadowburn, Soul Fire and Drain Soul start off: Death Coil is better saved for emergencies, and the others
spend or are used to collect Soul Shards. Turn any of them on with `/lrot toggle <spell>`.

### Tuning tips

- Mobs dying faster than expected (in a group, or much lower level): lower the lifetime, e.g. `/lrot ttl 10`, so it
  stops suggesting DoTs that won't finish.
- Running out of mana too often: raise the mana weight, e.g. `/lrot mana 1.5`.
- A spell never recommended: check `/lrot spells`; if it says its tooltip couldn't be read, the tooltip wording isn't
  understood yet.

## Installation

The addon is the `LiteRotation/` folder in this repository (it contains `LiteRotation.toc`). Copy or symlink that
folder into `World of Warcraft/_forever_/Interface/AddOns/`:

```bash
ln -s ~/Source/LiteRotation/LiteRotation \
  "<WoW install>/_forever_/Interface/AddOns/LiteRotation"
```

Then `/reload` in game. With a symlink, edits in the repository take effect on the next `/reload`.

## Known limits

- English client only (tooltip parsing).
- Single target only; no AoE spells.
- Talents, procs (other than Nightfall's instant Shadow Bolt, when the game lets it be read), spell power and gear
  bonuses are not modelled beyond what the tooltip and cast time already show.
- Resisted DoTs are still counted as applied.
- The pet is ignored.

## Code layout

| File | Purpose |
|---|---|
| `LiteRotation.toc` | Addon manifest. |
| `Core.lua` | Namespace, safe reads of hidden values, settings, class kit registry, spellbook scan. |
| `Tooltip.lua` | Parses damage from tooltip text. |
| `Classes/Warlock.lua` | Warlock kit: spell ranks, kinds and rules a tooltip can't express. |
| `State.lua` | Tracks casts, cooldowns, DoTs, mana and target lifetime; builds the snapshot for the simulation. |
| `Sim.lua` | The look-ahead search and scoring (plain Lua, no game calls). |
| `UI.lua` | The icon display. |
| `Commands.lua` | The `/lrot` commands. |

Adding a class means writing one `Classes/<Class>.lua` kit and listing it in `LiteRotation.toc`.

## Development setup

The repository was scaffolded with organiseMyProjects. Use the `wow` Conda environment defined in
`LiteRotationEnvironment.yml`; it holds the pre-commit tools and organiseMyProjects' `runLinter`, so commit with it
active (`conda activate wow`). The Python files (`LiteRotation/__init__.py`, `globalVars.py`, `ompr/`) belong to the
scaffold; the game ignores them.

## Documentation

- [Architecture](documentation/architecture.md)
- [Deployed Runtime](documentation/runtimeDeployment.md)
- [Roadmap](project/roadmap.md)
- [Current Increment](project/currentIncrement.md)
- [Requirements](project/requirements/requirementsIndex.md)
- [Architecture Decisions](project/adr/adrIndex.md)
- [Release Guide](documentation/howToRelease.md)
- [Repository Layout](documentation/repositoryLayout.md)
- [Requirements Management](documentation/requirementsManagement.md)
- [Testing Process](documentation/testingProcess.md)
- [Agent Workflow](documentation/agentImplementationWorkflow.md)
- [Master Agent Instructions](.github/agent-instructions.md)
