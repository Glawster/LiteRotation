# LiteRotation

A light rotation helper for WoW Forever. It suggests your next spell by simulating a few casts ahead using only the
spells you know, scored by the damage in their tooltips. Because it reads your spellbook, it adapts as you level and
learn new spells or ranks, with no per-level priority lists to maintain.

It is meant for leveling. At level 60, a tuned priority helper such as Hekili Forever (which uses wowsims-derived
priority lists) will do better, because it accounts for talents, procs and gear that a tooltip-based model ignores.

## Supported classes

| Class | Spells it considers | Notes |
|---|---|---|
| **Warlock** | Shadow Bolt, Immolate, Corruption, Bane of Agony, Siphon Life, Drain Life, Searing Pain, Incinerate, Conflagrate, Wrack, Life Tap, your wand | Typically keeps Bane of Agony, Corruption and Immolate up, then wands or casts Shadow Bolt depending on mana, with Life Tap when nearly out. Off by default: Death Coil, Shadowburn, Soul Fire, Drain Soul. |
| **Paladin** | Seal of Righteousness, Seal of Command, Judgement, Holy Strike, Exorcism, Hammer of Wrath, Holy Shock | Keeps a seal up and judges it on cooldown. On Forever Judgement doesn't consume the seal. Exorcism's early ranks only on Undead and Demons; Hammer of Wrath only when the game says it's usable (target below 20%). Off by default: Consecration. |
| **Hunter** | Hunter's Mark, Serpent Sting, Arcane Shot, Aimed Shot, Raptor Strike, Mongoose Bite | Auto Shot runs by itself; Aimed Shot is charged for the Auto Shot time its cast costs. Shots or strikes are left out when the game says they're out of range. Off by default: Multi-Shot. |
| **Druid** | Caster/Moonkin: Wrath, Starfire, Moonfire, Insect Swarm. Cat: Claw, Rake, Shred, Rip, Ferocious Bite. Bear: Maul, Swipe, Primal Bite, Lacerate | Recommends for the form you're in and never suggests shifting. Off by default: Shred (it needs you behind the target, which the addon can't see). |
| **Warrior** | Heroic Strike, Mortal Strike, Bloodthirst, Slam, Battle Shout, Victory Rush; Battle: Overpower, Rend, Execute; Defensive: Revenge, Shield Slam, Rend; Berserker: Whirlwind, Execute | Recommends for the stance you're in and never suggests swapping. Overpower, Revenge, Victory Rush, Execute and Shield Slam are offered when the game says they're usable. Execute is worth more the more rage you have. Battle Shout counts for its whole duration. Off by default: Cleave, Thunder Clap. |
| **Shaman** | Lightning Bolt, Earth Shock, Flame Shock, Frost Shock, Stormstrike | The three shocks share one cooldown, so it picks the best shock for the slot. Off by default: Chain Lightning, Fire Nova. Weapon imbues, Lightning Shield and totems are not modelled. |

Other classes load the addon but stay idle. The Warlock kit is the most complete; the other kits
depend more on tooltip wording that hasn't been checked in game yet, so `/lrot spells` is the first thing to run.

## How it works

1. **Your spells.** On login, and whenever your spellbook or gear changes, it finds the highest rank you know of each
   spell in the class kit and reads its cost, cast time and cooldown from the game.
2. **Tooltip damage.** It reads damage from each spell's tooltip text. English client only. It understands:
   - direct damage ("13 to 18 Shadow damage") and damage over time ("40 damage over 12 sec")
   - per-tick effects ("10 health every 1 sec … Lasts 5 sec")
   - weapon strikes ("27 additional damage", "225% damage plus 54", "increases ranged damage by 70"), which add your
     weapon's average hit
   - combo-point finishers, one line per point ("1 point: 50-66 damage")
   - attack power bonuses (Hunter's Mark) and Life Tap's "Converts X health into Y mana"
   - Paladin seals: the damage added to each swing, and the damage the seal's Judgement deals
3. **What it tracks.** WoW Forever hides many values from addons, so the addon keeps its own record from your casts:
   - your cast in progress, the global cooldown and your cooldowns
   - your DoTs and marks on each target (the target's debuffs can't be read in combat) and your seal
   - your mana, energy or rage: the game's value when readable, otherwise an estimate kept within the range implied by
     which spells the game says you can afford. Rage income is estimated from your weapon.
   - combo points: the game's count when readable, otherwise counted from your builders and finishers
   - your weapon's damage and speed, remembered from whenever the game last showed them
   - how long the target will live: target health is hidden, so this is a guess per mob type that you can tune
4. **The simulation.** It tries every sequence of 3 actions from your enabled spells (plus your wand) and picks the one
   with the best damage per second:
   - direct hits count if they land before the target is expected to die
   - DoT ticks count up to the DoT's end or the target's death; refreshing a DoT early loses its remaining ticks
   - a seal counts for its whole duration, since it carries on to the next mob
   - next-swing attacks (Raptor Strike, Maul) are off the global cooldown and worth their bonus over a normal swing
   - spending power counts against a sequence and regenerating it counts for one, valued at your filler's damage per
     point and more heavily as your power runs low
   - combo points count for most of their share of a full finisher, so builders aren't undervalued
   - healing (Drain Life, Siphon Life) counts for a sequence and health spent (Life Tap) against it

## The display

One large icon shows the spell to cast next, with a cooldown swirl until it can be cast. Two smaller icons show the
rest of the planned sequence. When you're out of mana and nothing is castable, it shows a mana potion: drink or use a potion. While the display is unlocked, hover over it to see the plan and its score (when
locked it ignores the mouse, so clicks pass through to the game; use `/lrot log` and `/lrot why` instead).

