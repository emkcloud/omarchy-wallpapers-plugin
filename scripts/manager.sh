#!/bin/bash
#
# Helper per il plugin emkcloud.wallpaper-manager.
# Scarica i dati dal repo emkcloud/omarchy-wallpapers e gestisce
# install/remove/set-default dei wallpaper nel tema Omarchy locale.
#
# Il ref del repo (un tag di release) viene letto da config.json e ogni URL
# assoluto che punta al repo viene rebasato su quel ref: i clienti restano
# congelati su una snapshot testata anche se `main` continua a cambiare.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="$PLUGIN_ROOT/config/config.json"
DEFAULT_REPO="emkcloud/omarchy-wallpapers"
DEFAULT_REF="main"
DEFAULT_DATASETS="datasets"

REPO="$DEFAULT_REPO"
REF="$DEFAULT_REF"
DATASETS_REL="$DEFAULT_DATASETS"
if [[ -f $CONFIG_FILE ]]; then
  cfg_repo="$(jq -r '.repo // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  cfg_ref="$(jq -r '.release // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  cfg_datasets="$(jq -r '.paths.datasets // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  [[ -n $cfg_repo ]] && REPO="$cfg_repo"
  [[ -n $cfg_ref ]] && REF="$cfg_ref"
  [[ -n $cfg_datasets ]] && DATASETS_REL="$cfg_datasets"
fi

RAW_BASE="https://raw.githubusercontent.com/$REPO/$REF"
DATASETS_URL="$RAW_BASE/datasets/datasets.json"

# Local cache of the pinned dataset. Gitignored except for `.gitkeep`, and
# tagged with the release in `.release`: since `omarchy plugin update` merges
# with `git merge --ff-only`, ignored files survive an update, so the marker is
# what tells us the cache belongs to a stale release.
DATASETS_DIR="$PLUGIN_ROOT/$DATASETS_REL"
DATASETS_JSON="$DATASETS_DIR/datasets.json"
DATASETS_REF_FILE="$DATASETS_DIR/.release"

DEST_BASE="$HOME/.config/omarchy/backgrounds"
STATE_BG="$HOME/.local/state/omarchy/current/background"
CONFIG_BG="$HOME/.config/omarchy/current/background"

usage() {
  cat >&2 <<EOF
Usage: $0 <command> [args...]
Commands:
  themes                            List themes as TSV (name,title,url,collections,count,preview)
  catalog <theme> <catalog-url>     Wallpapers of a theme as TSV
  install <theme> [filename]        Install all wallpapers, or one by filename/name/code
  remove <theme> [filename]         Remove all wallpapers, or one by filename/name/code
  set-default <theme> <filename> <url>  Download if needed + set as current background
Repository: $REPO@$REF
EOF
}

fetch() {
  curl -fsSL --max-time 60 "$@"
}

# Download $1 (URL) into $2, atomically (tmp + mv). Leaves no partial file.
download_file() {
  local url="$1" dest="$2" tmp
  mkdir -p "$(dirname -- "$dest")"
  tmp="$dest.tmp.$$"
  if fetch "$url" -o "$tmp"; then
    mv -- "$tmp" "$dest"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

# Drop the cached dataset but keep the tracked `.gitkeep`.
invalidate_datasets() {
  [[ -d $DATASETS_DIR ]] || return 0
  find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf -- {} +
}

# Warm every theme catalog once datasets.json is in place. Best effort: a
# failure here does not fail the caller, `ensure_catalog()` retries on demand.
prefetch_catalogs() {
  local theme path remote dest
  while IFS=$'\t' read -r theme path; do
    [[ -n $theme ]] || continue
    dest="$DATASETS_DIR/$theme/catalog.json"
    [[ -s $dest ]] && continue
    remote="$RAW_BASE/${path#/}"
    download_file "$remote" "$dest" || echo "Warning: could not cache catalog '$theme'." >&2
  done < <(jq -r '
    .themes | to_entries[]
    | select(.value.kind == "theme")
    | [.key, (.value.catalog.path // "")] | @tsv
  ' "$DATASETS_JSON")
  return 0
}

# Ensure the dataset for the pinned release is cached. The first run downloads
# `datasets.json` and then warms every catalog; later runs reuse the cache until
# the `.release` marker no longer matches.
ensure_datasets() {
  if [[ -s $DATASETS_JSON && -f $DATASETS_REF_FILE ]] \
    && [[ "$(cat -- "$DATASETS_REF_FILE" 2>/dev/null || true)" == "$REF" ]]; then
    return 0
  fi
  mkdir -p "$DATASETS_DIR"
  invalidate_datasets
  download_file "$DATASETS_URL" "$DATASETS_JSON" || return 1
  printf '%s\n' "$REF" >"$DATASETS_REF_FILE"
  prefetch_catalogs
}

# Ensure the catalog of one theme is cached. Normally the eager first-run
# prefetch already did it; this is the on-demand fallback.
ensure_catalog() {
  local theme="$1" path remote dest
  ensure_datasets || return 1
  dest="$DATASETS_DIR/$theme/catalog.json"
  [[ -s $dest ]] && return 0
  path="$(jq -r --arg t "$theme" '.themes[$t].catalog.path // empty' "$DATASETS_JSON" 2>/dev/null || true)"
  [[ -n $path ]] || path="datasets/$theme/catalog.json"
  remote="$RAW_BASE/${path#/}"
  download_file "$remote" "$dest"
}

# Rebase any absolute raw.githubusercontent.com/$REPO/<ref>/ URL onto the
# pinned REF, so data generated against `main` still resolves to the release.
rebase_url() {
  printf '%s\n' "$1" | sed -E \
    "s#^https://raw\.githubusercontent\.com/$REPO/[^/]+/#https://raw.githubusercontent.com/$REPO/$REF/#"
}

sha256_of() {
  sha256sum "$1" | cut -d' ' -f1
}

theme_installed_in_omarchy() {
  local theme="$1"
  [[ -d "$HOME/.config/omarchy/themes/$theme" \
    || -d "${OMARCHY_PATH:-/usr/share/omarchy}/themes/$theme" ]]
}

# Case-insensitive exact match on id/name/code/filename, then substring on name.
wallpaper_matches() {
  local term="$1" id="$2" name="$3" code="$4" filename="$5"
  local needle field
  needle="$(printf '%s' "$term" | tr '[:upper:]' '[:lower:]')"
  for field in "$id" "$name" "$code" "$filename"; do
    [[ "$(printf '%s' "$field" | tr '[:upper:]' '[:lower:]')" == "$needle" ]] && return 0
  done
  [[ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == *"$needle"* ]] && return 0
  return 1
}

# Cached wallpaper switcher thumbnails are stale after install/remove.
refresh_bg_cache() {
  command -v omarchy-theme-bg-cache >/dev/null 2>&1 || return 0
  omarchy-theme-bg-cache >/dev/null 2>&1 || true
}

# If the current background link dangles (its file was removed), fall back to
# the theme's own default background.
reset_dangling_background() {
  local link="" candidate f fallback="" dir
  for candidate in "$STATE_BG" "$CONFIG_BG"; do
    if [[ -L $candidate ]]; then link="$candidate"; break; fi
  done
  [[ -n $link ]] || return 0
  [[ -f "$(readlink -f "$link" 2>/dev/null || true)" ]] && return 0

  for dir in \
    "$HOME/.local/state/omarchy/current/theme/backgrounds" \
    "$HOME/.config/omarchy/current/theme/backgrounds"; do
    for f in "$dir"/*; do
      [[ -f $f ]] && { fallback="$f"; break; }
    done
    [[ -n $fallback ]] && break
  done
  [[ -n $fallback ]] || return 0
  omarchy-theme-bg-set "$fallback" >/dev/null 2>&1 || true
}

# Download one wallpaper unless the destination already matches its sha256.
download_one() {
  local url="$1" dest="$2" sha="$3"
  if [[ -f $dest && "$(sha256_of "$dest")" == "$sha" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if curl -fsSL --max-time 120 "$url" -o "$dest.tmp" 2>/dev/null \
    && [[ "$(sha256_of "$dest.tmp")" == "$sha" ]]; then
    mv -- "$dest.tmp" "$dest"
    return 0
  fi
  rm -f -- "$dest.tmp"
  echo "FAILED $(basename "$dest")" >&2
  return 1
}

cmd_themes() {
  ensure_datasets || {
    echo "Failed to fetch datasets." >&2
    return 1
  }
  local name title catalog collections count preview
  while IFS=$'\t' read -r name title catalog collections count preview; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$title" "$(rebase_url "$catalog")" "$collections" "$count" "$(rebase_url "$preview")"
  done < <(jq -r '
    .themes | to_entries[]
    | select(.value.kind == "theme")
    | [.key, (.value.title // .key), (.value.catalog.url // ""), (.value.collections | length), (.value.count // 0), (.value.preview // "")]
    | @tsv
  ' "$DATASETS_JSON")
}

cmd_catalog() {
  local theme="$1"
  ensure_catalog "$theme" || {
    echo "Failed to fetch catalog for '$theme'." >&2
    return 1
  }
  local filename name code url sha256 preview path current installed
  while IFS=$'\t' read -r filename name code url sha256 preview; do
    path="$DEST_BASE/$theme/$filename"
    if [[ -f $path ]]; then
      installed="1"
      if [[ "$(readlink -f "$STATE_BG" 2>/dev/null)" == "$path" ]]; then
        current="1"
      else
        current="0"
      fi
    else
      installed="0"
      current="0"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$filename" "$name" "$code" "$(rebase_url "$url")" "$sha256" "$installed" "$current" "$(rebase_url "$preview")"
  done < <(jq -r '.wallpapers[] | [.filename, .name, .code, .url, .sha256, (.preview // "")] | @tsv' \
    "$DATASETS_DIR/$theme/catalog.json")
}

cmd_install() {
  local theme="$1" selector="${2:-}"
  local catalog
  ensure_datasets || {
    echo "Failed to fetch datasets." >&2
    return 1
  }
  if [[ "$(jq -r --arg t "$theme" '.themes[$t] | type' "$DATASETS_JSON")" == "null" ]]; then
    echo "Theme '$theme' not found in the repository." >&2
    return 1
  fi
  theme_installed_in_omarchy "$theme" || {
    echo "Theme '$theme' is not installed in Omarchy. Install it first." >&2
    return 1
  }
  ensure_catalog "$theme" || {
    echo "Failed to fetch catalog for '$theme'." >&2
    return 1
  }
  catalog="$(cat -- "$DATASETS_DIR/$theme/catalog.json")"

  local -a sel_url=() sel_dest=() sel_sha=()
  local filename id name code url sha
  while IFS=$'\t' read -r filename id name code url sha; do
    if [[ -z $selector ]] || wallpaper_matches "$selector" "$id" "$name" "$code" "$filename"; then
      sel_url+=("$(rebase_url "$url")")
      sel_dest+=("$DEST_BASE/$theme/$filename")
      sel_sha+=("$sha")
    fi
  done < <(jq -r '.wallpapers[] | [.filename, .id, .name, .code, .url, .sha256] | @tsv' <<<"$catalog")

  if (( ${#sel_url[@]} == 0 )); then
    echo "No wallpaper matching '$selector' in theme '$theme'." >&2
    return 1
  fi

  mkdir -p "$DEST_BASE/$theme"
  local fail_file i
  fail_file="$(mktemp)"
  for i in "${!sel_url[@]}"; do
    download_one "${sel_url[$i]}" "${sel_dest[$i]}" "${sel_sha[$i]}" 2>>"$fail_file" &
    while (( $(jobs -rp | wc -l) >= 8 )); do
      wait -n || true
    done
  done
  wait || true

  refresh_bg_cache
  if [[ -s $fail_file ]]; then
    cat "$fail_file" >&2
    rm -f -- "$fail_file"
    return 1
  fi
  rm -f -- "$fail_file"
  echo "Installed ${#sel_url[@]} wallpaper(s) in $DEST_BASE/$theme."
}

cmd_remove() {
  local theme="$1" selector="${2:-}"
  local dest="$DEST_BASE/$theme"
  if [[ ! -d $dest ]]; then
    echo "No wallpapers installed for theme '$theme'." >&2
    return 1
  fi

  local catalog
  if ensure_datasets \
    && [[ "$(jq -r --arg t "$theme" '.themes[$t] | type' "$DATASETS_JSON" 2>/dev/null || true)" != "null" ]] \
    && ensure_catalog "$theme"; then
    catalog="$(cat -- "$DATASETS_DIR/$theme/catalog.json")"
  else
    catalog='{"wallpapers":[]}'
  fi

  local -A to_remove=()
  local filename id name code
  while IFS=$'\t' read -r filename id name code; do
    if [[ -z $selector ]] || wallpaper_matches "$selector" "$id" "$name" "$code" "$filename"; then
      to_remove["$filename"]=1
    fi
  done < <(jq -r '.wallpapers[] | [.filename, .id, .name, .code] | @tsv' <<<"$catalog")

  local f base removed=0
  for f in "$dest"/*; do
    [[ -f $f ]] || continue
    base="$(basename -- "$f")"
    if [[ ${to_remove["$base"]+set} ]]; then
      rm -f -- "$f"
      removed=$((removed + 1))
    fi
  done
  if (( removed > 0 )) && [[ -z "$(ls -A -- "$dest" 2>/dev/null)" ]]; then
    rmdir -- "$dest" 2>/dev/null || true
  fi

  reset_dangling_background
  refresh_bg_cache
  echo "Removed $removed wallpaper(s) from theme '$theme'."
}

cmd_set_default() {
  local theme="$1" filename="$2" url="$3"
  local path="$DEST_BASE/$theme/$filename"
  url="$(rebase_url "$url")"
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
