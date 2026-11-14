# Huens Liste

## v1.7.0
- New "Log" tab (`/hl log`): recent KOS kills (red) and sightings (yellow), newest first, with who, where and when. Filters for kills/sightings. Kills are shared with friends; sightings are your own plus the ones friends reported while you were online (kept 14 days).
- Guild-only sync (on by default): sync messages are only accepted from members of your guild, plus your private sync channel. Strangers in a pickup group can no longer change your lists. Toggle in the Users tab or with `/hl trust`. If you're not in a guild, everything is accepted as before.
- Search box and sortable columns (click a header) in the KOS and Swine lists.
- Class and level of listed players: stored when someone sees them, shared with sightings, shown in the list (class-colored name, Lv column), tooltips and sighting alerts.
- Deaths: when you die to a KOS player, it's recorded and shared. The KOS list shows kills / deaths, the Log shows deaths in purple. A death counts for a KOS player who was targeting you (or, if that can't be read, your target or the only KOS player around); deaths out of combat never count.
- Quiet zones (Quality of Life tab, off by default): no KOS alerts, sharing or log entries in battlegrounds/arenas, or in cities, inns and sanctuaries.
- Bounties: put a bounty text on a KOS player (right-click their row or the player, or `/hl bounty Firstname Lastname 50g from me`). It shows above the skull, in alerts, tooltips and the list (coin icon), syncs to friends, and is announced and removed when someone kills that player. Paying is up to you.
- Log tab: "Show zones" switches to a per-zone summary (sightings, kills, deaths and who was there) for the last 24 hours or 7 days.
- Users tab: new "Week" column with KOS kills since Monday, the week's leader in gold. Chat announces KOS kill streaks (3, 5, 10, 15, ... kills without dying to a KOS player).
- After a gank (Quality of Life tab, off by default): when you die in combat to an enemy player who isn't listed, a popup offers to add them to the KOS List with a prefilled note. Never in battlegrounds or arenas; a declined player isn't offered again that session.
- Options tab (`/hl options`): alerts, sounds, alert cooldown, skull size and height, sync toggles and the private sync channel, all with checkboxes and sliders instead of slash commands. The "Quality of Life" tab is now labelled "QoL" to make room.
- High priority: Shift-click a KOS row, use the right-click menu or `/hl prio Firstname Lastname`. High-priority players get a gold "HIGH PRIORITY" skull (25% bigger), their own banner and sound, a star in the list and sort to the top. Syncs to friends. New option "Normal KOS players: chat line only" keeps the banner and sound for high-priority players.
- Revenge: when a KOS player kills you, they are your revenge target for 10 minutes: orange "REVENGE" skull, always alerted, last line of the target macro (so they win), and "Revenge!" when you kill them.
- Zone warning: entering a zone prints one line if KOS players were active there in the last 30 minutes (from kills, deaths and sightings). At most once per zone every 5 minutes; toggle in the Options tab.
- Target macro order is now: everyone else, high priority, recently seen, recently seen + high priority, revenge target.
- Fixed: the "Target nearby KOS" key binding did nothing unless the on-screen button was on or `/hl macro` had been used. The macro is now created as soon as a key is bound.
- Fixed: once your full name was known, sync messages from a friend with the same first name and an identical list could be dropped as "your own echo".
- Fixed: a possible error when the game hides a unit name in a group roster update.

## v1.6.3
- Swine List alerts only on direct contact: when a Swine joins your party/raid, when you join their group, or when they whisper you. Being near them no longer alerts (the tooltip line stays).
- Fixed: KOS targeting found nobody. In Forever, /target inside an addon-built macro ("macrotext") doesn't work, so Huens Liste now keeps a real WoW macro "KOS Target" up to date (out of combat) with /target lines for the KOS players you saw most recently. The key binding, the on-screen button and the macro on your bar all run it. Stays under the 255-character macro limit.

## v1.6.2
- Fixed: the KOS target button/macro/key binding didn't target anyone. Forever only accepts `/target First Last` (not `/targetexact`), so the macro now uses that. Up to 15 names.

## v1.6.1
- Fixed: the X button didn't close the /hl window (and the export/import window) in combat; only Escape worked
- Kill counter: Forever's honor message ("You have been awarded 4 Honor.") has no name, so kills are now detected when a KOS player dies and you get honor / an honorable kill within a few seconds, or when they die as your target while you're fighting. `/hl debug` now shows each step of the kill detection.
- Target nearby KOS: a secure button that targets the KOS player you saw most recently. Use it via Key Bindings > AddOns > Huens Liste, `/hl macro` (creates a "KOS Target" macro), or the on-screen button (Quality of Life tab, off by default).

## v1.6.0
- KOS kill counter: when you or your group kill someone on the KOS List (honorable kill), the kill is recorded and shared with your friends. Kills column in the KOS List, killers and last kill in the tooltip.
- Users tab: "KOS Kills" scoreboard per player
- Fixed: you showed up twice in the Users tab. Names are now handled the same everywhere ("Vila Yeezy" = "Vila-Yeezy"), and the addon learns your full name from your own messages.
- Names are shown with first and last name everywhere
- Edit the note on anyone on a list: click their row in /hl, "Edit note" in the right-click menu, or `/hl note Firstname Lastname new note`. Changes sync to friends.
- New "Patch Notes" tab (`/hl notes`) with a short list of what changed in each version; after an update, chat points you to it

## v1.5.1
- Typing names works with a space or a dash: "Vila Yeezy" and "Vila-Yeezy" (input field and slash commands)
- All Quality of Life options are now opt-in. The Well Fed reminder is off until you tick it in the Quality of Life tab (it's switched off once for everyone who had it on automatically)

## v1.5.0
- New **Swine List** for toxic players of your own faction: chat message + sound when they join your group, when you join a group they're in, or when you target/mouse over them. No skull.
- KOS List is now for the enemy faction only: same-faction players no longer get a skull, and adding them to KOS is refused
- Move players between the two lists (row button, right-click menu, `/hl move`)
- `/hl swine Firstname Lastname [reason]`; `/hl target` picks the list by faction
- Both lists sync separately with friends; export/import per list
- Well Fed reminder now sits below windows like /hl

## v1.4.0
- New "Users" tab: everyone with the addon, their version (outdated ones highlighted), online status and how you're connected
- "Refresh" asks everyone online for their version

## v1.3.0
- New "Quality of Life" tab in the /hl window
- Well Fed reminder: movable on-screen warning while you have no food buff
- `/hl wellfed [on/off]`, `/hl buffs`
- Update notice: a popup tells you when a friend has a newer version (also shown in the minimap tooltip)

## v1.2.1
- First automatic release from GitHub (no gameplay changes)

## v1.2.0
- Support for WoW Forever's two-part, realmless names ("First Last")
- Fixed sync: names no longer lose their surname when shared with friends
- `/hl add Firstname Lastname [reason]`
- `/hl debug` prints sync traffic for troubleshooting
- Broken entries from older versions are cleaned up automatically

## v1.1.0
- Minimap button (left-click: list, right-click: sync, drag: move)
- Addon compartment entry

## v1.0.0
- First release: shared kill-on-sight list, nameplate skull, alerts, in-game sync, export/import
