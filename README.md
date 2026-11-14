# Huens Liste

**A shared kill-on-sight list (and avoid list) for you and your friends in WoW: Forever.**

Getting ganked? Put the ganker on the list. Everyone in your group of friends gets the same list. The next time any of you comes across that player, a pulsing skull and **KILL ON SIGHT** appear above their nameplate, together with a raid-warning alert. Your friends also get a chat message saying where they were spotted.

## Features
- **Two lists:** the **KOS List** for the enemy faction and the **Swine List** for toxic players of your own faction
- **Swine List alerts:** chat message + sound when someone on it joins your party/raid, when you join their group, or when they whisper you
- **Target nearby KOS:** key binding, macro or on-screen button that targets the KOS player you saw most recently
- **Log:** recent kills, deaths and sightings in one tab, color-coded
- **Search and sort** the lists; class and level of listed players; kills / deaths per KOS player
- **Options tab** with every setting; **high-priority** KOS players, **revenge** targets and **zone warnings**
- **Bounties** on KOS players, announced when someone claims them
- **Hotspots:** per-zone view of where KOS players have been active
- **Weekly kill board** and kill streak announcements
- **Guild-only sync** by default, so strangers can't change your lists
- **Kill counter:** honorable kills on KOS players are counted and shared; see who killed whom and who has the most KOS kills
- **Nameplate marker:** a skull and "KILL ON SIGHT" above every listed player
- **Alerts:** a raid warning plus a sound when a listed player appears near you (nameplate, target or mouseover)
- **Shared sightings:** your friends see "*Name* spotted in *Zone* by *You*"
- **In-game sync:** the list syncs automatically over guild, party/raid or a private channel. Friends who were offline catch up as soon as they log in. No website, no external app.
- **Right-click menu:** right-click any player and pick **Add to Huens Liste (KOS)** to add them with an optional reason
- **List window:** add, remove, see who added whom and when each player was last seen
- **Export/import:** share the whole list as a text string, e.g. on Discord
- **Quality of Life tab (all options off until you turn them on):** a movable **Well Fed reminder** that shows up while you have no food buff, a **campfire buff reminder**
- **Users tab:** see who in your group of friends has the addon, which version they run and who is online
- **Update notice:** a popup tells you when a friend has a newer version
- **Minimap button** and an addon compartment entry
- Built for Forever's two-part names. No libraries needed.

## Getting started
1. Install the addon (everyone in your group needs it).
2. **Same guild?** Nothing else to do. The list syncs over guild chat.
   **Different guilds?** Everyone types the same `/hl channel <name> <password>` once.
3. Right-click a ganker and pick **Add to Huens Liste (KOS)**.

## Commands
| Command | What it does |
|---|---|
| `/hl` | Open the list |
| `/hl add Firstname Lastname [reason]` | Add to the KOS List (enemy faction) |
| `/hl swine Firstname Lastname [reason]` | Add to the Swine List (your faction) |
| `/hl move Firstname Lastname` | Move between the two lists |
| `/hl note Firstname Lastname new note` | Change the note (or click the row in `/hl`) |
| `/hl target [reason]` | Add your target (KOS or Swine List, by faction) |
| `/hl del Firstname Lastname` | Remove a player |
| `/hl sync` | Sync now |
| `/hl channel <name> [password]` | Private sync channel (`/hl channel off` to stop) |
| `/hl guild` / `group` / `alerts` / `sound` / `share` / `remote` `[on/off]` | Toggles |
| `/hl minimap [on/off]` | Show/hide the minimap button |
| `/hl wellfed [on/off]` | Well Fed reminder on/off (move it in the Quality of Life tab) |
| `/hl campfire [on/off]` | Campfire buff reminder on/off (move it in the Quality of Life tab) |
| `/hl buffs` | List your buffs (troubleshooting) |
| `/hl offset <px>`, `/hl scale <0.5–2>` | Move/resize the nameplate skull |
| `/hl export`, `/hl import` | Share the list by copy & paste |
| `/hl log` | Recent kills, deaths and sightings; zone view |
| `/hl options` | All settings in one tab |
| `/hl prio Firstname Lastname` | Toggle high priority for a KOS player |
| `/hl bounty Firstname Lastname text` | Set a bounty on a KOS player (no text = remove) |
| `/hl macro` | Create a "KOS Target" macro that targets the nearby KOS player |
| `/hl notes` | Patch notes: what's new in each version |
| `/hl debug` | Print sync traffic in chat (troubleshooting) |

## How syncing works
Addons can't reach the internet, so every copy of the list syncs peer-to-peer in-game. Adds and removals go out right away. Every 5 minutes, on login and when joining a group, clients compare a short checksum and exchange only what differs. When two people edit the same entry, the newest change wins.

**Who can edit:** by default only members of your guild (and people in your private channel) are synced with; `/hl trust off` accepts group members from other guilds too. Everyone you sync with can add and remove entries. In a large guild, turn off guild sync (`/hl guild off`) and use a private channel with a password.

## Limitations
WoW: Forever uses Midnight's addon restrictions, so addons can no longer read the combat log. Huens Liste detects players through **nameplates, target and mouseover** and turns on enemy nameplates at login.
