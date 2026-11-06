# KewkyChatTarget

WoW Forever addon that adds **Target** to the right-click menu on player names in chat (and in the
guild, community and chat-channel rosters). If the player is near you, they become your target; if
not, it says they're not in range.

The game's own Target entry only appears when the name belongs to a unit you can see, and addons
can't target by name themselves, so the entry is backed by a secure button running `/targetexact`.
Like Blizzard's own Target entry, it only works out of combat.

- `/kct debug` prints the menu each right-click opens, for troubleshooting.

## Install

1. Download **[KewkyChatTarget.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyChatTarget.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with
   `AddOns/KewkyChatTarget/KewkyChatTarget.toc`.
3. Restart the game (new addons only load after a full restart, not `/reload`).

To update, replace the folder with the new zip's and `/reload`.
