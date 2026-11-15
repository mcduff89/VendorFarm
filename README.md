# VendorFarm

Ranks the mobs around your level by expected **vendor gold per hour**, for WoW Forever.

    gold/hr = (average coin + sum of drop chance x sell price) x kills per hour

- `/vfarm debug` toggles debug printing; `/vfarm check` shows what this client supports.
- `/vfarm` opens the list for your level. `/vfarm 32` checks another level. `/vfarm options` opens the settings.
- **Zone** toggle limits the list to your current zone. **Right-click** rows to pick farm targets; they stay on top and the status line shows their combined gold/hr.
- **Dungeons tab** (`/vfarm dungeons`): every 5-man ranked by gold per full clear and gold/hr (max 5 runs an hour). Red names are above your level. Hover for run time, runs/hr and the biggest earners. Your runs are logged when you leave and replace the estimates.
- **Compact tracker** (`/vfarm track`, or the minus button): session time, kills, seconds per kill, looted gold/hr and how it compares to the model.
- Seconds per kill is learned from your real kills (gaps over 3 minutes count as breaks), starting from a 25s guess. Settings shows your pace and has a Reset pace button.
- Hover a row to see its drops, drop %, and what each one is worth per kill. Click a row to drop a TomTom arrow on its main camp.
- Window toggles: Elites, Dungeons, Skinning (adds leather/hides), AH price (uses Auctionator's last scan minus the 5% cut when it beats the vendor price).
- Level range: type the lowest level in **From** (Enter), and pick +0 to +5 above your level in the dropdown.
- Settings (Esc > Options > AddOns > VendorFarm): rows, rares, respawn cap.

## Where the numbers come from
- **Other players (1.6.0+):** VendorFarm users share kill/loot totals through hidden addon messages, all inside the game. Turn it off in settings.
- **Your own kills (1.2.0+):** every corpse you loot is recorded per mob. Rates blend from the database toward yours and use only yours after the "Kills until your own drop rates take over" setting (100 by default).
- **Drop rates, coin, levels, spawn counts, respawn times:** CMaNGOS Classic-DB (vanilla 1.12, release z2815, GPL-3.0). These are an emulator database's values, not measured on Forever. Forever-only mobs are missing.
- **Sell prices:** read live from your client (`GetItemInfo`), so Forever's own vendor prices are used. Rows tagged `db` in the tooltip use the Classic price until the item is cached.
- **Zone names and waypoints:** QuestieDB, if loaded. Friendly town/guard NPCs are filtered out with QuestieDB as well.
- **Kills per hour** is a model: 3600 / seconds per kill, capped by spawn count x 3600 / respawn time. Set seconds per kill to your real pace.

Rebuild the data with `tools/build.py` (parse the CMaNGOS SQL dump with `tools/parse.py` first).

## Changelog
- 2.1.0 (2026-11-14): Gathering data is shared like mob data (same channels and settings): what nodes and fishing drop per zone (item counts, so your own prices apply) and other players' nodes per hour as a better starting guess. Each player counts for at most 2000 nodes or catches per zone; impossible numbers are dropped. Your own pace still takes over after 20 nodes in a zone.
- 2.0.0 (2026-11-14): Gathering tab. Checkboxes for Herbalism, Mining, Skinning and Fishing (ticked for the professions you have, with your skill shown). Herb and ore nodes are ranked per zone by gold/hr: value per node from CMaNGOS node loot x your prices, nodes up from spawn spots weighted by their spawn pools (only nodes your skill can gather), nodes per hour estimated until you gather 20 nodes in a zone, then your own pace. Fishing ranks zones by open-water loot x catches per hour (learned). Skinning shows the best skinnable mob per zone. The Zone box limits it to your current zone. `/vfarm gathering`.
- 1.9.1 (2026-11-14): Tracker lines have hover tooltips: farming time and pace, a Looted breakdown (coin, items at vendor vs. AH price, totals both ways), and what Model and Luck mean.
- 1.9.0 (2026-11-14): Spawn dots. Your farm targets and the waypoint mob show every spawn point on the world map and minimap; hovering a row with the world map open lights up that mob's spawns. Uses HereBeDragons-Pins from TomTom or Questie. Toggle in options.
- 1.8.0 (2026-11-14): Session history. Each farm session (10+ kills, 5+ minutes) is saved when you end it on the tracker or after 15 minutes without a kill. A History tab ranks the spots you actually farmed by the gold/hr you really made, next to what the model predicted; hover for each session. `/vfarm history`, `/vfarm clearhistory`. Bag button on the window and tracker: left-click drops a TomTom waypoint on the nearest friendly vendor, right-click the nearest repair vendor (`/vfarm vendor`, `/vfarm repair`); 879 vendors from CMaNGOS, spots and faction from QuestieDB.
- 1.7.0 (2026-11-14): `/vfarm debug` prints what VendorFarm reads (loot slots, coin, kills, combat log, sync, waypoint coordinates) and `/vfarm check` lists what this client supports. Kill pace is now learned per mob (blends in over 10 kills; overall pace is the fallback). Minimap button (left: list, right: tracker, shift: options, drag to move; `/vfarm minimap` hides it) plus a LibDataBroker launcher when a broker display is installed.
- 1.6.0 (2026-11-14): shared drop data. VendorFarm users swap their kill/coin/loot totals in game (guild, party/raid and a hidden VendorFarmSync channel) and everyone's kills blend into the rates. Totals per player replace older ones, so nothing is double counted; each player counts for at most 500 kills per mob; impossible numbers are dropped. Paused in combat and instances. `/vfarm sync` shows the community totals. Blue dot = community data only.
- 1.5.0 (2026-11-14): Dungeons tab (`/vfarm dungeons`): ranks every 5-man by gold per full clear and gold/hr, capped at 5 runs an hour. Bosses are included. Run time starts as an estimate from your kill pace and switches to your real average once you finish a run (logged when you leave, 3 min minimum); gold per run blends to your own runs over 5 runs.
- 1.4.1 (2026-11-14): AH prices are read from Auctionator by item link first (matches its tooltip for gear), greys are included, BoP items skip AH, and the tooltip shows each item's price per item with its source and scan age, then its value per kill.
- 1.4.0 (2026-11-14): your own drop rates now take 100 kills to fully take over (was 30; old saved 30 is moved to 100). The elite multiplier slider is gone: it starts at 3x and is learned from your elite vs normal kill pace. Reset pace resets both.
- 1.3.3 (2026-11-14): removed the level range sliders from settings (the From box and +N dropdown in the window are the only controls) and the seconds-per-kill slider: kill pace is always learned from your kills, shown read-only in settings with a Reset pace button.
- 1.3.2 (2026-11-14): left-clicking the same mob again removes its waypoint; clicking another mob replaces it.
- 1.3.1 (2026-11-14): fixed "couldn't map zone" on waypoint clicks (QuestieDB stores its zone table as text that needs loading).
- 1.3.0 (2026-11-14): Zone toggle (current zone only), right-click rows to pick farm targets (pinned on top, combined gold/hr), compact tracker (`/vfarm track` or the minus button) with session gold/hr vs expected, and seconds per kill now learns from your real kills.
- 1.2.1 (2026-11-14): the From box no longer clears itself while you type.
- 1.2.0 (2026-11-14): learns drop rates from your own kills (coin, loot, skinning). Your rates blend in and fully replace the database after 100 kills (setting; 30 before 1.4.0). Mobs the database lacks (new Forever mobs) show up once you have killed them. Green dot = your data. `/vfarm resetdata` clears it.
- 1.1.0 (2026-11-14): level range is now "From <level> to your level" plus a +0 to +5 dropdown, in the window and in settings.
- 1.0.0 (2026-11-14): first version.
