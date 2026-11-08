# Sage QoL: Mana Ticks

A World of Warcraft: Forever addon that shows mana regeneration on your mana bar. A spark sweeps the bar over the five seconds after you spend mana, while spirit regeneration is blocked. Once the five-second rule ends, the spark crosses the bar every two seconds, timed to your observed regen ticks, so it reaches the right edge as the next tick lands. The spark hides when mana is full, when you have no mana, and when you are dead.

Druids in a form that does not use mana get an extra mana bar below the player frame, with the same spark. Forever's built-in alternate bar does not cover cat and bear form.

It is part of Sage QoL, a personal set of small quality-of-life addons.

## Install

Copy this repository into `World of Warcraft/_forever_/Interface/AddOns/SageQoL_ManaTicks`. The folder name must be `SageQoL_ManaTicks`.

## Development

```sh
npm install
npm run check
```

`npm run check` confirms the TOC and the Lua files agree and that the Lua parses.

## Checking regen timing

Type `/manaticks log` in game, spend some mana, and stand still. For 30 seconds it prints each mana spend and regen tick, with the time since the previous one. It works in forms too, where Forever hides the mana amount. Regen ticks should land about 2 seconds apart.
