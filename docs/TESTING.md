# Testing guide

How to verify a change in this repository. Three layers: **unit tests**,
**static checks** and a **manual pass** on the running shell. The first two are
dependency-free and offline, so they stay CI-friendly and never trip the
marketplace security review.

## Unit tests

`interface/js/Model.js` holds the pure logic (parsers, labels, cursor math,
Markdown splitting) with no Qt or Quickshell dependency, so it is unit-tested
directly with Node's built-in test runner — **no dependencies, no install, no
network**:

```bash
node --test            # from the repo root, discovers tests/*.test.js
```

The tests live in `tests/model.test.js` and cover `parseThemes` / `parseCatalog`
(TSV edge cases), the labels and search matchers, the cursor and status helpers,
`parseHelpIndex` / `parseRoadmap`, `inlineMarkdown`, and `parseMarkdown`
including the wrapped- and nested-list handling that the Help screen relies on.

The module ends with a guarded CommonJS export block so it can be `require`d
from the tests; QML never defines `module`, so that block is a no-op inside the
plugin. Keep the suite dependency-free so it stays CI-friendly and never trips
the marketplace security review.

## Static checks

Shell script syntax:

```bash
bash -n scripts/manager.sh
```

QML with `qmllint`. On Omarchy it is not on `PATH`: call
`/usr/lib/qt6/bin/qmllint`. It needs an import directory containing a `qs`
symlink to the shell (the same trick the shell's own code uses):

```bash
mkdir -p /tmp/qs && ln -sf /usr/share/omarchy/shell /tmp/qs/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qs \
  interface/WallpaperManager.qml interface/BarLauncher.qml \
  interface/views/*.qml interface/sections/*.qml interface/components/*.qml
```

Only `Error:` lines matter. The residual `unqualified` / `missing-property`
warnings on `Style.*` and `Color.menu.*` are unavoidable — the shell's own code
produces them.

Plugin manifest, entry points and folder layout:

```bash
omarchy plugin validate .
```

It rejects symlinks anywhere inside the plugin folder, so the local `AGENTS.md`
must be a **regular gitignored file**, never a symlink (see `DEVELOPMENT.md` →
*Repository layout*).

## Manual / visual

The developer install is a wrapper of symlinks, so inotify does **not**
hot-reload edits. Restart the shell after every change and check the UI by hand:

```bash
omarchy restart shell
```

Then ask the user to open the overlay and report the result. Do **not** verify
the UI with screenshots (`grim` + reading the image): it is slow and expensive.

### Manual checklist

Work top to bottom after `omarchy restart shell`. Every line is something to
*look at and confirm* on the running overlay — the QML has no automated
behaviour test, so this list is the "feature" suite. Tick what passes and
report the rest.

**A. Open / close / navigation**

- [ ] The bar icon opens the overlay on the themes list; clicking it again hides it.
- [ ] A click on the scrim, the Close button, and `q` / `x` all close from every screen.
- [ ] `Esc` closes from themes; returns to themes from wallpapers; returns to the grid from preview; returns to the opening screen from Help and Setup.
- [ ] Exactly one tile is highlighted at a time, moving with both arrows/hjkl *and* mouse hover.

**B. Themes screen**

- [ ] The grid loads: preview thumbnail, uppercased name, "N collections · M wallpapers".
- [ ] `Enter` / click opens a theme and the wallpapers header shows that theme's name.
- [ ] `/` (or Tab) opens the search; typing filters; Backspace edits; `Esc` clears then closes.
- [ ] `Tab` moves the focus from the theme list to the detail action row (accent ring), Left/Right walk Browse/Install/Shuffle/Uninstall/Custom, `Enter`/Space activate, and `Down`/`Tab` return to the list; `Esc` closes (or clears the filter) exactly as from the list.
- [ ] Disabled actions are skipped by the focus: e.g. `Uninstall` when nothing is installed, `Install`/`Shuffle` when the theme is full.
- [ ] `/` (or Up on the first theme) opens the search; `Tab` no longer does.
- [ ] `f` shuffle installs 5 random wallpapers; `r` refresh; `i` install all; `u` uninstall all.
- [ ] `?` opens Help; `s` opens Setup.
- [ ] While a bulk action runs: the running overlay (opaque scrim + spinner) covers the screen, only `Esc` is accepted, and `Esc` stops it.

**C. Wallpapers screen**

- [ ] The grid shows the theme's wallpapers with code + name, installed disc, and the `DEFAULT` pill on the theme default.
- [ ] The collection picker (`All collections` + the theme's collections) narrows the grid.
- [ ] The search field filters by name/code and composes with the collection filter.
- [ ] Filter-row focus: `Up` / `/` / Tab enters it, Left/Right/Tab walk the four controls, `Enter`/Space activate, `Down` returns to the grid (filter kept).
- [ ] `Space` toggles the cursor tile's checkbox; clicking the checkbox toggles it *without* opening the preview.
- [ ] `Select all` / `Clear` fill and empty the selection; `Select all` respects the active filter.
- [ ] Install / Uninstall act on the checks when any are set, else on the cursor tile.
- [ ] The footer progress bar updates while installing/removing.
- [ ] `Enter` / click opens the preview; `u` / Del removes; `d` sets default; `r` refreshes; Back returns to themes.

**D. Preview**

- [ ] Full-bleed image; title `<theme> / <collection> / <name>`; meta shows file + size (or "failed to load").
- [ ] `h/l/j/k` or arrows walk the wallpapers; the filmstrip follows the selection.
- [ ] Navigating never shows a blank frame (previous image stays until the next is ready).
- [ ] Install is disabled when already installed and Uninstall when not; the state dot shows top-right.
- [ ] `Enter` installs; `u` uninstalls (urgent tint); `d` / double-click toggles the default (`DEFAULT` pill).
- [ ] `Download` opens `omarchy-file-select` (overlay hides), and the file is saved (numeric suffix on a name collision).
- [ ] `Esc` returns to the grid; while an action runs only `Esc` (stops it) works and the running overlay is up.

**E. Help**

- [ ] The hero Help button (or `?`, or `F1`) opens it: three columns (roadmap / topic / index + resources).
- [ ] `Enter` / Space open the highlighted topic; arrows/hjkl move the index; `PgUp`/`PgDn` scroll the topic.
- [ ] `p` proposes a feature; `d` opens the dataset; `Star` / `Archive RAW` open the configured URLs.
- [ ] `Esc` / hero Back return to the screen it was opened from; the hero title jumps to the themes list.

**F. Setup**

- [ ] Opened with `s` or the Setup buttons; sections are Download and Automatic rotation.
- [ ] Arrows/jk move, Tab cycles areas, `Enter`/Space toggle, numeric rows open an edit, the interval opens the `Dropdown`.
- [ ] Settings survive close/reopen (`~/.config/omarchy/<id>/settings.json`).
- [ ] Automatic rotation runs on the timer once enabled; "Rotate now" changes the background even with the switch off.
- [ ] A default chosen on a theme that is *not* the running one is remembered and applied after switching to that theme.

**G. Custom install**

- [ ] The themes detail `Custom Install` button (or `c`) opens the screen: 3×3 previews + theme info on the left, "WHAT TO INSTALL" cards on the right.
- [ ] The cards are `Full collection`, one `Full <Collection>` per collection, `Shuffle (N)`, `Select only`; each shows count, resolution and estimated size.
- [ ] The right pane appears complete in one go (no partial 3-card flash, no shifting rows) and, for a theme already warmed, with no "Loading catalog…" caption at all.
- [ ] Arrows/jk walk the rows, a single click only selects the card, `Enter`/Space/`i` (or a double click) run it, `Tab` jumps to the switch and back, `Esc` / hero Back return to the themes list.
- [ ] `b` opens the theme's grid (narrowed to the selected collection when a collection card is highlighted); `Esc` there returns to the custom screen with its state.
- [ ] `s` / `?` from the custom screen open Setup / Help, and `Esc` / Back there return to the custom screen (not the theme list).
- [ ] `Full collection` / a collection / `Shuffle` run the install with the running overlay; Esc cancels.
- [ ] A collection install names the **collection** in the caption (`Downloading 250 wallpapers…`), while the footer bar stays **theme-wide** (`NAME · N/500`, climbing as the theme fills up).
- [ ] With the switch on, an install (finished or stopped with Esc) also sets a random default **of the configured theme only** — live background when it is the running theme, otherwise remembered per theme; the switch state survives close/reopen.
- [ ] Card counts (`N installed`) refresh on their own after an install, including when stopped with Esc (no need to leave and re-enter).
- [ ] `Select only` lands on the wallpapers grid of that theme; `Esc` there returns to the custom screen with its state (not to the theme list), while entering a theme from the list returns to the list.
- [ ] `Refresh` reloads the custom catalog.

**H. Cross-cutting (actions)**

- [ ] Every install/remove shows the running overlay (scrim + accent spinner + pulsing caption).
- [ ] While it runs the hero actions are dimmed and navigation keys are no-ops.
- [ ] When it finishes, counts / badges / progress update in place, without a manual refresh.
- [ ] Install a theme's wallpapers into a theme that is **not** the running one, then watch `~/.cache/omarchy/image-selector/*.jpg` grow while the plugin sits idle: the native picker thumbnail warm runs detached after the install.
- [ ] Stop a bulk install with `Esc` at, say, half: the files already on disk still get their thumbnails (the cancel trap warms `WARM_THEME`), and opening `omarchy-theme-bg-switcher` on that theme is fast.

## Not covered (yet)

- `scripts/manager.sh` beyond `bash -n`: there is no integration test (it needs
  the network and the dataset cache).
- QML behaviour: there is no Qt Quick Test harness; the components are verified
  visually.
- No CI workflow and no `package.json`; the checks above are run by hand.
