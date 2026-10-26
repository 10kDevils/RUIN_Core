# RUIN Core: the RUIN Gaming Companion App

The hub addon of the **RUIN Gaming Companion App** on WoW Forever (and Retail). It draws the RUIN window that every module lives in, holds the Guild page with RUIN's community links, links the guild chats of every RUIN guild, links their officer chats, shows who is online with RUIN across the org, and gives the RUIN addons (Codex, Pathfinder, Finder, Muster, Exchange) one shared way to talk to each other.

## The RUIN window

Dark navy with the gold RUIN mark, as in the RUIN Companion brief. Tabs run across the top in this order, shown only when the module is installed: **Guild**, **Finder**, **Muster**, **Pathfinder**, **Codex**, **Exchange** and **Settings**. The title bar shows whether you're connected to RUIN and which game you're in. Guild and Settings keep RUIN's navy, teal and gold; each module's page and tab wear that addon's own color.

- **Guild → Overview:** everyone connected through RUIN right now, across every guild of the org (level, zone and guild tag; away or busy shows by the name), the guild message of the day (with *Edit* for ranks allowed to change it), RUIN's community links with Copy buttons, and Overlord Forever, which runs RUIN's world PvP (the page opens it with `/ov show` when it's installed; RUIN's old Warfront addon is retired).
- **Guild → Roster:** every member of every guild in the org, online and offline: name, level, zone, guild, rank, public note, officer note (your own guild's, for ranks allowed to see it) and last online, with search, *Show offline*, a guild filter and sorting by any column. Your own guild comes live from the game; each other guild's roster is shared by one of its members running RUIN (when it changes, at most every five minutes) and kept, so it shows even when nobody from that guild is online. Officer notes never leave their guild. Click a member to whisper them or invite them to your group; for your own guild, and as far as your guild rank allows in the game, promote, demote or remove them (removing asks first) and edit their notes. *My note* edits your own note (if the game refuses, your rank can't edit notes; RUIN says so). *Invite to guild* invites a new member. `/ruin roster` opens it.
- **Guild → Chat:** your guild's chat, or every RUIN guild's (*All RUIN guilds* / *My guild*), with a line to type to your guild. *Pop out* (or `/ruin chat`) opens it in its own small window you can move anywhere; Escape closes it. The log covers this session.
- **Settings → Org:** the org key. Everyone can *Import key*: paste the key, or type the org's **key phrase**. Only the org admin can *Export key*, since a pasted key is how a new guild joins. The admin's *Choose new key* sets a new key phrase (or a new random key); officers and the admin see the phrase on this page. *Guild settings* (with RUIN Muster installed) sets which ranks of your guild can create events; officers and up change it, and it reaches the whole guild. The org admin also sees *Guilds in the org*: pick a guild to change its name (it must match the in-game guild name exactly), its tag, and which ranks count as officers (your own guild's rank names are shown), or press *Remove guild*. The org admin is every character on the admin's WoW account, so the org can be run from an alt.
- **Settings → Options:** chat and display options (couch mode for Steam Deck and TV), the tab order, and at the bottom *About RUIN*: versions, modules and what RUIN shares: only with RUIN members of your org, never outside the game.
- **Settings → Feedback:** write a bug report, idea or question and press *Copy GitHub link*. Addons can't reach the internet, so RUIN gives you a link that opens a new issue on the Companion App's GitHub with your text, its type and your RUIN version filled in: copy it into your browser and press Submit (a free GitHub account is needed). Nothing is sent inside the game. Issues are public.
- **Community links:** the org admin sets them once (Settings → Org → Community links, or `/ruin key links`) as `Name = address` lines, and they reach every member inside the org key. Keep donation links such as Patreon on the website: Blizzard's add-on rules forbid them in game.

## Install

Copy the `RUIN_Core` folder into your WoW Forever `Interface/AddOns` folder (during the beta that is `_classic_beta_/Interface/AddOns`), or Retail's `_retail_/Interface/AddOns`. Each game keeps its own RUIN settings. Enable "RUIN Core" at character select. Open it with `/ruin`, the addon compartment button, or bind a key under Key Bindings → AddOns → RUIN (handy on a Steam Deck).

## Setting up the org (once)

All RUIN guilds must be on the same ruleset and faction.

1. **Org admin** (the main guild master): open `/ruin` → Settings → **Create org key**. You become the admin and your guild is added. Give it a **key phrase** if you like (or set one later with *Choose new key*).
2. Click **Add guild** for each other guild: `Guild Name, officer rank, tag`. Rank 0 is the guild master, 1 the next rank down. Everyone at or above the officer rank counts as an officer.
3. Target each other guild's leader (or an officer) and click **Send key to target**. They get an "accept org key" prompt. No copy-paste needed. **Export key** (org admin only) gives a text string instead, for leaders who are offline.
4. That's it. Inside each guild, officers share the member key with everyone automatically when they log in, and pass the officer channel to other officers.

**Key phrase.** Instead of the long key, members can type the org's key phrase (for example *dragons eat at dawn*) under Settings → Org → Import key, or `/ruin key join <phrase>`. The phrase decides the org channel's name and password, so RUIN joins that channel and a RUIN member already on it hands over the member key within seconds (someone from the org must be online). Capitals and extra spaces don't matter. The officer channel never comes from the phrase. A phrase is easier to pass around and easier to guess than the random key: anyone who knows it can join the org channel, so change it with *Choose new key* when people leave. Their guild still has to be in the org for them to stay connected.

Admin changes (adding or removing a guild, choosing a new key) are announced to every guild's online officers automatically. Officers who were offline catch up from other guilds' officers when they log in, unless the key was changed; after *Choose new key*, give the new phrase (or send the key again) to anyone who was offline.

## Day to day

- Type in `/g` as usual. Other RUIN guilds see `[RUIN·YourTag] Name: message`, and you see theirs.
- Officers type in `/o` as usual; other guilds' officers see `[RUIN Officer·Tag]`. Lines from officers not yet confirmed by their guild show "(unverified)".
- Guildmates without the addon are relayed by an automatically chosen "bridge" (an online member with RUIN). They will not *see* other guilds' chat until they install RUIN.

## Commands

| Command | What it does |
| --- | --- |
| `/ruin` | Open or close the window |
| `/ruin guild` / `/ruin settings` | Open the Guild or Settings page (`/ruin options` works too) |
| `/ruin tabs reset` | Put the tabs back in their usual order (change the order under Settings → Options → Tab order) |
| `/ruin key links` | Admin: edit the community links |
| `/ruin status` | Print connection status |
| `/ruin versions` | RUIN versions seen online |
| `/ruin key import` / `join <key phrase>` / `send [name]` / `forget`, and `export` (org admin) | Key handling |
| `/ruin key editguild <guild>, <new name>, <officer rank>[, <tag>]` | Org admin: change a guild's entry |
| `/ruin roster` / `/ruin chat` | The guild roster, or guild chat in its own window |
| `/ruin key create <org>` | Create an org key (you become admin) |
| `/ruin key addguild <guild>, <rank>[, <tag>]` | Admin: add a guild |
| `/ruin key removeguild <guild>` | Admin: remove a guild (new officer channel; with a random key, a new org channel too) |
| `/ruin key newkey [key phrase]` | Admin: a new key phrase, or without one the Choose new key box (empty for a random key) |
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

- Addons cannot do real encryption. Anyone with the channel password and a modified client can read or fake RUIN traffic. Choosing a new key locks out people who left; keep truly sensitive officer talk in Discord.
- Hidden channels use one of your 10 chat channel slots each (two for officers).
- If someone outside RUIN learns a channel name and joins it first with a different password, RUIN cannot join it. The org admin fixes this with *Choose new key*.
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

API level 8 (Core 0.3.15) adds:
- `W.Dropdown(parent, width, options, getter, setter, prefix)`: a button showing the current choice that opens the list of choices underneath; `d.format(value)` sets the shown text, `d:Refresh()` re-reads the value.
- `W.WhenPicker(parent)`: a day list (today and the next two weeks, as *Wed 10/21*), hour and minute boxes and AM / PM, in the player's own time; `:GetTime()` returns epoch seconds (or nil and why), `:GetText()` gives "2026-10-21 20:00", `:SetTime(t)`.
- `W.WhenText(t)`: "Wed 10/21 8:00 PM".

API level 10 (Core 0.3.17; 0.3.18 adds `Widgets.FitScrollBar(scrollFrame)`, which shows a scroll bar only when there is something to scroll) adds `RUIN_API:CanCreateEvents()` and `GetEventRank()` (which ranks of your guild may create events, set by its officers), and the `GUILD_SETTINGS_CHANGED` and `ORG_ROSTER_UPDATED` callbacks.

API level 9 (Core 0.3.16) adds `RUIN_API.Items`: `Items.Text(id, fallbackName, fallbackQuality)` gives an item's link, else its remembered name in quality color, else the fallback, else "Loading item..." (never a bare ID); `Items.Info(id)` gives name, link, quality; `Items.RememberLinks(text)`, `Items.QualityHex(q)`, `Items.QualityName(q)`. Pages redraw on the `ITEMS_LOADED` callback (`RUIN_API:Subscribe("ITEMS_LOADED", fn)`).

## Chat channel numbers
RUIN's two hidden channels (org and officers) always sit after your other channels: General, Trade and the rest keep the low numbers, RUIN's come last and are never /1. Right after login RUIN waits (up to 45 seconds) for the game's own channels to join first, then moves its channels to the end of the list one swap at a time, keeping your other channels in their order. Nothing is moved during combat. If you have left every other channel, RUIN's has to be /1 until you join one.
