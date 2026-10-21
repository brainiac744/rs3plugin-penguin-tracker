# Penguin Tracker

A RuneScape plugin for the weekly **Penguin Hide and Seek** Distraction & Diversion.

It shows where this week's penguins and the polar bear have been reported, and marks the
ones **you have already spied — automatically**, by reading your progress from the game.
No more clicking rows to remember who you've found.

## Features

- **Live locations** of all 12 penguins and the bear, from the community tracker at
  [w60pengu.in](https://w60pengu.in), refreshed every 30 seconds.
- **Automatic spy tracking** — spied penguins fade out the moment you spy them, and the header
  shows how many you've found and how many points that's worth this week.
- **Confirm or correct locations** — press **OK** if a penguin is still where it's listed, or
  **Edit** to report where it really is. Your update goes to w60pengu.in for everyone.
- **Optional highlight** *(off by default)* — draws a gold box around disguised penguins near
  you; ones you've just spied turn grey.
- A movable, resizable window that remembers where you left it.

## Using it

1. Open the **Plugins** panel and click the **Penguin Tracker** icon.
2. Press **Show window**.
3. In the window:
   - Rows show the penguin's number, area and disguise, its points, the last reported location
     and how long ago that was reported.
   - Faded rows are penguins you've already spied this week.
   - **Refresh** fetches the latest locations immediately.
   - **Highlight: Off / On** toggles the boxes around nearby penguins.

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
   (Delete or rename any existing `dev_plugins\penguin-tracker` folder first. In Command Prompt
   the equivalent is `mklink /J "...\dev_plugins\penguin-tracker" "<checkout>\plugin"`.)
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
| `plugin/main.lua` | Entry point: events, timers, saving settings |
| `plugin/src/spied.lua` | Reads spy progress from the game variable `PENG_SPY_SWITCH` |
| `plugin/src/locations.lua` | Talks to the w60pengu.in API |
| `plugin/src/ui.lua` | The window and the Plugins-panel summary |
| `plugin/src/highlight.lua` | Optional in-world boxes around penguin NPCs |
| `plugin/src/clock.lua` | Current time, for "5m ago" labels |
| `plugin/src/json.lua` | Small JSON reader/writer (Lua has none built in) |

**Spy progress** comes from one player variable, `PENG_SPY_SWITCH` (VarPlayer 1408):

| Bits | Meaning |
|---|---|
| 0–9 | penguins 1–10 (penguin *n* is bit *n − 1*) |
| 16–20 | number of penguins spied this week |
| 26 | the bear |
| 27 | penguin 11 (the ghost) |
| 28 | penguin 12 |

Penguin NPCs are named after their disguise (`PENG_SPY_PUMPKIN`, `PENG_SPY_BARREL`, …) and don't
carry their penguin number, so the highlight marks a penguin as spied by noting which one was
closest to you when your spy count went up.

More notes on the RuneScape plugin API: [`docs/runescape-plugin-notes.md`](docs/runescape-plugin-notes.md).

## Credits

Location data: [w60pengu.in](https://w60pengu.in) and the players who report there.
UI library: [PrettyUI](https://github.com/PrettyRS/prettyui).

## Licence

[Apache-2.0](LICENSE)
