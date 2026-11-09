# Huens Liste

## v1.6.0
- KOS kill counter: when you or your group kill someone on the KOS List (honorable kill), the kill is recorded and shared with your friends. Kills column in the KOS List, killers and last kill in the tooltip.
- Users tab: "KOS Kills" scoreboard per player
- Fixed: you showed up twice in the Users tab. Names are now handled the same everywhere ("Vila Yeezy" = "Vila-Yeezy"), and the addon learns your full name from your own messages.
- Names are shown with first and last name everywhere
- Edit the note on anyone on a list: click their row in /hl, "Edit note" in the right-click menu, or `/hl note Firstname Lastname new note`. Changes sync to friends.

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
