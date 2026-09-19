# Multi Monitor

By default every output shows the same wallpaper: Omarchy paints a single
background across the whole session. **Multi Monitor** is about giving each
Hyprland output its own wallpaper, so a laptop panel and an external screen can
carry different images.

This is not implemented yet; it is on the roadmap. The rest of this page explains
how outputs work, how Omarchy handles the background today, and how the plugin
will implement per-output wallpapers.

## Hyprland

Hyprland identifies each output by its **name**, not by a number or a position on
the desk. List the active ones with:

```sh
hyprctl monitors -j | jq -r '.[] | select(.disabled == false) | .name'
```

Typical names are `eDP-1` for the laptop panel, `DP-1` / `DP-2` for DisplayPort or
`HDMI-A-1` for HDMI; a virtual output may be called `Virtual-1`. A name is stable
for a given port, which makes it the right key for a per-monitor setting.

Omarchy, however, manages **one** background for the whole session:

- the `omarchy.background` shell service draws the image on every output;
- the image is the file behind the symlink
  `~/.local/state/omarchy/current/background`;
- it is changed with `omarchy theme bg set <path>`, and the backgrounds of a
  theme live under `~/.config/omarchy/backgrounds/<theme>/`.

Because that renderer keeps a single image, there is no per-output setting today.
To give each monitor its own wallpaper, the single background has to give way to
a per-output renderer.

## How the plugin will implement it

1. **Detect the outputs.** Read `hyprctl monitors -j` and keep the active
   outputs (name, size, position, scale). Refresh on the `monitoradded` and
   `monitorremoved` events so hot-plugging is handled.
2. **Store a per-output mapping.** Each monitor name maps to a chosen wallpaper,
   a file already installed under the local background directory. An output with
   no mapping falls back to the current theme background, so a freshly plugged
   screen is never blank.
3. **Pick a wallpaper per output in Setup.** The Setup screen lists the detected
   outputs, one row each, with the wallpaper chosen from the installed
   collection. You do not type a monitor count: the plugin reads the connected
   outputs and you assign one wallpaper to each.
4. **Render one surface per output.** A single global image cannot express a
   per-output choice, so the plugin draws its own background surface per screen
   (`Quickshell.screens` → a `PanelWindow` on `WlLayer.Background`, keyed by
   `screen.name`). That requires the built-in `omarchy.background` service to
   yield; until then this stays a proposal.
5. **Persist and restore.** The mapping survives restarts and theme changes: the
   files are re-resolved after `omarchy theme set` and re-applied.

> Until this ships, use different themes or backgrounds per workspace, or a
> dedicated wallpaper daemon, if you really need a distinct image on each
> screen.
