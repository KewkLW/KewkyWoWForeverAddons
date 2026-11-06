# KewkyConsole

Run Lua in WoW Forever and see the result, without one-line `/run` guesswork.

- `/kc` opens the console (or bind a key: Key Bindings > AddOns > KewkyConsole). Paste or type code, then
  **Run** or **Ctrl+Enter**.
- `/kc <lua>` runs it straight away. An expression shows its value: `/kc UnitLevel("player")` prints `= 7`.
- Output: `print()` lines, return values (tables expanded two levels), errors in red. The last 200 lines are
  kept in saved variables, and the console shows the tail again after a `/reload`.
- Long code from outside the game (macros, tools): `/kc+ <piece>` adds to a buffer, `/kc!` runs it,
  `/kc clear` empties it.

It has the same power as `/run`: the game still blocks protected actions (targeting, casting, moving,
using items) and keeps combat data hidden from addons.

## Install

1. Download **[KewkyConsole.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyConsole.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the game.
