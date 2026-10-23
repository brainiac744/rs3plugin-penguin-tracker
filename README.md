# Penguin Tracker

A RuneScape plugin for the weekly **Penguin Hide and Seek** Distraction & Diversion.

It shows where this week's penguins and the polar bear have been reported, and marks the
ones you have already spied by reading your progress from the game.

## Features

- Locations of all 12 penguins and the bear from the community tracker at
  [w60pengu.in](https://w60pengu.in), refreshed every 30 seconds while the window is open.
- A penguin's name turns green when you spy it, and the header shows how many you've found
  and how many points that's worth this week.
- Press **OK** if a penguin is still where it's listed, or **Edit** to report where it really
  is. Your update goes to w60pengu.in for everyone.
- An optional highlight (off by default) draws a box around disguised penguins near you: gold
  if you haven't spied them yet, grey if you have. You can change the colours.
- Penguin points are capped at 250 and any extra are lost. Once your banked points pass a
  threshold (245 by default), unspied penguins are outlined in a warning colour (red by
  default). You can also have Spy-on stop being the left-click option near the cap, so you
  can't spy by accident (right-click still works).
- The window can be moved and resized, and remembers where you left it.

## Using it

1. Open the **Plugins** panel and click the **Penguin Tracker** icon.
2. Press **Show locations**.
3. In the window:
   - Rows show the penguin's number, area and disguise, its points, the last reported location
     and how long ago that was reported.
   - Green names (marked "spied") are penguins you've already spied this week. You can still
     confirm or edit their locations - having just seen them, you're the best person to.
   - **Refresh** fetches the latest locations immediately.
   - The header also shows your banked points out of 250.
4. Settings are on the plugin's settings page (**Plugin Hub › Manage**, then Penguin Tracker's
   settings icon): turn the highlight on, pick its colours, and set up the points-cap warning.

Points never change: penguins 1–5 are worth 1, 6–10 and 12 are worth 2, penguin 11 (the ghost)
is worth 3, and the bear is worth 1.

## Permissions

The plugin asks for **HTTP access** so it can read and update locations on
`https://api.w60pengu.in`. It contacts no other site. Without the permission, spy tracking
still works but locations aren't shown.

## Installing for development

The plugin itself is the [`plugin/`](plugin/) folder.

1. Make the game load it from this checkout by linking it into `dev_plugins`. In PowerShell
   (no admin needed), from the root of this checkout:
   ```powershell
   New-Item -ItemType Junction -Path "C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\penguin-tracker" -Target "$PWD\plugin"
   ```
   (In Command Prompt the equivalent is `mklink /J "...\dev_plugins\penguin-tracker" "<checkout>\plugin"`.)
2. In game, open the console with **Alt + `** and run:
   ```
   prf
   pon penguin-tracker
   ppr penguin-tracker
   ppe penguin-tracker httpAccess
   prl penguin-tracker
   ```
3. After editing any Lua file, run `prl penguin-tracker`. After changing `plugin.json`, run
   `prf` first.

Requires the **PrettyUI** plugin (installed automatically as a dependency from the Plugin Hub).

## How it works

| File | Purpose |
|---|---|
| `plugin/main.lua` | Entry point: wires events and timers to the pieces below |
| `plugin/src/spied.lua` | Reads spy progress and banked points from game variables |
| `plugin/src/locations.lua` | Talks to the w60pengu.in API |
| `plugin/src/highlight.lua` | Optional in-world boxes around penguin NPCs |
| `plugin/src/menu.lua` | Near the points cap, keeps Spy-on off the left click (optional) |
| `plugin/src/settings.lua` | Saved player settings and their defaults |
| `plugin/src/items.lua` | The 13 items: numbering, fixed points, default names |
| `plugin/src/clock.lua` | Current time, for "5m ago" labels |
| `plugin/src/json.lua` | Small JSON reader/writer (Lua has none built in) |
| `plugin/src/log.lua` | Console messages (set `Log.DEBUG = true` for progress messages) |
| `plugin/src/ui/window.lua` | The locations window, including editing and remembering its position |
| `plugin/src/ui/sidebar.lua` | The Plugins panel: summary and Show/Hide locations |
| `plugin/src/ui/settings_page.lua` | The settings page |
| `plugin/src/ui/common.lua` | Shared colours, fonts and UI helpers |

**Spy progress** comes from one player variable, `PENG_SPY_SWITCH` (VarPlayer 1408):

| Bits | Meaning |
|---|---|
| 0–9 | penguins 1–10 (penguin *n* is bit *n − 1*) |
| 16–20 | number of penguins spied this week |
| 26 | the bear |
| 27 | penguin 11 (the ghost) |
| 28 | penguin 12 |

**Banked points** are bits 16–23 of `PENG_SPY_PERM1` (VarPlayer 9543).

Penguin NPCs are named after their disguise (`PENG_SPY_PUMPKIN`, `PENG_SPY_BARREL`, etc.) and don't
carry their penguin number, but each one keeps the same NPC UID. The highlight uses a table of
UIDs to penguin numbers (in `src/highlight.lua`) and takes each penguin's spied state from the
flags above. If a penguin's UID isn't in the table, it's learned the first time you spy it: the
most recent penguin you clicked is taken to be the one you spied, and the mapping is saved.

## Credits

Location data: [w60pengu.in](https://w60pengu.in) and the players who report there.
UI library: [PrettyUI](https://github.com/PrettyRS/prettyui).

## Licence

[Apache-2.0](LICENSE)
