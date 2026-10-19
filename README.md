# RUIN Core: the RUIN Gaming Companion App

The hub addon of the **RUIN Gaming Companion App** on WoW Forever (and Retail). It draws the RUIN window that every module lives in, holds the Guild page with RUIN's community links, links the guild chats of every RUIN guild, links their officer chats, shows who is online with RUIN across the org, and gives the RUIN addons (Codex, Pathfinder, Finder, Muster, Exchange) one shared way to talk to each other.

## The RUIN window

Dark navy with the gold RUIN mark, as in the RUIN Companion brief. Tabs run across the top, named after each module and shown only when it is installed: **Codex** (Gear Path, journal, best-in-slot), **Pathfinder** (leveling and quest guide), **Guild**, **Finder**, **Muster**, **Exchange**, **Settings**. The title bar shows whether you're connected to RUIN and which game you're in.

- **Guild:** who's online in your guild (level, class, online / away / busy, and whether they run RUIN), RUIN members of the other guilds with their tag, the guild message of the day, RUIN's community links with Copy buttons, and Overlord Forever, which runs RUIN's world PvP (the page opens it with `/ov show` when it's installed; RUIN's old Warfront addon is retired).
- **Settings:** the org key tools, chat and display options (couch mode for Steam Deck and TV), and what RUIN shares: only with RUIN members of your org, never outside the game.
- **Community links:** the org admin sets them once (Settings → Community links, or `/ruin key links`) as `Name = address` lines, and they reach every member inside the org key. Keep donation links such as Patreon on the website: Blizzard's add-on rules forbid them in game.

## Install

Copy the `RUIN_Core` folder into your WoW Forever `Interface/AddOns` folder (during the beta that is `_classic_beta_/Interface/AddOns`), or Retail's `_retail_/Interface/AddOns`. Each game keeps its own RUIN settings. Enable "RUIN Core" at character select. Open it with `/ruin`, the addon compartment button, or bind a key under Key Bindings → AddOns → RUIN (handy on a Steam Deck).

## Setting up the org (once)

All RUIN guilds must be on the same ruleset and faction.

1. **Org admin** (the main guild master): open `/ruin` → Settings → **Create org key**. You become the admin and your guild is added.
2. Click **Add guild** for each other guild: `Guild Name, officer rank, tag`. Rank 0 is the guild master, 1 the next rank down. Everyone at or above the officer rank counts as an officer.
3. Target each other guild's leader (or an officer) and click **Send key to target**. They get an "accept org key" prompt. No copy-paste needed. **Export key** gives a text string instead, for leaders who are offline.
4. That's it. Inside each guild, officers share the member key with everyone automatically when they log in, and pass the officer channel to other officers.

Admin changes (adding or removing a guild, rotating) are announced to every guild's online officers automatically. Officers who were offline catch up from other guilds' officers when they log in, unless the key was rotated; after a rotation, send the key again to any guild leader who was offline.

## Day to day

- Type in `/g` as usual. Other RUIN guilds see `[RUIN·YourTag] Name: message`, and you see theirs.
- Officers type in `/o` as usual; other guilds' officers see `[RUIN Officer·Tag]`. Lines from officers not yet confirmed by their guild show "(unverified)".
- Guildmates without the addon are relayed by an automatically chosen "bridge" (an online member with RUIN). They will not *see* other guilds' chat until they install RUIN.

## Commands

| Command | What it does |
| --- | --- |
| `/ruin` | Open or close the window |
| `/ruin guild` / `/ruin settings` | Open the Guild or Settings page |
| `/ruin key links` | Admin: edit the community links |
| `/ruin status` | Print connection status |
| `/ruin versions` | RUIN versions seen online |
| `/ruin key import` / `export` / `send [name]` / `forget` | Key handling |
| `/ruin key create <org>` | Create an org key (you become admin) |
| `/ruin key addguild <guild>, <rank>[, <tag>]` | Admin: add a guild |
| `/ruin key removeguild <guild>` | Admin: remove a guild (also rotates passwords) |
| `/ruin key rotate` | Admin: new channel passwords |
| `/ruin bridge on\|off` | Allow or stop relaying for guildmates without RUIN |
| `/ruin chatframe <n>` | Which chat window shows RUIN lines |
| `/ruin couch` | Couch mode (larger window) |
| `/ruin debug` | Debug messages |
| `/ruin overlord` | Check whether RUIN can see Overlord Forever |

## Beta test checklist

Two characters in two different guilds (or a friend) are enough:

1. Create the key on character A, add B's guild, send the key to B. Does B get the prompt?
2. `/ruin status` on both: do both channels say "connected"? Do you see any "Joined channel" spam? (It should be hidden.)
3. Say something in `/g` on A. Does B see `[RUIN·Tag]`?
4. With a guildmate of A who does **not** have RUIN: does their `/g` line reach B?
5. Officer chat the same way, if both characters are officers.
6. `/reload` and log out/in: is the key still there? (Tests the beta SavedVariables bug.)
7. Turn on `/ruin debug` and report any "send failed" lines with the number shown.

## Known limits

- Addons cannot do real encryption. Anyone with the channel password and a modified client can read or fake RUIN traffic. Rotating the key locks out people who left; keep truly sensitive officer talk in Discord.
- Hidden channels use one of your 10 chat channel slots each (two for officers).
- If someone outside RUIN learns a channel name and joins it first with a different password, RUIN cannot join it. The org admin fixes this by rotating the key.
- Unverified on the live game: the addon-message results, channel scoping by ruleset/faction, and First Last name formats are from Retail behavior and beta notes. Please report what you see.

## For module authors
RUIN modules use `RUIN_API` (see Modules.lua). API level 3 adds:
- `RUIN_API.Map`: positions, distances, and pins on the world map and minimap (`SetPin`, `RemovePin`, `ClearPins`, `Offset`, `DistanceText`).
- `Module:Publish(event, ...)` and `RUIN_API:Subscribe("Module:EVENT", fn)` so modules react to each other locally.
- `RUIN_API.Util.Encode(kind, table)` / `Decode(kind, text)` for copy-paste strings, plus `RUIN_API:ShowText` and `RUIN_API:Confirm` dialogs.
- Widgets: `SubTabs`, `Card`, `HudFrame` (themed, couch-scaled on-screen frames), `RoleIcon`, `ClassIcon`, `Duration`; list rows show item tooltips (`row.link`) and empty-state text.

API level 4 (Core 0.3.6) adds:
- The RUIN look for module pages: `W.PALETTE` (navy, steel, teal, gold), `W.Skin(frame, bg, alpha, border)`, `W.Pill(parent, width)` with `:SetTag("Quick" | "Medium" | "Long" | "Verified" | "Unverified" | "Sample" | "Solo" | "Group", label)`, `W.TagText(tag)`, `W.Progress(parent, w, h)` with `:SetValue(0..1)`, and `W.MARKERS`, one map-marker color per kind (quest, turn-in, dungeon, class, trainer, flight, waypoint, event, enemy, objective).
- `Module:AddTab(title, builder, { order = n, label = "Tab" })`; by default a module's tab label and place come from its theme.
- `RUIN_API:GetClient()` returns `"forever"` or `"retail"`, and `RUIN_API:GetLinks()` the org's community links.
- `RUIN_API:HasOverlord()` and `RUIN_API:OpenOverlord()`: RUIN's world PvP runs on Overlord Forever, so modules can point to it. `RUIN_API.appName` is "RUIN Gaming Companion App".
