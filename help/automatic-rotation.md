# Automatic rotation

Automatic rotation changes the desktop wallpaper on its own after a set interval,
so a theme stays fresh without switching it by hand. You pick the interval once
and the plugin keeps cycling through the theme's wallpapers.

This is not implemented yet; it is on the roadmap. The rest of this page explains
how Omarchy handles the background today and how the feature will be configured.

## How the background works today

Omarchy has no built-in rotation: the background stays until you change it. The
current one is drawn by the `omarchy.background` shell service and changed with:

```sh
omarchy theme bg set <path>   # set a specific background
omarchy theme bg next         # cycle to the next one
```

A theme's backgrounds live under `~/.config/omarchy/backgrounds/<theme>/`, and the
file currently in use is the symlink
`~/.local/state/omarchy/current/background`. Rotation simply means running that
change on a timer instead of on a key press.

## In Setup (planned)

The **Setup** screen will host the whole feature:

- **Enable Automatic rotation** — a switch that turns the timer on or off.
- **Rotation interval** — how long each wallpaper stays up before the plugin
  moves to the next one (for example every 5, 15 or 30 minutes).
- **Pool to rotate through** — which wallpapers are used:
  - **All theme wallpapers** — every background available for the current theme,
    the theme's own backgrounds and the ones you installed.
  - **Plugin wallpapers only** — only the wallpapers installed from the
    `omarchy-wallpapers` collection by this plugin.

When rotation is active the plugin advances the wallpaper by itself at each
interval, following the current theme and skipping any file that is missing.
Turning the switch off leaves the current wallpaper in place.
