# RUIN Core changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

(nothing yet)

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
