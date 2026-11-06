# KewkyCamPortrait

WoW Forever addon for streaming: makes your character portrait on the player frame see-through, so a
webcam (in OBS, with a circle mask) can sit inside the portrait ring. The ring, name, bars and level
badge stay.

- `/kcp` toggles the portrait (hidden by default once installed).
- `/kcp level` toggles the level badge at the bottom of the ring, if it covers the cam.
- `/kcp where` prints the portrait's position and size in screen pixels, to place the cam source in OBS.

## Install

1. Download **[KewkyCamPortrait.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyCamPortrait.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with
   `AddOns/KewkyCamPortrait/KewkyCamPortrait.toc`.
3. Restart the game (new addons only load after a full restart, not `/reload`).
