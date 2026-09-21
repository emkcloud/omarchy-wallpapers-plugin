# Setup

Setup is the configuration screen of the plugin: press `s` on any screen to open
it. It uses the same three columns as this guide — the roadmap on the left, the
settings of the selected section in the centre, and the section index with your
local usage on the right.

Two sections are available:

- **Download** — how new wallpapers are fetched and how much room they may take.
- **Automatic rotation** — change the background on its own.

Every change is saved automatically; there is no Save button. Move with the
arrows (or h / j / k / l), press enter or space to toggle a switch.

## Keyboard

| Key | Action |
|---|---|
| h / j / k / l | move the selection |
| arrows | move the selection |
| tab | switch between the section list and the fields |
| enter / space | toggle a switch, confirm an edit |
| left / right | change a value |
| pageup / pagedown | previous / next section |
| esc | back |

## Restore defaults

**Restore defaults** puts every setting back to its factory value in one step. It
only changes the settings, never the wallpapers already installed: nothing is
downloaded or deleted. Run it from the **Restore defaults** button in the ACTIONS
column on the right, or press `d` while Setup is open.

## Archive RAW

The whole collection also lives at the source. The **Archive RAW** button in the
footer (or `d` on the Help screen) opens the `datasets.json` of the version
currently in use on the CloudFront CDN in your browser. It lists every theme and
wallpaper with the absolute URLs of the full-resolution original files.
