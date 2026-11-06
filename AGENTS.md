# Guide for AI coding agents

Addons for WoW Forever (Interface 16001, modern `C_` APIs, Blizzard's "camelot" UI flavor). One folder per
addon; the folder name, its `.toc` and its `_Camelot.toc` must all match.

- Forever hides some values from addons ("secret values", mostly in combat). Check `issecretvalue`
  before comparing or doing math with them.
- Never write into Blizzard tables or `hooksecurefunc` Blizzard mixin tables; it taints everything built
  from them and the game blocks the next protected action ("blocked from an action"). Use
  `ScrollUtil` frame callbacks, `HookScript`, `Menu.ModifyMenu` and secure templates instead.
- Lua errors are logged by the game in `_forever_/Logs/General.log` (`[E][Lua]` lines). For blocked
  actions, `/console taintLog 1` writes `Logs/taint.log`.
- New addons and TOC changes need a full game restart; code changes need `/reload`.
- Releases: push a `v*` tag; `.github/workflows/release.yml` builds one zip per addon plus
  `KewkyWoWForeverAddons.zip`. Keep `## Version: dev` in the TOCs; the workflow fills it in. A new addon
  needs a row in README.md.
- Blizzard's UI source for this client is extracted locally under
  `~/build/wow-forever-mine/out/<build>/files/interface/addons/` (when present); read it before hooking.

## KewkyFriends

KewkyFriends is a WoW Forever (Interface 16001, modern `C_` APIs) addon that shows each Battle.net
friend's ruleset and faction. Grouping on Forever needs the same region, ruleset and faction; the
ruleset is the last word of the friend's `gameAccountInfo.realmName`.

- Forever uses the mainline card-style friends list (`FriendsListSocialCardMixin`, inside
  `SocialUIFrame.FriendsList.ScrollBox`). Hook it with `ScrollUtil.AddInitializedFrameCallback` and
  `HookScript` only. Never write into or `hooksecurefunc` Blizzard mixin tables: the first version did,
  every card copied the tainted key, and the friends frame got "blocked from an action".
- The right-click menu is `Menu.ModifyMenu("MENU_UNIT_BN_FRIEND", ...)`.
- `/kfr` dumps the raw friend data; use it to check the server-name format.

## KewkyChatTarget

KewkyChatTarget is a WoW Forever (Interface 16001, modern `C_` APIs) addon that adds Target to the
right-click menu on chat names.

- `TargetUnit` is protected, so the menu entry (`Menu.ModifyMenu` on `MENU_UNIT_FRIEND` and the
  roster menus) is covered by one `SecureActionButtonTemplate` overlay running `/targetexact <name>`.
  The overlay is placed in absolute UIParent coordinates, never parented or anchored to the pooled
  menu buttons, and is only set up and hidden out of combat.
- Forever names are first name + unique surname, and the surname sits where a realm normally would
  (`Name-Surname`). The macro tries both `Name-Surname` and `Name Surname`.

## KewkyDeathNote

Per-character PvP note (`KewkyDeathNoteDB.chars[playerGUID].players[enemyGUID]` with `kills`, `assists`,
`deaths` lists of `{t, theirs, mine, zone, via}`).

- `COMBAT_LOG_EVENT_UNFILTERED` is restricted, so: kills from `PARTY_KILL` (readable when the victim is a
  player); assists from `PARTY_KILL` by a group member, confirmed on `PLAYER_REGEN_ENABLED` by scanning
  `C_DamageMeter` DamageDone for your GUID (`combatSpells[].combatSpellDetails.unitName`), which is
  `SecretWhenInCombat`; deaths from `C_DeathRecap.GetRecapEvents()` (`causedDeath` event's `sourceName`,
  no GUID or level), matched by name to players cached from target/mouseover/nameplates.
- The meter's `unitName` meaning (target of your damage) and whether `PARTY_KILL` fires for solo kills
  are unconfirmed in game; `/kdn debug` prints both.
- The target glow is its own frame anchored to `TargetFrame`; nothing is written into `TargetFrame`.
