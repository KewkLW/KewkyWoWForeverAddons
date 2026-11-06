# KewkyFriends

WoW Forever addon that shows which ruleset (Normal, PvP, Roleplaying) each Battle.net friend is
playing on, and whether you can group with them.

Forever has no realm list: you can only group with friends on the same region, ruleset and faction.
The friends list hides the server name, so a friend on another ruleset just gives "Cannot find player"
when you invite them. KewkyFriends shows:

- **Friend cards:** the ruleset after the zone, green when it matches yours, red when it doesn't, plus
  the faction in red if it differs from yours.
- **Card tooltip:** ruleset, server name, and "Can group with you" or the reason you can't.
- **Right-click menu:** the same ruleset and can-group lines.
- **`/kfr`:** prints every online Battle.net friend's character, server, faction and race in chat.

The ruleset is read from the last word of the server name ("CAMWOW US2 Realm 5 PvE" is Normal).

## Install

1. Download **[KewkyFriends.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyFriends.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with
   `AddOns/KewkyFriends/KewkyFriends.toc`.
3. Restart the game (new addons only load after a full restart, not `/reload`).

To update, replace the folder with the new zip's and `/reload`.
