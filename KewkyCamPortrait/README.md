# KewkyCamPortrait

WoW Forever addon for streaming: makes your character portrait on the player frame see-through, so a
webcam (in OBS, with a circle mask) can sit inside the portrait ring. The ring, name, bars and level
badge stay.

- `/kcp` toggles the portrait (hidden by default once installed).
- `/kcp level` toggles the level badge at the bottom of the ring, if it covers the cam.
- `/kcp key` fills the empty circle with solid magenta so the cam can sit behind the ring (see below).
- `/kcp where` prints the portrait's position and size in screen pixels, to place the cam source in OBS.

## Cam behind the ring (OBS)

1. `/kcp key` in game.
2. In OBS, put the webcam source **below** the game capture in the source list, sized and placed over
   the portrait (`/kcp where` gives the numbers; make it a little bigger than the circle).
3. On the game capture: Filters, add **Color Key**, Key Color Type **Custom**, color `#FF00FF`.
   Start Similarity low (around 1 to 20) so nothing else in the game gets keyed.

The ring and level badge then draw over the cam. Without the key fill, put the cam above the game
capture with a circle mask instead.

## Install

1. Download **[KewkyCamPortrait.zip](https://github.com/KewkLW/KewkyWoWForeverAddons/releases/latest/download/KewkyCamPortrait.zip)**.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with
   `AddOns/KewkyCamPortrait/KewkyCamPortrait.toc`.
3. Restart the game (new addons only load after a full restart, not `/reload`).
