# Automatic rotation

Automatic rotation changes the desktop wallpaper on its own after a set interval,
so a theme stays fresh without switching it by hand. You pick the interval once
and the plugin keeps cycling through the theme's wallpapers.

## How the background works

Omarchy has no built-in rotation: the background stays until you change it. The
current one is drawn by the `omarchy.background` shell service and changed with:

```sh
omarchy theme bg set <path>   # set a specific background
omarchy theme bg next         # cycle to the next one
```

A theme's backgrounds live under `~/.config/omarchy/backgrounds/<theme>/`, and the
file currently in use is the symlink
`~/.local/state/omarchy/current/background`. Rotation simply runs that change on
a timer instead of on a key press.

## In Setup

The **Setup** screen hosts the whole feature:

- **Enable feature** — a switch that turns the timer on or off.
- **Interval time** — how long each wallpaper stays up before the plugin moves to
  the next one (1, 5, 15, 30, 60 or 120 minutes).
- **Include theme wallpapers** — which pool is used:
  - **Off** — only the wallpapers this plugin installed for the current theme.
  - **On** — every background of the current theme, including the ones bundled
    with the theme itself.
- **Random order** — off advances in name order, on picks at random.
- **Rotate now** — changes the background immediately with the settings above,
  even when the switch is off.

## How it behaves

Rotation follows the **current Omarchy theme**, not the theme open in the
plugin: when you switch theme, the next tick uses the new theme's pool. Only
files already on disk are used, so rotation never downloads anything and skips a
wallpaper that is missing. Sequential rotation continues from whatever is on
screen; random rotation never picks the wallpaper already in use.

Turning the switch off leaves the current wallpaper in place. The plugin keeps
the timer alive while the shell runs, so rotation continues with the overlay
closed and picks up again after a shell restart.
