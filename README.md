# PhantomPower

A from-scratch Paladin blessing and utility manager for **World of Warcraft: Forever**.

Target: WoW Forever 1.60.1 / Interface 16001
Version: 0.1.1

## What v0.1 does

- `/pp` toggles the main window. (`/phantompower` and `/phantom` also work.)
- Assigns one of the current Forever raid blessings to each class:
  - Blessing of Might
  - Blessing of Wisdom
  - Blessing of Kings
  - Blessing of Salvation
  - Blessing of Light
- Left-click a class **Buff** button for the matching Greater Blessing (when learned).
- Right-click the same button for the regular Blessing.
- Out of combat, the regular Blessing button points at the first group member of that class who appears to be missing the assigned blessing.
- Shows `buffed / total` for each class while aura data is readable.
- Aura selector/caster for Devotion, Retribution, Concentration, Shadow Resistance, Frost Resistance, and Fire Resistance Aura.
- Seal selector/caster including the new **Seal of Fury**.
- Righteous Fury cast button.
- Secure cast buttons and assignment changes respect combat lockdown.

## Forever-specific assumptions

This build intentionally targets the modern WoW Forever addon API rather than Classic Era/Turtle WoW APIs.

Current Forever beta data used by this release:

- Interface: `16001`
- Blessings last 60 minutes.
- Greater Blessings last 60 minutes.
- Blessing of Kings is baseline/trained.
- Blessing of Sanctuary / Greater Blessing of Sanctuary are not included in the current Forever ability set.
- Seal of Fury is included (spell ID 1311649).
- Judgement not consuming seals means this addon does not attempt old-style post-Judgement seal rebuff logic.
- Aura reads can become restricted/secret; v0.1 freezes assignment target updates in combat instead of trying to infer protected state.

## Install

1. Put the `PhantomPower` folder directly inside your WoW Forever `Interface/AddOns/` folder.
2. Restart the client if this is a brand-new addon folder.
3. Enable **PhantomPower** at the AddOns screen.
4. Log into a Paladin and type `/pp`.

## Commands

- `/pp` - toggle window
- `/phantompower` or `/phantom` - toggle window aliases
- `/pp scan` - refresh group blessing status
- `/pp reset` - reset assignments and window position
- `/pp diag` - print client/API diagnostics

## Important beta limitation

WoW Forever's beta API can restrict aura information in combat. This addon does not use combat-log workarounds and does not modify secure spell/unit attributes in combat. The cast buttons keep the last safe out-of-combat target/assignment until combat ends.

## Next planned steps

- Multi-Paladin assignment columns and addon-message synchronization.
- Detect learned blessings/auras/seals and hide unavailable entries.
- Personal blessing overrides (tank gets Kings while the rest of the class gets Salvation, etc.).
- Greater Blessing reagent count/status.
- Optional compact BuffBar view.
- Saved assignment presets.
- More robust localization using client spell data.
