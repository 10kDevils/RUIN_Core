# RUIN Core

The hub addon for the RUIN suite on WoW Forever. It links the guild chats of every RUIN guild, links their officer chats, shows who is online with RUIN across the org, and gives future RUIN addons (Finder, Warfront, Codex, Exchange…) one shared way to talk to each other.

## Install

Copy the `RUIN_Core` folder into your WoW Forever `Interface/AddOns` folder (during the beta that is `_classic_beta_/Interface/AddOns`). Enable "RUIN Core" at character select. Open it with `/ruin`, the addon compartment button, or bind a key under Key Bindings → AddOns → RUIN (handy on a Steam Deck).

## Setting up the org (once)

All RUIN guilds must be on the same ruleset and faction.

1. **Org admin** (the main guild master): open `/ruin` → **Create org key**. You become the admin and your guild is added.
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
