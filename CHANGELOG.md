# RUIN Core changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

1. Guild → Roster: the *My note* button under a selected member (yourself) is wide enough for its name.

## 0.4.3 — 2026-10-27

The Guild page grows from three sub-tabs to seven: Overview, Census, Roster, People, Chat, Watch and Bank.

1. **Census.** Every guild of the org on one page: members, online, average level, guild master (online or last seen), RUIN users and free slots, sortable, with the org's totals, today's peak, a 30-day graph of characters and a 24-hour graph of who's online (kept on your computer), and where members are by continent and zone.
2. **Census search.** One box finds a guild or its tag, a guild master, a player or a zone; look-alike letters match (l, I, 1 and 0, O). `recruiting` or `free 50` lists guilds with room.
3. **People.** The hierarchy (guild masters, officers and office holders of every guild), inactive members (7, 14 or 30 days and more), and members by class, zone, level or profession (professions from RUIN Exchange). Officers are told once when their guild master has been away 3 days or more.
4. **Appointed offices.** Guild masters (and the org admin) appoint Treasurer, Recruiter, Raid leader, Quartermaster and other offices; every RUIN member sees them, and modules can ask who holds one.
5. **The Watch.** Report a player to the officers (Guild > Watch, `/ruin report`, or right-click a player); the report goes to an officer online, or waits until one is, and becomes a case every officer of the org sees. Officers note, warn (a mute that climbs 5 minutes, 30 minutes, 24 hours within a day), mute, hide from the RUIN network, resolve or dismiss, and delete chat lines for everyone, under a cover name if they like. Every client keeps a log of what it saw done.
6. **Sanctions follow the BattleTag.** Each RUIN shares a salted hash of its BattleTag (it can't be read back or matched across orgs), so a mute or hide covers every character of that player. Only the org admin can sanction an officer.
7. **Chat tools.** Search the chat, pin lines (Pins), click a line to pin, whisper, report, copy, or (officers) delete it for everyone or mute its author. Block words hide lines with words you choose; the org admin can set block words for the whole org (Settings → Org).
8. **Join screen.** Players who aren't in an org guild get a Join card on the Overview: type the key phrase to see the guilds, find a guild's members online with /who, and ask one of them to join. The request reaches that guild's members who can invite: on their Overview, with Invite and Decline.
9. **Update tools.** A *What's new* letter once after each update (Settings → Options → What's new, `/ruin news`). Right-clicking a player adds a RUIN part to the game's menu: their RUIN version (or Check RUIN version), Ask to update (officers, when they're behind) and Report to the RUIN Watch.
10. **Guild bank snapshots.** When a guildmate with RUIN opens the guild bank, RUIN shares what its tabs hold (the tabs their rank can see) and its gold; Guild > Bank shows it with search, per tab, and how old it is.
11. Settings → Options → *Count my characters as one player*: the census counts your characters once (RUIN shares a random token only your characters send). Off by default.
12. API level 11 for modules: `GetOrgMembers`, `GetCensus`, `GetWhere`, `GetOffices`, `HasOffice`, `IsSanctioned`, `AddProfessionSource`, `OpenGuildTab`, `PromptReport`, `GetVersionOf`, `GetGuildBank`, `Module:SendRaw`, and the events `CENSUS_SAMPLED`, `OFFICES_CHANGED`, `WATCH_CHANGED` and `BANK_CHANGED`. Buttons take a `tip`; `Widgets.ContextMenu` opens a small menu at the cursor.
13. New commands: `/ruin census | people | watch | bank`, `/ruin report [name]`, `/ruin news`.

## 0.4.2 — 2026-10-26

1 change since 0.4.1:

1. Settings → Feedback says feedback goes to the Companion App's GitHub.

## 0.4.1 — 2026-10-25

1 change since 0.4.0:

1. RUIN's text boxes (Choose new key, Import key, Export key and the others) grow to fit their explanation, so the text box always sits below it instead of covering it.

