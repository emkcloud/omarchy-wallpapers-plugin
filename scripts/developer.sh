#!/usr/bin/env bash
#
# Developer helper: install this checkout as a separate
# `emkcloud.wallpaper-manager-developer` plugin via symlinks, so it can coexist
# with a real `omarchy plugin add` install of the official id.
#
# Edits are not hot-reloaded: the shell watches ~/.config/omarchy/plugins with
# inotify, which does not follow symlinks. After changing QML run:
#   omarchy restart shell
#
#   scripts/developer.sh link     # create wrapper + enable + summon
#   scripts/developer.sh unlink   # remove the wrapper
#
# `link` also clears the dataset cache, so a dev session always exercises the
# download path.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
DEV_ID="emkcloud.wallpaper-manager-developer"
DEV_DIR="$PLUGINS_DIR/$DEV_ID"
MARKER="$DEV_DIR/.dev-wrapper"
LINKS=(interface scripts config assets help)
# Datasets live in the app cache, outside the watched plugin dir (see manager.sh).
DEV_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/$DEV_ID"

die() {
  echo "developer.sh: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<EOF
Usage: $0 <link|unlink>

  link     Install this checkout as $DEV_ID via symlinks and clear the cache
  unlink   Remove the $DEV_ID wrapper

Repository: $REPO
EOF
}

cmd_link() {
  [[ -f "$REPO/manifest.json" ]] || die "not a plugin repo: $REPO"
  command -v jq >/dev/null 2>&1 || die "jq is required"

  mkdir -p "$DEV_DIR"

  local d
  for d in "${LINKS[@]}"; do
    if [[ -e "$REPO/$d" ]]; then
      ln -sfn "$REPO/$d" "$DEV_DIR/$d"
    fi
  done

  # Derive the dev manifest from the official one so it never drifts.
  jq --arg id "$DEV_ID" --arg name "Wallpaper manager (dev)" \
    '.id = $id | .name = $name' "$REPO/manifest.json" >"$DEV_DIR/manifest.json.tmp"
  mv -f -- "$DEV_DIR/manifest.json.tmp" "$DEV_DIR/manifest.json"
  : >"$MARKER"

  # Drop the dataset cache so a dev session always exercises the download path.
  rm -rf -- "$DEV_CACHE/datasets"

  omarchy-shell shell rescanPlugins >/dev/null

  local i
  for ((i = 0; i < 40; i++)); do
    if omarchy-plugin-list --json | jq -e --arg id "$DEV_ID" 'any(.[]; .id == $id)' >/dev/null; then
      break
    fi
    sleep 0.05
  done

  # Disable first so enabling re-inserts the bar entry: a plugin already enabled
  # as a plain overlay keeps its old location and would never show in the bar.
  omarchy plugin disable "$DEV_ID" >/dev/null 2>&1 || true
  omarchy plugin enable "$DEV_ID"
  omarchy-shell shell summon "$DEV_ID" '{}' >/dev/null || true

  echo "Developer plugin ready: $DEV_ID"
  echo "Edit the repo, then: omarchy restart shell"
}

cmd_unlink() {
  [[ -f "$MARKER" ]] ||
    die "refusing: $DEV_DIR is not a developer wrapper (missing .dev-wrapper)"

  omarchy plugin disable "$DEV_ID" >/dev/null 2>&1 || true
  rm -rf -- "$DEV_DIR"
  omarchy-shell shell rescanPlugins >/dev/null
  echo "Removed $DEV_ID"
}

case "${1:-}" in
link) cmd_link ;;
unlink) cmd_unlink ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage
  exit 1
  ;;
esac
