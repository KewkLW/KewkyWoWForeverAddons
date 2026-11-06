# KewkyDeathNote

WoW Forever addon that keeps a note of every enemy player who killed you, and every player you
killed or helped kill, with their level and yours at the time.

- **`/kdn`** (or `/deathnote`) opens the note: one row per player with their name, class and
  K / A / D. Click a row to drop down every kill, assist and death with their level, your level,
  the zone and the time. The header shows your totals and K/D.
- **Target glow:** when you target someone in the note, a red glow pulses around the target frame
  with your K / A / D and K/D against them.
- **Enemy alert:** when a player of the other faction shows up near you, a sound plays and a banner shows
  their name, level, race and class. Someone already in your Death Note gets the loud raid-warning sound
  and a red banner with your record against them. The same player alerts again only after 2 minutes, and
  it stays quiet in battlegrounds and arenas. It turns on enemy nameplates (that's how nearby enemies
  become visible to addons, about 40-60 yards); `/kdn alert` turns it off and restores your settings.
- Kept per character.

## How it counts

Forever restricts the combat log for addons, so the addon uses what the game does share:

- **Kill:** you or your pet landed the killing blow on a player.
- **Assist:** someone in your group landed the killing blow and the damage meter shows you damaged
  that player in the fight. This is checked when combat ends, because the meter is hidden from
  addons during combat. If the meter is turned off, a kill on your recent target counts instead.
- **Death:** the killing blow in your death recap, if it came from a player you saw (targeted,
  moused over or saw a nameplate for) in the last 5 minutes. Kills by pets and players you never
  saw are not recorded.

Levels come from the last time you saw the player; "??" means they were too high to show a level.

- `/kdn debug` prints what the addon sees (kill events, death recap, damage meter) to chat.
- `/kdn alert` turns the enemy alert on or off.
- `/kdn reset` clears the note for the current character.

## Install

1. Download **[KewkyDeathNote.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyDeathNote.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with
   `AddOns/KewkyDeathNote/KewkyDeathNote.toc`.
3. Restart the game (new addons only load after a full restart, not `/reload`).