It shows while you have an attackable target that isn't dead. Use `/lrot unlock` to drag it, then `/lrot lock`.

## Commands

| Command | What it does |
|---|---|
| `/lrot` | List the commands. |
| `/lrot lock` | Lock the display in place. |
| `/lrot unlock` | Unlock the display so you can drag it. |
| `/lrot scale <n>` | Set the display scale, e.g. `/lrot scale 1.2`. |
| `/lrot spells` | List your known spells as the simulator sees them: rank, spell ID, power and cost, cast time, cooldown, tooltip damage (and with your weapon now), combo-point damage, seal numbers, and whether each is turned off or skipped because its tooltip couldn't be read. Ends with your remembered weapon damage and speed. |
| `/lrot log [on\|off]` | Switch the decision log on or off (off by default, which saves a little work each update). While it's on, every spell you cast is recorded with what was recommended at that moment and why. |
| `/lrot why` | Print the decision log: your last 10 casts, oldest first. Each shows the spell (green if it was the recommendation, orange if not, with the score it had), the recommendation and its score, your power (read or estimated), combo points, expected target lifetime, the next-best alternatives and the planned line. |
| `/lrot toggle <spell>` | Turn a spell on or off for recommendations, using the names `/lrot spells` shows, e.g. `/lrot toggle death_coil`. |
| `/lrot ttl <sec>` | Set how long a normal mob is expected to live, in seconds (default 18). |
| `/lrot ttl <type> <sec>` | Set it for one mob type: `normal`, `elite`, `rare`, `rareelite` or `worldboss` (defaults 18, 45, 45, 60, 180). `/lrot ttl` on its own prints the current values. |
| `/lrot mana <w>` | Power weight (default 1.0), used for mana, energy and rage alike. Higher saves power (e.g. more wanding, fewer Shadow Bolts); lower spends it more freely. |
| `/lrot health <w>` | Health weight relative to mana (default 0.8). Lower makes Life Tap more attractive; higher values Drain Life's healing more. |
| `/lrot depth <n>` | How many actions to look ahead, 1 to 4 (default 3). Higher is slower. |
| `/lrot probe` | Show which game values this client lets addons read; hidden ones print as SECRET. Useful for diagnosing bad mana or DoT tracking. |
| `/lrot rescan` | Re-read your spells and tooltips. |

Settings are saved per account in `LiteRotationDB`.

### Spells that start turned off

Some spells start off for each class (see the table above): emergency cooldowns, Soul Shard spenders, spells mainly
for groups of mobs, and Shred. Turn any of them on with `/lrot toggle <spell>`.

### Tuning tips

- Mobs dying faster than expected (in a group, or much lower level): lower the lifetime, e.g. `/lrot ttl 10`, so it
  stops suggesting DoTs that won't finish.
- Running out of mana too often: raise the mana weight, e.g. `/lrot mana 1.5`.
- A spell never recommended: check `/lrot spells`; if it says its tooltip couldn't be read, the tooltip wording isn't
  understood yet.

## Installation

The repository is the addon: `LiteRotation.toc` and the Lua files sit at its root. Clone it straight into the game's
AddOns folder:

```bash
cd "<WoW install>/_forever_/Interface/AddOns"
git clone git@github.com:Glawster/LiteRotation.git
```

Then restart the game (it only looks for new addons at startup) and `/reload` after later edits. The game ignores the
repository's other files. Don't symlink the folder into AddOns instead: under Wine the client doesn't list symlinked
addon folders.

## Known limits

- English client only (tooltip parsing).
- Single target only; AoE spells are left out or off by default.
- Talents, procs (other than Nightfall's instant Shadow Bolt, when the game lets it be read), spell power and gear
  bonuses are not modelled beyond what the tooltip and cast time already show.
- Resisted DoTs are still counted as applied.
- Pets are ignored, and Druids get no advice on when to shift form.
- Hunter and Paladin melee depends on weapon damage the game may only show out of combat; the last readable value is used.

## Code layout

| File | Purpose |
|---|---|
| `LiteRotation.toc` | Addon manifest. |
| `Core.lua` | Namespace, safe reads of hidden values, settings, class kit registry, spellbook scan. |
| `Tooltip.lua` | Parses damage from tooltip text. |
| `Classes/*.lua` | One kit per class (Warlock, Paladin, Hunter, Druid, Warrior, Shaman): spell ranks, kinds and rules a tooltip can't express. |
| `Log.lua` | The decision log behind `/lrot log` and `/lrot why`. |
| `State.lua` | Tracks casts, cooldowns, DoTs, mana and target lifetime; builds the snapshot for the simulation. |
| `Sim.lua` | The look-ahead search and scoring (plain Lua, no game calls). |
| `UI.lua` | The icon display. |
| `Commands.lua` | The `/lrot` commands. |

Adding a class means writing one `Classes/<Class>.lua` kit and listing it in `LiteRotation.toc`.

## Development setup

The repository follows the OMP WoW addon standard
([documentation/wowAddon.md](documentation/wowAddon.md)). Lint and formatting
run as pre-commit hooks from the `wow` Conda environment:

```bash
conda env update -n wow -f LiteRotationEnvironment.yml
conda activate wow
luarocks install luacheck
pre-commit install
pre-commit run --all-files    # lint and format everything
```

Commit with the environment active. `~/Source/LiteRotation` is a symlink to the
repository in the AddOns folder.

## Documentation

- [WoW addon standard](documentation/wowAddon.md)
- [Changelog](CHANGELOG.md)
- [Architecture](documentation/architecture.md)
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
