#!/bin/bash
#
# Helper per il plugin emkcloud.wallpaper-manager.
# Scarica i dati dal repo emkcloud/omarchy-wallpapers e gestisce
# install/remove/set-default dei wallpaper nel tema Omarchy locale.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/emkcloud/omarchy-wallpapers/main"
DATASETS_URL="$REPO_URL/datasets/datasets.json"
WALLPAPERS_SCRIPT_URL="$REPO_URL/scripts/wallpapers.py"

DEST_BASE="$HOME/.config/omarchy/backgrounds"
STATE_BG="$HOME/.local/state/omarchy/current/background"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/wallpaper-manager"

usage() {
  echo "Usage: $0 <command> [args...]" >&2
  echo "Commands:" >&2
  echo "  themes                            List theme names (kind=theme)" >&2
  echo "  catalog <theme> <catalog-url>     Wallpapers of a theme as TSV" >&2
  echo "  install <theme> [name]            Install wallpapers (delegates to wallpapers.py)" >&2
  echo "  remove <theme> [name]             Remove wallpapers (delegates to wallpapers.py)" >&2
  echo "  set-default <theme> <filename> <url>  Download if needed + set as current background" >&2
}

fetch() {
  curl -fsSL --max-time 60 "$@"
}

theme_is_installed() {
  [[ -d "$DEST_BASE/$1" || -d "$HOME/.config/omarchy/themes/$1" || -d "/usr/share/omarchy/themes/$1" ]]
}

wallpapers_py() {
  local script="$CACHE_DIR/wallpapers.py"
  if [[ ! -f $script ]]; then
    mkdir -p "$CACHE_DIR"
    fetch "$WALLPAPERS_SCRIPT_URL" -o "$script.tmp" && mv "$script.tmp" "$script"
  fi
  python3 "$script" "$@"
}

cmd_themes() {
  fetch "$DATASETS_URL" | jq -r '
    .collections | to_entries[]
    | select(.value.kind == "theme")
    | [.key, .value.catalog.url] | @tsv
  '
}

cmd_catalog() {
  local theme="$1"
  local catalog_url="$2"
  local path current
  fetch "$catalog_url" | jq -r '.wallpapers[] | [.filename, .name, .code, .url, .sha256] | @tsv' | while IFS=$'\t' read -r filename name code url sha256; do
    path="$DEST_BASE/$theme/$filename"
    if [[ -f $path ]]; then
      installed="1"
      current=""
      if [[ "$(readlink -f "$STATE_BG" 2>/dev/null)" == "$path" ]]; then
        current="1"
      else
        current="0"
      fi
    else
      installed="0"
      current="0"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$filename" "$name" "$code" "$url" "$sha256" "$installed" "$current"
  done
}

cmd_install() {
  wallpapers_py install "$@"
}

cmd_remove() {
  wallpapers_py remove "$@"
}

cmd_set_default() {
  local theme="$1" filename="$2" url="$3"
  local path="$DEST_BASE/$theme/$filename"
  if [[ ! -f $path ]]; then
    mkdir -p "$DEST_BASE/$theme"
    fetch "$url" -o "$path"
  fi
  omarchy-theme-bg-set "$path"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  themes) cmd_themes ;;
  catalog) cmd_catalog "$@" ;;
  install) cmd_install "$@" ;;
  remove) cmd_remove "$@" ;;
  set-default) cmd_set_default "$@" ;;
  *) usage; exit 1 ;;
esac