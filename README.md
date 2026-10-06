# Omarchy Wallpapers Plugin

![Omarchy Wallpapers Plugin](assets/images/banner.webp)

An [Omarchy](https://github.com/omacom/omarchy) shell plugin to browse, preview,
install and manage the wallpaper collection, theme by theme, straight from the
bar: pick a collection, leaf through every wallpaper full screen, install or
remove single images or whole themes, and set your next background without ever
leaving the desktop.

https://github.com/emkcloud/omarchy-wallpapers

The plugin (`emkcloud.wallpaper-manager`) talks to a versioned snapshot served
from a CloudFront CDN, so it keeps working offline once the catalogue is cached,
and installs wallpapers natively into the active theme.

## Features

- **Theme browser** — master/detail screen: theme preview, palette, description
  and install counts.
- **Wallpaper grid** — lazy thumbnails, search, installed/default state per
  tile.
- **Fullscreen preview** — hi-res image, thumbnail filmstrip, install/uninstall,
  set-as-default.
- **Bulk operations** — install a whole theme, uninstall it, or install a random
  sample of wallpapers.
- **Live progress** — the footer bar and the list keep counting while an
  operation runs.
- **Search** — a small search engine to filter themes and wallpapers.
- **Favorites** — star a wallpaper once and install it in any theme, with a
  one-click install card.
- **Automatic rotation** — cycle the current theme's wallpapers on a schedule.
- **Theme-aware UI** — colors, borders and rounding follow the active Omarchy
  theme.

## Requirements

- Omarchy Linux `4.0.4` or newer (Quickshell).
- Packages: `curl` and `jq` (installed by default in Omarchy).
- The Omarchy wallpaper tools shipped with the desktop.

## Installation

The repository root is the plugin, so install it from git:

```bash
omarchy plugin add https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes
```

Summon it from the CLI too:

```bash
omarchy-shell shell summon emkcloud.wallpaper-manager '{}'
```

Update to the latest snapshot with:

```bash
omarchy plugin update emkcloud.wallpaper-manager --yes
```

## Screenshots

<table>
  <tr>
    <td><a href="assets/images/screenshots/theme-selection-2k.webp"><img src="assets/images/screenshots/theme-selection.webp" alt="Theme selection"></a></td>
    <td><a href="assets/images/screenshots/wallpapers-2k.webp"><img src="assets/images/screenshots/wallpapers.webp" alt="Wallpaper grid"></a></td>
    <td><a href="assets/images/screenshots/preview-2k.webp"><img src="assets/images/screenshots/preview.webp" alt="Wallpaper preview"></a></td>
  </tr>
  <tr>
    <td><a href="assets/images/screenshots/downloading-2k.webp"><img src="assets/images/screenshots/downloading.webp" alt="Download in progress"></a></td>
    <td><a href="assets/images/screenshots/help-2k.webp"><img src="assets/images/screenshots/help.webp" alt="Guide and support"></a></td>
    <td><a href="assets/images/screenshots/settings-2k.webp"><img src="assets/images/screenshots/settings.webp" alt="Settings and options"></a></td>
  </tr>
</table>

## Removal

Remove the plugin the same way as any other Omarchy plugin:

```bash
omarchy plugin remove emkcloud.wallpaper-manager
```

This disables the plugin and deletes its git checkout. It does **not** touch
your wallpapers or the runtime caches, so cleanup is entirely opt-in and left to
you:

- **Installed wallpapers** live in `~/.config/omarchy/backgrounds/<theme>/`.
  Remove only the ones you installed, or the whole folder of a theme you no
  longer want.
- **Runtime caches** (catalogue and images) live in
  `~/.cache/omarchy/emkcloud.wallpaper-manager/`. Deleting the folder is safe;
  it is rebuilt on the next run.
- If one of the wallpapers is your **current background**, reset it to the
  theme default before deleting it, otherwise the desktop keeps pointing at a
  missing file.

The plugin never modifies your configuration without an explicit action, and
removal is always available.

## How it works

The QML overlay is a thin controller; all the heavy lifting is done by
`scripts/manager.sh` (bash + `curl` + `jq` + `sha256`). The script prints
tab-separated records on stdout that the QML parses into list models.

- **Data** — `datasets.json` lists the themes; each theme has a `catalog.json`
  with its wallpapers.
- **Install / Remove** — files are downloaded atomically and verified with
  `sha256`.
- **Set default** — downloads the file first if needed, then calls
  `omarchy-theme-bg-set`.
- **Versioned CDN snapshot** — wallpapers come from a versioned CloudFront base.
- **Caches** — the dataset and the big images are stored in
  `~/.cache/omarchy/<plugin-id>/`.

## Automatic rotation

The plugin can change the background on its own, so a theme stays fresh without
touching it by hand. Everything is configured in **Setup → Automatic rotation**:

- **Enable feature** — turn the timer on or off.
- **Interval time** — how long each wallpaper stays up before the next one (1,
  5, 15, 30, 60 or 120 minutes).
- **Include theme wallpapers** — off rotates only the wallpapers you installed
  from the collection.
- **Random order** — sequential by name, or pick at random (never the one already
  on screen).
- **Rotate now** — change the background immediately with the settings above,
  even when the timer is off.

Rotation follows the **current Omarchy theme**, so switching theme switches the
pool. It only uses files already on disk — nothing is downloaded — and it keeps
running with the overlay closed, from shell start to shell restart. Turning the
switch off leaves the current wallpaper in place.

## Showcase

<table>
  <tr>
    <td><a href="assets/images/showcase/showcase-001-tokyo-night-2K.webp"><img src="assets/images/showcase/showcase-001-tokyo-night.webp" alt="Tokyo Night preview 1"></a></td>
    <td><a href="assets/images/showcase/showcase-002-tokyo-night-2K.webp"><img src="assets/images/showcase/showcase-002-tokyo-night.webp" alt="Tokyo Night preview 2"></a></td>
    <td><a href="assets/images/showcase/showcase-003-tokyo-night-2K.webp"><img src="assets/images/showcase/showcase-003-tokyo-night.webp" alt="Tokyo Night preview 3"></a></td>
  </tr>
  <tr>
    <td><a href="assets/images/showcase/showcase-004-osaka-jade-2K.webp"><img src="assets/images/showcase/showcase-004-osaka-jade.webp" alt="Osaka Jade preview 1"></a></td>
    <td><a href="assets/images/showcase/showcase-005-osaka-jade-2K.webp"><img src="assets/images/showcase/showcase-005-osaka-jade.webp" alt="Osaka Jade preview 2"></a></td>
    <td><a href="assets/images/showcase/showcase-006-osaka-jade-2K.webp"><img src="assets/images/showcase/showcase-006-osaka-jade.webp" alt="Osaka Jade preview 3"></a></td>
  </tr>
  <tr>
    <td><a href="assets/images/showcase/showcase-007-matte-black-2K.webp"><img src="assets/images/showcase/showcase-007-matte-black.webp" alt="Matte Black preview 1"></a></td>
    <td><a href="assets/images/showcase/showcase-008-matte-black-2K.webp"><img src="assets/images/showcase/showcase-008-matte-black.webp" alt="Matte Black preview 2"></a></td>
    <td><a href="assets/images/showcase/showcase-009-matte-black-2K.webp"><img src="assets/images/showcase/showcase-009-matte-black.webp" alt="Matte Black preview 3"></a></td>
  </tr>
  <tr>
    <td><a href="assets/images/showcase/showcase-010-gruvbox-2K.webp"><img src="assets/images/showcase/showcase-010-gruvbox.webp" alt="Gruvbox preview 1"></a></td>
    <td><a href="assets/images/showcase/showcase-011-gruvbox-2K.webp"><img src="assets/images/showcase/showcase-011-gruvbox.webp" alt="Gruvbox preview 2"></a></td>
    <td><a href="assets/images/showcase/showcase-012-gruvbox-2K.webp"><img src="assets/images/showcase/showcase-012-gruvbox.webp" alt="Gruvbox preview 3"></a></td>
  </tr>
</table>

## Available themes

- **Catppuccin** — soothing pastel accents over deep dark backgrounds.
- **Gruvbox** — retro groove color scheme with warm earthy browns and muted greens.
- **Matte Black** — matte black backgrounds with a strong orange accent.
- **Nord** — cold, muted blue-gray tones from the Nord palette, with crisp arctic-inspired contrast.
- **Osaka Jade** — a fresh jade green palette with warm highlights.
- **Solitude** — minimal monochrome near-black backgrounds with quiet gray tones.
- **Tokyo Night** — deep blue backgrounds with cyan and purple neon accents.

## Available collections

- **Countries** — panoramas and iconic scenery inspired by individual countries.
- **Machines** — computing machines through the decades, from 1960s mainframes to today's AI.
- **Shelters** — cozy improvised refuges tucked into the city.

## License

This project is licensed under the [MIT License](LICENSE).