## 0.4.0 — 2026-10-23 · Beta 1

The RUIN Gaming Companion App enters beta: every addon is now 0.4.0. Nothing changed since 0.3.19 apart from the version number. Report what you find under Settings → Feedback.

## 0.3.19 — 2026-10-23

1 change since 0.3.18:

1. **Feedback goes through GitHub only.** Settings → Feedback no longer sends feedback to the org admin inside the game (the admin's inbox is gone): *Copy GitHub link* gives a link that opens a new GitHub issue with the text, its type and the RUIN version filled in.

## 0.3.18 — 2026-10-23

3 changes since 0.3.17:

1. **Options is now Settings**, with sub-tabs *Org*, *Options* (chat and display options and the tab order, with *About RUIN* at the bottom) and *Feedback*. `/ruin options` and modules opening "Options" still work.
2. **Feedback.** Settings → Feedback has a box to write a bug, idea or question. *Send to RUIN* sends it inside the game to the org admin (any of the admin's characters), and RUIN keeps it and tries again until the admin's RUIN confirms it; *Copy GitHub link* opens a new GitHub issue with the text filled in. The org admin gets a *Feedback inbox* (copy new feedback as Markdown, mark it posted, clear it); `tools/feedback_to_github.py` in the suite repo posts it as GitHub issues.
3. Lists show their scroll bar only when there is something to scroll (`Widgets.FitScrollBar` for modules).

## 0.3.17 — 2026-10-23

5 changes since 0.3.16:

1. **Roster shows every guild in the org.** One RUIN member online in each guild shares its roster (name, level, class, zone, rank and rank name, public note, online state, last online; never officer notes) on the org channel when it changes, at most every five minutes, and on request. Everyone keeps the last copy, so other guilds show even when nobody from them is online. New *Guild* column and guild filter; moderation stays for your own guild. RUIN turns on the game's "show offline members" so offline guildmates are listed.
2. **Overview lists only players connected through RUIN**, across every guild, with level, zone and guild tag.
3. **Edit your own note.** *My note* on the Roster (and *My note* when you pick yourself) edits your note in the guild roster for every rank; the game still decides, and RUIN says so if your rank can't.
4. **Key phrases.** The org can have a key phrase members type under Import key (or `/ruin key join <phrase>`) instead of pasting the long key: the phrase leads to the org channel, and a member online there hands over the member key. *Rotate key* is now *Choose new key*: a new phrase, or a new random key. Create org key asks for an optional phrase. Officers and the admin see the phrase under Options; members' keys don't carry it.
5. **Guild settings: who can create events.** Under Options → Org, officers and up choose the lowest rank of their guild that can create RUIN Muster events; the setting reaches the whole guild (and guildmates who log in later). For modules, API level 10: `RUIN_API:CanCreateEvents()`, `GetEventRank()`.

## 0.3.16 — 2026-10-22

4 changes since 0.3.15:

1. **The Guild page has the game's guild window.** New sub-tabs: *Overview* (as before, plus *Edit* for the message of the day), *Roster* (name, level, zone, rank, public note, officer note and last online as the game shows them, with search, *Show offline* and column sorting; pick a member to whisper or group-invite them and, as your guild rank allows, promote, demote, remove (asks first), edit notes, or *Invite to guild*), and *Chat* (your guild's chat or every RUIN guild's, a line to type to your guild, and *Pop out* into a movable window). `/ruin roster` and `/ruin chat`.
2. **Options for the org admin.** Options now has *Org*, *Display* and *About* sub-tabs. *Org* lists the org's guilds for the admin: rename a guild, change its tag and which ranks count as officers (with your guild's rank names), or remove it. `/ruin key editguild` does the same from chat. The admin is now every character on the admin's WoW account (noted in the account-wide RUIN_DB), so the org can be run from an alt; the admin stays connected to the org channels on every character. *Export key* is for the org admin only.
3. **RUIN's channels are always the last channel numbers, never /1.** RUIN joins after the game's channels and then moves its two channels behind the others, keeping your other channels' order (not in combat).
4. For modules (API level 9): `RUIN_API.Items` shows items by name, never as a bare ID: it asks the game for missing items, remembers names and qualities it has seen, and fires `ITEMS_LOADED` when names arrive.

## 0.3.15 — 2026-10-21

1 change since 0.3.14:

1. For modules (API level 8): `Widgets.Dropdown` (a button that opens a list of choices underneath), `Widgets.WhenPicker` (a day list showing the weekday and a short date such as *Wed 10/21*, with separate hour and minute boxes and AM / PM) and `Widgets.WhenText` (writes a time as *Wed 10/21 8:00 PM*). RUIN Muster's New event form and the Codex Journal's run planning use them. The Codex and Pathfinder page lines now describe what those pages do.

## 0.3.14 — 2026-10-21

1 change since 0.3.13:

1. For modules: `RUIN_API:IsOfficerName(name)` (API level 7) tells whether another player is an officer: guildmates are checked against your guild roster, members of other RUIN guilds by what their RUIN reports. Long messages (such as shared routes) now have 90 seconds to arrive in full instead of 30. RUIN Pathfinder uses both for officer routes.

## 0.3.13 — 2026-10-19

2 changes since 0.3.12:

1. **Arrange the tabs your way.** Options has a new *Tab order* card: pick a tab, then *Move left* or *Move right*. Guild and every module can go anywhere; Options always stays last so you can find it. Your order is saved in RUIN Core (RUIN_DB). *Reset*, or `/ruin tabs reset`, puts them back, and a newly installed module joins at the end until you place it.
2. **Fixed: the Overlord Forever card on the Guild page.** Its text ran out of the card and the button read "Open /ov s...". The button is now *Open Overlord* on the card's title line, the text is shorter and has the full width, and the card is a little taller.

## 0.3.12 — 2026-10-19

3 changes since 0.3.11:

1. **Each page in its addon's color.** Guild and Options keep RUIN's navy, teal and gold. A module's page (and its tab) now takes that addon's color throughout: the selected tab, sub-tabs, edges, button and row highlights, section rules, check marks and a faint tint in the panels. Each tab along the top also shows a thin line in its addon's color.
2. **Tidier controls that match the RUIN look.** Check boxes and text boxes are drawn in RUIN's style instead of Blizzard's (you can click a check box's label too). Text boxes show a grey hint of what goes in them while empty. Buttons that step through choices have a small arrow and say on hover how they work.
3. **Options is simpler.** Members see only the org-key buttons they can use (Import, Export); the org admin's tools sit on their own row, shown only to the admin. Officer chat appears only for officers, every option explains itself on hover, and the guild relay option now says what it does ("Share chat from guildmates without RUIN"). Page subtitles say plainly what each page is for. API level 6.

## 0.3.11 — 2026-10-19

1 change since 0.3.10:

1. **Original module names kept.** The tab order stays Guild, Finder, Muster, Pathfinder, Codex, Exchange, Options (Settings is now called Options; `/ruin options` and `/ruin settings` both work). Tabs, page headers, chat lines and the addon list use the original names again.

## 0.3.10 — 2026-10-19

1 change since 0.3.9:

1. **Tabs reordered and renamed.** Guild, Groups, Events, Leveling, Gear, Market, Options (was Settings; `/ruin options` works as well as `/ruin settings`). Page headers read Group Finder, Events & Rallies, Leveling & Quest Guide, Gear & Dungeons, Market and Options, and RUIN's chat lines use the same names. The tabs now read in the brief's plain language. Only what players see changed: the addon folder, repository, command and saved-data names stay the same, so nothing needs reinstalling or re-setting.

## 0.3.9 — 2026-10-19

2 changes since 0.3.8:

1. New `Module:ListenRaw(fullKind, handler)` and API level 5, so a module can keep understanding messages sent under a retired addon's name. RUIN Muster uses it for old RUIN Intel versions still in the org.
2. RUIN Intel is retired (its sightings and timers moved to RUIN Muster), so it no longer has its own tab. The theme entry stays, labelled retired, for chat lines.

## 0.3.8 — 2026-10-19

1. **Fixed: Overlord Forever showing as "not installed" when it is.** RUIN only looked for Overlord's /ov chat command, and a miss was remembered for 30 seconds. It now finds Overlord in the game's AddOns list (any addon with "Overlord" in its folder name or title) and checks whether it is loaded, so it no longer depends on when or how Overlord registers /ov. The Guild page and Muster now tell "installed but switched off" apart from "not installed". Open uses Overlord's /ov handler when it can find it, and otherwise sends "/ov show" like a typed command. New `/ruin overlord` prints what RUIN can see (AddOns list entry, loaded or not, /ov found or not).

## 0.3.7 — 2026-10-18

7 changes since 0.3.0, bringing the suite in line with the RUIN Companion brief from the head of RUIN:

1. The RUIN look: a new RUIN window in dark navy with steel-blue edges, the gold RUIN mark and "Guide · Gear · Quests · Guild" in the title bar, connection state, and page tabs across the top named after each module: Codex, Pathfinder, Guild, Finder, Muster, Intel, Exchange, Settings. Buttons, sub-tabs, lists, cards, dialogs, on-screen frames and page headers all use it, so every module changes with it. Chat lines start with a teal [RUIN].
2. Guild page (replaces the Org page): who's online in your guild with level, class and status, RUIN members of the other guilds with their tag, the guild message of the day, and RUIN's community links with Copy buttons. RUIN's world PvP now runs on Overlord Forever: the page says whether it is installed and opens it (/ov show).
3. Community links travel inside the org key: the org admin sets Discord, website, Twitch and the like (Settings → Community links, or /ruin key links) and every member gets them. Older RUIN versions carry the field along untouched.
4. Settings page: the org key tools, chat and display options (couch mode included) and an About box that says what RUIN shares (only with RUIN, never outside the game).
5. Retail and WoW Forever from one codebase: the TOC lists both interface numbers (16001 and 120105), and Core reports which game it runs in so data written for one game can stay out of the other. Each game keeps its own saved settings.
6. Module API level 4: pills (Quick / Medium / Long and evidence tags), progress bars, the RUIN palette and one set of map-marker colors for the suite, tab label and order options, RUIN_API:GetClient(), RUIN_API:GetLinks(), and RUIN_API:HasOverlord() / OpenOverlord().
7. The suite is now the **RUIN Gaming Companion App**: RUIN Core shows that name in the AddOns list and the window's title bar, every RUIN addon sits in one "RUIN Gaming Companion App" category on clients that group addons, and pages carry the app name above their title. RUIN Warfront is retired (see Muster 0.3.3).

## 0.3.0 — 2026-10-18

- Suite release: every RUIN addon moves to 0.3.0 together, bringing everything from the 0.2.x entries below. No further code changes.
- From now on a RUIN addon's 0.3.x number counts its own changes since this release.

## 0.2.6 — 2026-10-18

5 changes since 0.2.1 (0.2.1 fixed the window title on the Org page; this release counts from there.):

1. Map pins: modules can put markers on the world map and minimap (RUIN_API.Map), shown on a zone and the continent around it, with distance and direction on hover.
2. Module API level 3: modules react to each other locally (Publish / Subscribe), share copy-paste strings (RUIN_API.Util.Encode / Decode), and use RUIN's text and confirm dialogs.
3. Widget kit: themed sub-tabs for module pages, tinted cards for grouping controls, on-screen frames in each module's colours that follow couch mode, role and class icons, and countdown text.
4. Lists show an item's tooltip when you hover a row, extra row tooltips, and a line of help when a list is empty.
5. Alerts and chat lines show the module's name in that module's colour.

## 0.2.1 — 2026-10-18

- Fixed: the window title read "RUIN - RUIN Core" on the Org page. It now reads "RUIN Core"; module pages still read "RUIN - Finder" and so on.

## 0.2.0 — 2026-10-18

- Suite milestone: every RUIN addon moves to 0.2.0 together. This release is the new Blizzard-style RUIN window from 0.1.3; no further code changes.
- From now on a RUIN addon's 0.2.x number counts its own changes since this release.

## 0.1.3 — 2026-10-18

- New RUIN window built on Blizzard's own portrait window, the same frame the Character and Collections windows use: stone border, portrait in the corner, close button, and tabs along the bottom edge. It falls back to the old plain frame if a client lacks the template.
- Window title and portrait follow the open page (for example "RUIN  -  Warfront" with the PvP banner).
- Blizzard's open, close and tab-switch sounds.
- Each page gets a themed header in its own colour, with title, tagline, gold rule and a small animated scene:
  - Org: hanging Alliance banners.
  - Finder: notes pinned to a board.
  - Warfront: crossed swords over drifting embers.
  - Pathfinder: a walker on a dotted trail.
  - Codex: a tome with pulsing runes.
  - Exchange: ledger lines and coins.
  - Muster: flickering torches and pennants.
  - Intel: a sweeping radar.
- Section headings and list rows in every module pick up that page's colour (underlined headings, tinted zebra rows and hover).
- New setting "Animated page headers" on the Org page (on by default). Turn it off for a still header.
- Window is 724 px wide so all eight pages' tabs fit in one row; extra tabs wrap onto a second row.
- Couch mode scale raised to 1.15.
- Modules can pass their own `theme` in `RegisterModule`'s info table.

## 0.1.2 — 2026-10-18

- RUIN window now lists pages down a sidebar, so any number of modules fit and the list is easy to step through with a controller. Window is wider (724 px).
- New shared widget kit for modules (`RUIN_API.Widgets`: Button, Check, EditBox, Cycle, List, Label, Money, Ago, ClassName) and toast alerts (`RUIN_API:Toast`, `Module:Toast`).
- Module API level 2: `RUIN_API.apiLevel`, `RUIN_API:OpenTab`, `RUIN_API:GetModule`, `RUIN_API:GetPlayer`, `Module:OpenTab`, `Module:RegisterEvent`.
- Org page lists installed modules and their versions.
- Fixed: a key offer, or an officer-attestation reply, could be ignored during the first 30 seconds after the game started.
- Fixed: a Lua error on login ("Attempt to register unknown event AUCTION_ITEM_LIST_UPDATE") that also stopped RUIN Exchange from finishing its setup. Events the client doesn't have are now skipped quietly.

## 0.1.1 — 2026-10-17

- Fixed "RUIN_Core has been blocked from an action only available to the Blizzard UI" popups. RUIN no longer reassigns Blizzard's `StaticPopupDialogs` table or removes channels from Blizzard's chat frames, both of which tainted Blizzard UI code.
- The org key offer now uses RUIN's own Accept/Decline dialog instead of a Blizzard popup.
- Hidden channels are only joined or left out of combat.

## 0.1.0 — 2026-10-17

First test build for the WoW Forever beta.

- Comms layer: one `RUIN` addon prefix, GUILD / ORG / OFFICERS / PEER scopes, chunking for long messages, a throttled send queue, hidden password-protected org and officer channels.
- Org key: create, add/remove guilds, rotate, import/export as a copyable string, offer to another guild's leader in-game, automatic sharing to guild members, officer channel whispered between officers, edits announced to other guilds' officers.
- Unified guild chat: `/g` lines mirror to the other RUIN guilds as `[RUIN·Tag] Name: text`.
- Cross-guild officer chat: `/o` lines mirror to the other guilds' officers, with officer attestation and an "(unverified)" mark.
- Bridge election so guildmates without the addon are still relayed.
- Presence and version check: online list across the org, notice when a newer RUIN Core is in use.
- RUIN window with an Org tab, couch mode and a key binding; module API (`RUIN_API`) for future suite addons.
