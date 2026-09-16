# Omarchy Wallpapers Plugin

![Omarchy Wallpapers Plugin](assets/images/banner.png)

An [Omarchy](https://github.com/omacom/omarchy) shell plugin to browse, preview,
install and manage the wallpaper collection, theme by theme, straight from the
bar: pick a collection, leaf through every wallpaper full screen, install or
remove single images or whole themes, and set your next background without ever
leaving the desktop.

https://github.com/emkcloud/omarchy-wallpapers

The plugin (`emkcloud.wallpaper-manager`) talks to a pinned snapshot of the
remote repository, so it keeps working offline once the catalogue is cached, and
installs wallpapers natively into the active Omarchy theme.

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
- **Theme-aware UI** — colors, borders and rounding follow the active Omarchy
  theme.

## Requirements

- Omarchy Linux `0.4.0` or newer (Quickshell).
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

## Removal

Remove the plugin the same way as any other Omarchy plugin:

```bash
omarchy plugin remove emkcloud.wallpaper-manager
```

This disables the plugin and deletes its git checkout. It does **not** touch
your wallpapers or the runtime caches, so cleanup is opt-in:

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
removal requires no elevated privileges.

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
- **Pinned release** — wallpapers come from the pinned release, not from the
  `main` branch.
- **Caches** — the dataset and the big images are stored in
  `~/.cache/omarchy/<plugin-id>/`.

## Security

Only image files are accepted at install time: a catalogue entry whose extension
is not in the allowlist (`webp`, `jpg`, `jpeg`, `png`) is skipped, so a malformed
or malicious entry cannot drop a non-image into the wallpaper folder. Every
download is also pinned to the `sha256` recorded in the catalogue and discarded
if it does not match. Installed wallpapers live in
`~/.config/omarchy/backgrounds/<theme>/`.

## License

This project is licensed under the [MIT License](LICENSE).
