# Changelog

## 0.5.0

- The display is one icon: the next spell. Red while out of range, green while
  it isn't castable yet. The wait clock, mana potion, cooldown swirl and the
  two follow-up icons are gone; hover the unlocked display for the full plan.
- Hunter's Mark is recommended even when its tooltip names no number (its
  bonus comes from its rank).
- Hunter's Mark is no longer recommended again while it is up. Its two-minute
  bonus was valued in full when pricing mana, so every shot looked like a loss
  and the cheap re-mark won. An effect that is up and would gain nothing from
  a recast (a mark, a seal, a DoT refreshed early) is never recommended.
- Hunter's Mark is read from the target whenever the game shows its auras (out
  of combat at least), so a mark cast before a /reload counts. `/lrot probe`
  says whether the mark on your target is readable.
- Druid Bear: Demoralizing Roar and Enrage. Warrior: Demoralizing Shout.

## 0.4.1

- Out of range no longer shows the out-of-mana potion. The display keeps
  showing what to cast, tinted red, until you are in range; hovering it says
  "Out of range".

## 0.4.0

- Warrior and Shaman kits.
- Spells can share a cooldown (the Shaman's shocks).
- Tooltips: "weapon damage plus N" and "N% of your attack power" are read;
  attack power bonuses are found even with other numbers in the sentence.

## 0.3.0

- Out of mana shows a mana potion icon instead of the wait clock.
- `/lrot why` prints a decision log of your last 10 casts: what was recommended
  and why. `/lrot log` switches the log on or off (off by default).

## 0.2.0

- Paladin, Hunter and Druid kits.
- Energy, rage and combo points; weapon strikes, next-swing attacks, seals,
  range and reactive-spell checks.
- The repository is the addon folder (cloned into `_forever_/Interface/AddOns`).

## 0.1.0

- Warlock kit: look-ahead simulation scored by tooltip damage.
