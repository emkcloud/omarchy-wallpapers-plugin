# Security

How the plugin handles the remote catalogue, and why.

## Threat model

Wallpapers, previews and the datasets that describe them are downloaded from a
remote CDN. The catalogue is therefore treated as **untrusted input at install
time**: everything it carries (file names, URLs, sizes, hashes) is data, not
instructions, and must not be able to make the installer write outside the
wallpaper folder.

The `sha256` recorded in the catalogue is not a trust anchor on its own — a
compromised catalogue would ship a matching hash — so it is only a integrity
check downstream of the controls below.

## Controls (`scripts/manager.sh`)

- **Extension allowlist** — `is_allowed_image()` accepts only `webp`, `jpg`,
  `jpeg`, `png`; anything else is skipped, so a crafted entry cannot drop a
  non-image (script, symlink, config) into the backgrounds folder.
- **Bare file name** — `is_safe_filename()` rejects an empty name, any directory
  component (`/`), `.` / `..` and a leading dash. A catalogue entry is a single
  file name, never a path.
- **Bare theme name** — a theme is a directory under `DEST_BASE` and comes from
  the same untrusted datasets, so `require_safe_theme()` applies the same rule
  to it in every command that takes a theme.
- **Path containment** — `download_one()` resolves the destination with
  `realpath -m` and refuses it unless it stays under `DEST_BASE`
  (`~/.config/omarchy/backgrounds/<theme>/`). This is defence in depth,
  independent of how the caller built the path.
- **Atomic writes** — downloads land on a `.tmp` file and are `mv`'d only after
  the `sha256` recorded in the catalogue matches; a mismatch is discarded, so a
  failed or interrupted write never replaces a good file.
- **`..` cannot become the background** — `cmd_set_default()` only accepts a file
  name that is also present in the theme's catalogue.

The install paths that read a catalogue name (`cmd_install()`,
`cmd_random_install()`, `cmd_set_default()`) apply `is_safe_filename()` and
`is_allowed_image()` before building any destination, and `require_safe_theme()`
validates the theme on entry.

## Reporting a vulnerability

Open a private security advisory on the repository
(`emkcloud/omarchy-wallpapers-plugin`) rather than a public issue, and include
the commit, a description and, if possible, a reproducer.
