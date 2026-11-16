# Huens Liste

## v1.14.0
- Well Fed reminder is clickable: "Choose food" in the Quality of Life tab lists the food in your bags (other usable consumables after it). Pick your buff food once; when the reminder shows, click it to eat. The line under the text says what the click does, or that the food isn't in your bags. Out of combat only. Also `/hl food Item Name` and `/hl food clear`.

## v1.13.0
- Reminders (Well Fed, campfire, chosen buff, weapon imbue): each row in the Quality of Life tab has a new "Icon" checkbox. With it ticked the reminder is just the pulsing icon, without the text. Click-to-apply and click-to-cast still work on the icon; the line that explains the clicks is hidden in this mode. The Move and Reset buttons are a bit narrower to make room.

## v1.12.0
- Riding trinket (Quality of Life tab, off by default): while you are mounted the addon equips the Carrot on a Stick, and when you dismount it puts your normal trinket back. Gear can't be swapped in combat, so if you get dismounted in a fight the swap back happens as soon as combat ends. "Set up" lets you pick another trinket and choose the upper or lower trinket slot (default: lower). Not used on flight paths, in battlegrounds or arenas. `/hl mount [on/off]`.

## v1.11.1
- Chat messages about list changes: the word "added" is green and "removed" is red, for your own changes and for those of friends.
- Chosen-buff reminder: two new options at the bottom of the "Set up buffs" list (the button was called "Choose buffs"). "Only show in combat" keeps the text away until a fight starts; "Hide in main cities" hides it in Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff and Undercity. Also `/hl remind combat [on/off]` and `/hl remind cities [on/off]`.

## v1.11.0
- Friends on the world map (Quality of Life tab, two separate options, both off by default). "Share my location with friends" sends your zone and position to the same people the lists sync with, at most every 30 seconds while you move and every 2 minutes while you stand still. "Show friends on the world map" draws a class-coloured pin with the name for everyone who shares; hover it for zone and age. Pins disappear 5 minutes after the last update or when the friend enters a dungeon, raid or battleground (the game gives no position there). `/hl where` lists everyone in chat; `/hl location [on/off]`, `/hl map [on/off]`.
- The chosen-buff reminder is clickable like the weapon one: when a missing buff is a spell you know (for example Find Minerals), left-click the text to cast it; with two missing, right-click casts the second. The line under the text says what a click does. Out of combat only.

## v1.10.0
- Click to apply: in the Quality of Life tab, "Choose imbue" lists your known shaman imbues and the poisons, stones and oils in your bags. Left-click one for the main hand, right-click for the off hand. When the weapon reminder shows, left-click the text to apply the first missing one and right-click for the second. The line under the text says what a click does, or that the item isn't in your bags. Out of combat only: the game doesn't allow addons to offer such a button in combat. Also `/hl imbue main Name`, `/hl imbue off Name`, `/hl imbue clear`.

## v1.9.0
- Weapon imbue reminder (Quality of Life tab, off by default): a movable "No weapon imbue: main hand + off hand" text while a weapon you hold has no temporary enchant (shaman imbues like Windfury Weapon, rogue poisons, sharpening stones, oils). The off hand only counts when it holds a weapon, so shields and off-hand items are ignored, as are fishing poles. `/hl weapon [on/off]`. `/hl buffs` also prints the weapon imbue state.

## v1.8.0
- Own buff reminders (Quality of Life tab, off by default): choose any buffs you always want up, for example Find Minerals, and a movable "Missing: Find Minerals" text shows while one of them is gone. "Choose buffs" lists your current buffs to click; `/hl remind add Buff Name` adds one by name without having it. Also `/hl remind [on/off]`, `del Buff Name`, `clear`, `list`.

## v1.7.1
- Campfire reminder: taking the extra experience gives the Boosted Rest debuff (spell 1229451) instead of the buff. That now counts too, and the text is "No campfire or Boosted Rest buff!".

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
- Campfire buff reminder (Quality of Life tab, off by default): works like the Well Fed reminder, with its own movable text "Campfire buff is missing!" while you don't have the campfire buff (spell 1229741). No setup needed. Also `/hl campfire [on/off]`. The Well Fed and campfire rows each have their own Move / Reset buttons.
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
