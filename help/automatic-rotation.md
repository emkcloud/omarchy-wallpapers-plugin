# Automatic rotation

Automatic rotation changes the desktop wallpaper on its own after a set interval,
so a theme stays fresh without switching it by hand. You pick the interval once
and the plugin keeps cycling through the theme's wallpapers.

## In Setup

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
