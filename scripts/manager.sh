#!/bin/bash
#
# Helper per il plugin emkcloud.wallpaper-manager.
# Scarica i dati dal repo emkcloud/omarchy-wallpapers e gestisce
# install/remove/set-default dei wallpaper nel tema Omarchy locale.
#
# La base CloudFront (un path versionato, es.
# https://content.emkcloud.com/wallpapers/1.1.0) viene letta da config.json:
# da lì si scarica `datasets/datasets.json`, che contiene già tutti gli URL
# assoluti versionati (cataloghi, preview, immagini). Nessun rebase: cambiare
# la base in config è sufficiente a passare a una nuova snapshot.

set -euo pipefail

# When the UI cancels an operation (Esc), kill the in-flight downloads and
# clear the partial `.tmp` files they leave behind. `download_one` runs curl as
# a child of a background job, so we must kill the grandchildren too before the
# job shells go away.
cleanup_children() {
  local p k
  for p in $(jobs -p 2>/dev/null || true); do
    for k in $(pgrep -P "$p" 2>/dev/null || true); do
      kill "$k" 2>/dev/null || true
    done
    kill "$p" 2>/dev/null || true
  done
  sleep 0.2
  find "${DEST_BASE:-$HOME/.config/omarchy/backgrounds}" -name '*.tmp' -type f -delete 2>/dev/null || true
  if [[ -n ${CACHE_BASE:-} && -d ${CACHE_BASE:-} ]]; then
    find "$CACHE_BASE" -name '.tmp.*' -type f -delete 2>/dev/null || true
  fi
  exit 130
}
trap cleanup_children INT TERM

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="$PLUGIN_ROOT/config/config.json"
DEFAULT_BASE="https://content.emkcloud.com/wallpapers/1.1.0"
DEFAULT_DATASETS="datasets"

BASE="$DEFAULT_BASE"
DATASETS_REL="$DEFAULT_DATASETS"
if [[ -f $CONFIG_FILE ]]; then
  cfg_base="$(jq -r '.base // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  cfg_datasets="$(jq -r '.paths.datasets // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  [[ -n $cfg_base ]] && BASE="${cfg_base%/}"
  [[ -n $cfg_datasets ]] && DATASETS_REL="$cfg_datasets"
fi

DATASETS_URL="$BASE/datasets/datasets.json"

# App cache, one directory per plugin id so the official and the developer
# installs never share files. The QML passes its manifest id via
# WALLPAPER_MANAGER_ID; a bare CLI run falls back to the official id.
WALLPAPER_MANAGER_ID="${WALLPAPER_MANAGER_ID:-emkcloud.wallpaper-manager}"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/$WALLPAPER_MANAGER_ID"

# Local cache of the versioned dataset. It must live OUTSIDE the plugin
# directory: the shell watches ~/.config/omarchy/plugins/ and hot-reloads a
# plugin whenever a file under it changes, so caching the datasets inside the
# plugin closed the overlay every time a catalog was fetched. Tagged with the
# base URL in `.base`, so changing `base` wipes and re-downloads.
# `paths.datasets` is relative to the cache base; an absolute value is honoured
# as-is.
if [[ $DATASETS_REL = /* ]]; then
  DATASETS_DIR="$DATASETS_REL"
else
  DATASETS_DIR="$CACHE_BASE/$DATASETS_REL"
fi
DATASETS_JSON="$DATASETS_DIR/datasets.json"
DATASETS_BASE_FILE="$DATASETS_DIR/.base"

# Concurrent downloads for install / random-install, set by the UI
# (Setup → Download → Parallel downloads). Clamped to 1-12, default 8.
PARALLEL_DOWNLOADS="${WALLPAPER_MANAGER_PARALLEL:-8}"
[[ $PARALLEL_DOWNLOADS =~ ^[0-9]+$ ]] || PARALLEL_DOWNLOADS=8
PARALLEL_DOWNLOADS=$(( PARALLEL_DOWNLOADS < 1 ? 1 : PARALLEL_DOWNLOADS > 12 ? 12 : PARALLEL_DOWNLOADS ))

# Cap on locally installed wallpaper files, enforced only by the bulk "install
# all" (no selectors). Set by the UI (Setup → Download → Max local files).
# Clamped to 1000-5000, default 2500.
MAX_LOCAL_FILES="${WALLPAPER_MANAGER_MAX_FILES:-2500}"
[[ $MAX_LOCAL_FILES =~ ^[0-9]+$ ]] || MAX_LOCAL_FILES=2500
MAX_LOCAL_FILES=$(( MAX_LOCAL_FILES < 1000 ? 1000 : MAX_LOCAL_FILES > 5000 ? 5000 : MAX_LOCAL_FILES ))

# Cap on the disk space used by installed wallpapers (Setup → Download → Max
# disk size). Counts only the local wallpaper files, not the disposable image
# cache. Clamped to 1-50 GB, default 3.
MAX_DISK_GB="${WALLPAPER_MANAGER_MAX_DISK_GB:-3}"
[[ $MAX_DISK_GB =~ ^[0-9]+$ ]] || MAX_DISK_GB=3
MAX_DISK_GB=$(( MAX_DISK_GB < 1 ? 1 : MAX_DISK_GB > 50 ? 50 : MAX_DISK_GB ))
MAX_DISK_BYTES=$(( MAX_DISK_GB * 1024 * 1024 * 1024 ))

DEST_BASE="$HOME/.config/omarchy/backgrounds"
STATE_BG="$HOME/.local/state/omarchy/current/background"
CONFIG_BG="$HOME/.config/omarchy/current/background"

usage() {
  cat >&2 <<EOF
Usage: $0 <command> [args...]
Commands:
  themes                            List themes as TSV (name,title,url,collections,count,preview,installed,palette,description,image,present)
  limits                            Current local usage as TSV (files, bytes)
  catalog <theme> <catalog-url>     Wallpapers of a theme as TSV
  install <theme> [selector...]     Install all wallpapers, or every one matching a selector
  random-install <theme> [count]    Install <count> (default 5) random wallpapers
  remove <theme> [selector...]      Remove all wallpapers, or every one matching a selector
  set-default <theme> <filename> <url>  Download if needed + set as current background
  unset-default <theme> <filename>  Clear it as background, back to the theme default
  random-default <theme>            Set a random wallpaper of the theme as current background
  rotate [--all] [--random]         Set the next wallpaper of the current theme (--all: include theme backgrounds)
  image <url>                       Print the local cache path of an image, downloading it if missing
  prewarm <url>...                  Warm the image cache in the background (best-effort)
  download <url> <dest-dir>         Copy the original wallpaper into a folder, print the saved path
Source: $BASE
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

# Local path of a remote image, downloading it once. The cache key is the URL,
# which already carries the versioned base, so changing `base` invalidates the
# cache on its own. Prints the path on success, nothing on failure (the UI
# then falls back to the remote URL). `flock` keeps concurrent callers (detail
# + prefetch) from downloading the same image twice.
cmd_image() {
  local url="$1" key ext dest
  [[ -n $url ]] || return 1
  key="$(printf '%s' "$url" | md5sum | cut -d' ' -f 1)"
  ext="${url%%\?*}"
  ext="${ext##*.}"
  case "$ext" in
    webp | jpg | jpeg | png | gif | bmp | avif) ;;
    *) ext="img" ;;
  esac
  dest="$CACHE_BASE/$key.$ext"

  if [[ -s $dest ]]; then
    printf '%s\n' "$dest"
    return 0
  fi
  mkdir -p "$CACHE_BASE"
  (
    local tmp ok=1
    flock -w 60 9 || exit 1
    if [[ -s $dest ]]; then
      printf '%s\n' "$dest"
      exit 0
    fi
    tmp="$(mktemp "$CACHE_BASE/.tmp.XXXXXX")"
    if fetch "$url" -o "$tmp"; then
      mv -f -- "$tmp" "$dest"
      ok=0
    fi
    if [[ $ok -eq 0 ]]; then
      printf '%s\n' "$dest"
    else
      rm -f -- "$tmp"
    fi
    exit "$ok"
  ) 9>"$dest.lock"
}

# Best-effort parallel warm-up of the image cache. Prints one
# `url<TAB>local-path` line per image that is (or becomes) cached, so the UI can
# use the local file for the neighbours instead of re-fetching the remote URL.
cmd_prewarm() {
  (( $# > 0 )) || return 0
  local url
  for url in "$@"; do
    (
      local path
      path="$(cmd_image "$url" 2>/dev/null)" || exit 0
      [[ -n $path ]] && printf '%s\t%s\n' "$url" "$path"
    ) &
    while (( $(jobs -rp | wc -l) >= PARALLEL_DOWNLOADS )); do
      wait -n || true
    done
  done
  wait || true
}

# Copy the original wallpaper into a folder, keeping its file name and adding a
# numeric suffix instead of overwriting. Prints the saved path.
cmd_download() {
  local url="$1" dest_dir="$2"
  [[ -n $url && -n $dest_dir && -d $dest_dir ]] || return 1
  local src name base ext dest i=1
  src="$(cmd_image "$url" 2>/dev/null)" || return 1
  [[ -s $src ]] || return 1
  name="${url%%\?*}"
  name="${name##*/}"
  [[ -n $name ]] || name="wallpaper"
  base="${name%.*}"
  ext="${name##*.}"
  [[ "$base" == "$name" ]] && ext=""
  if [[ -n $ext ]]; then
    dest="$dest_dir/$name"
    while [[ -e $dest ]]; do
      dest="$dest_dir/$base-$i.$ext"
      i=$((i + 1))
    done
  else
    dest="$dest_dir/$name"
    while [[ -e $dest ]]; do
      dest="$dest_dir/$base-$i"
      i=$((i + 1))
    done
  fi
  cp -f -- "$src" "$dest" || return 1
  printf '%s\n' "$dest"
}

# Drop the cached dataset but keep the tracked `.gitkeep`.
invalidate_datasets() {
  [[ -d $DATASETS_DIR ]] || return 0
  find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf -- {} +
}

# Warm every theme catalog once datasets.json is in place. Best effort: a
# failure here does not fail the caller, `ensure_catalog()` retries on demand.
prefetch_catalogs() {
  local theme remote path dest
  while IFS=$'\t' read -r theme remote path; do
    [[ -n $theme ]] || continue
    dest="$DATASETS_DIR/$theme/catalog.json"
    [[ -s $dest ]] && continue
    [[ -n $remote ]] || remote="$BASE/${path#/}"
    download_file "$remote" "$dest" || echo "Warning: could not cache catalog '$theme'." >&2
  done < <(jq -r '
    .themes | to_entries[]
    | select(.value.kind == "theme")
    | [.key, (.value.catalog.url // ""), (.value.catalog.path // "")] | @tsv
  ' "$DATASETS_JSON")
  return 0
}

# Ensure the dataset for the configured base is cached. The first run downloads
# `datasets.json` and then warms every catalog; later runs reuse the cache until
# the `.base` marker no longer matches.
ensure_datasets() {
  if [[ -s $DATASETS_JSON && -f $DATASETS_BASE_FILE ]] \
    && [[ "$(cat -- "$DATASETS_BASE_FILE" 2>/dev/null || true)" == "$BASE" ]]; then
    return 0
  fi
  mkdir -p "$DATASETS_DIR"
  invalidate_datasets
  download_file "$DATASETS_URL" "$DATASETS_JSON" || return 1
  printf '%s\n' "$BASE" >"$DATASETS_BASE_FILE"
  prefetch_catalogs
}

# Ensure the catalog of one theme is cached. Normally the eager first-run
# prefetch already did it; this is the on-demand fallback.
ensure_catalog() {
  local theme="$1" remote dest
  ensure_datasets || return 1
  dest="$DATASETS_DIR/$theme/catalog.json"
  [[ -s $dest ]] && return 0
  remote="$(jq -r --arg t "$theme" '.themes[$t].catalog.url // empty' "$DATASETS_JSON" 2>/dev/null || true)"
  [[ -n $remote ]] || remote="$BASE/datasets/$theme/catalog.json"
  download_file "$remote" "$dest"
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
# Uses bash's `${v,,}` instead of `printf | tr`: the catalogs have hundreds of
# rows and a subshell per field made install/remove spin for seconds.
wallpaper_matches() {
  local term="$1" id="$2" name="$3" code="$4" filename="$5"
  local needle="${term,,}" field
  for field in "$id" "$name" "$code" "$filename"; do
    [[ "${field,,}" == "$needle" ]] && return 0
  done
  [[ "${name,,}" == *"$needle"* ]] && return 0
  return 1
}

# Selectors of the current install/remove call, set from the extra arguments
# (the QML passes one exact filename per checked wallpaper). An empty array
# means "the whole theme".
SELECTORS=()
matches_any_selector() {
  local id="$1" name="$2" code="$3" filename="$4" s
  if (( ${#SELECTORS[@]} == 0 )); then return 0; fi
  for s in "${SELECTORS[@]}"; do
    wallpaper_matches "$s" "$id" "$name" "$code" "$filename" && return 0
  done
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

# Extensions a wallpaper file may carry. The collection is JSON-driven, so a
# wrong (or malicious) entry must not drop a non-image into the backgrounds
# folder; the sha256 still pins the content downstream.
ALLOWED_IMAGE_EXTS=(webp jpg jpeg png)

is_allowed_image() {
  local name="${1##*/}" ext
  ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')"
  local allowed
  for allowed in "${ALLOWED_IMAGE_EXTS[@]}"; do
    [[ $ext == "$allowed" ]] && return 0
  done
  return 1
}

# Download one wallpaper unless the destination already matches its sha256.
download_one() {
  local url="$1" dest="$2" sha="$3"
  if ! is_allowed_image "$dest"; then
    echo "Refusing '$(basename "$dest")': not an allowed image (webp/jpg/jpeg/png)." >&2
    return 1
  fi
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

# Machine-readable progress on stdout, consumed by the QML footer bar:
#   PROGRESS <theme> <installed-on-disk> <operation-total>
# `installed-on-disk` is the definitive count (same metric as `cmd_themes`), so
# the bar is correct even for partial themes and random installs. `.tmp` files
# from in-flight downloads are excluded.
emit_progress() {
  local theme="$1" total="$2" n
  n="$(find "$DEST_BASE/$theme" -maxdepth 1 -type f ! -name '*.tmp' 2>/dev/null | wc -l)" || true
  n="${n//[[:space:]]/}"
  printf 'PROGRESS\t%s\t%s\t%s\n' "$theme" "${n:-0}" "$total"
}

cmd_themes() {
  ensure_datasets || {
    echo "Failed to fetch datasets." >&2
    return 1
  }
  local name title catalog collections count preview palette description image installed present
  # Read the jq row with a non-whitespace separator: `IFS=$'\t'` collapses
  # runs of tabs, so the empty palette field would shift the description in.
  while IFS=$'\x1f' read -r name title catalog collections count preview palette description image; do
    [[ -n $name ]] || continue
    installed=0
    if [[ -d "$DEST_BASE/$name" ]]; then
      installed="$(find "$DEST_BASE/$name" -maxdepth 1 -type f ! -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')"
    fi
    # "present" = the Omarchy theme itself exists locally; install/remove of
    # its wallpapers only makes sense when it does.
    present=0
    if theme_installed_in_omarchy "$name"; then present=1; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$title" "$catalog" "$collections" "$count" \
      "$preview" "$installed" "$palette" "$description" \
      "$image" "$present"
  done < <(jq -r '
    .themes | to_entries[]
    | select(.value.kind == "theme")
    | [.key, (.value.title // .key), (.value.catalog.url // ""), (.value.collections | length), (.value.count // 0), (.value.preview // ""), ((.value.palette // []) | join(",")), (.value.description // ""), (.value.image // "")]
    | map(tostring) | join("\u001f")
  ' "$DATASETS_JSON")
}

cmd_catalog() {
  local theme="$1"
  ensure_catalog "$theme" || {
    echo "Failed to fetch catalog for '$theme'." >&2
    return 1
  }
  local filename name code url sha256 preview size collection resolution width height path current installed
  while IFS=$'\t' read -r filename name code url sha256 preview size collection resolution width height; do
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$filename" "$name" "$code" "$url" "$sha256" "$installed" "$current" "$preview" "$size" "$collection" "$resolution" "$width" "$height"
  done < <(jq -r '.wallpapers[] | [.filename, .name, .code, .url, .sha256, (.preview // ""), (.size_bytes // 0), (.collection // ""), (.resolution // ""), (.width // 0), (.height // 0)] | @tsv' \
    "$DATASETS_DIR/$theme/catalog.json")
}

# Total wallpaper files currently installed across every theme.
count_local_files() {
  find "$DEST_BASE" -mindepth 2 -maxdepth 2 -type f ! -name '*.tmp' 2>/dev/null | wc -l | tr -d ' '
}

# Total bytes used by the installed wallpaper files (excluding in-flight .tmp).
count_local_bytes() {
  find "$DEST_BASE" -mindepth 2 -maxdepth 2 -type f ! -name '*.tmp' -printf '%s\n' 2>/dev/null \
    | awk '{s+=$1} END {print s+0}'
}

# Current local usage, so the UI can flag that the caps are reached. The caps
# themselves travel back through the env, so this only reports what is on disk.
cmd_limits() {
  printf 'LIMITS\t%s\t%s\n' "$(count_local_files)" "$(count_local_bytes)"
}

cmd_install() {
  local theme="$1"
  shift
  SELECTORS=("$@")
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
  local filename id name code url sha size
  # The caps apply only to the bulk "install all" (no selectors): manual
  # single/multi selections are always honoured, since the user is choosing
  # them explicitly. Already-installed files do not consume budget.
  local cap_active=0 remaining=0 bytes_remaining=0 skipped=0
  if (( ${#SELECTORS[@]} == 0 )); then
    cap_active=1
    remaining=$(( MAX_LOCAL_FILES - $(count_local_files) ))
    (( remaining < 0 )) && remaining=0
    bytes_remaining=$(( MAX_DISK_BYTES - $(count_local_bytes) ))
    (( bytes_remaining < 0 )) && bytes_remaining=0
  fi
  while IFS=$'\t' read -r filename id name code url sha size; do
    if matches_any_selector "$id" "$name" "$code" "$filename"; then
      if ! is_allowed_image "$filename"; then
        echo "Skipping '$filename': not an allowed image (webp/jpg/jpeg/png)." >&2
        continue
      fi
      if (( cap_active )) && [[ ! -f "$DEST_BASE/$theme/$filename" ]]; then
        if (( remaining <= 0 || size > bytes_remaining )); then
          skipped=$((skipped + 1))
          continue
        fi
        remaining=$((remaining - 1))
        bytes_remaining=$((bytes_remaining - size))
      fi
      sel_url+=("$url")
      sel_dest+=("$DEST_BASE/$theme/$filename")
      sel_sha+=("$sha")
    fi
  done < <(jq -r '.wallpapers[] | [.filename, .id, .name, .code, .url, .sha256, (.size_bytes // 0)] | @tsv' <<<"$catalog")

  if (( skipped > 0 )); then
    echo "Local file limit reached ($MAX_LOCAL_FILES): skipped $skipped wallpaper(s)." >&2
  fi

  if (( ${#sel_url[@]} == 0 )); then
    if (( cap_active )); then
      echo "Local file limit reached ($MAX_LOCAL_FILES): nothing new to install." >&2
      return 0
    fi
    echo "No wallpaper matching the selection in theme '$theme'." >&2
    return 1
  fi

  mkdir -p "$DEST_BASE/$theme"
  local fail_file i total=${#sel_url[@]}
  fail_file="$(mktemp)"
  emit_progress "$theme" "$total"
  for i in "${!sel_url[@]}"; do
    download_one "${sel_url[$i]}" "${sel_dest[$i]}" "${sel_sha[$i]}" 2>>"$fail_file" &
    while (( $(jobs -rp | wc -l) >= PARALLEL_DOWNLOADS )); do
      wait -n || true
      emit_progress "$theme" "$total"
    done
  done
  while (( $(jobs -rp | wc -l) > 0 )); do
    wait -n || true
    emit_progress "$theme" "$total"
  done

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
  local theme="$1"
  shift
  SELECTORS=("$@")
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
    if matches_any_selector "$id" "$name" "$code" "$filename"; then
      to_remove["$filename"]=1
    fi
  done < <(jq -r '.wallpapers[] | [.filename, .id, .name, .code] | @tsv' <<<"$catalog")

  local f base removed=0 total
  total="$(find "$dest" -maxdepth 1 -type f ! -name '*.tmp' 2>/dev/null | wc -l)" || true
  total="${total//[[:space:]]/}"
  for f in "$dest"/*; do
    [[ -f $f ]] || continue
    base="$(basename -- "$f")"
    if [[ ${to_remove["$base"]+set} ]]; then
      rm -f -- "$f"
      removed=$((removed + 1))
      emit_progress "$theme" "${total:-0}"
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
  if ! is_allowed_image "$filename"; then
    echo "Refusing '$filename': not an allowed image (webp/jpg/jpeg/png)." >&2
    return 1
  fi
  local path="$DEST_BASE/$theme/$filename"
  if [[ ! -f $path ]]; then
    mkdir -p "$DEST_BASE/$theme"
    fetch "$url" -o "$path"
  fi
  omarchy-theme-bg-set "$path"
}

# Toggle a wallpaper off the default: only when it currently is the background,
# fall back to the theme's own default background (like a dangling link would).
cmd_unset_default() {
  local theme="$1" filename="$2"
  local path="$DEST_BASE/$theme/$filename"
  [[ "$(readlink -f "$STATE_BG" 2>/dev/null)" == "$path" ]] || return 0
  local f fallback="" dir
  for dir in \
    "$HOME/.local/state/omarchy/current/theme/backgrounds" \
    "$HOME/.config/omarchy/current/theme/backgrounds"; do
    for f in "$dir"/*; do
      [[ -f $f ]] && { fallback="$f"; break; }
    done
    [[ -n $fallback ]] && break
  done
  [[ -n $fallback ]] || return 1
  omarchy-theme-bg-set "$fallback" >/dev/null 2>&1 || true
}

# Pick a random wallpaper of a theme (no selector) and set it as the current
# background, downloading it first if needed.
cmd_random_default() {
  local theme="$1"
  ensure_catalog "$theme" || {
    echo "Failed to fetch catalog for '$theme'." >&2
    return 1
  }
  local catalog total index filename url
  catalog="$DATASETS_DIR/$theme/catalog.json"
  total="$(jq -r '.wallpapers | length' "$catalog")"
  if (( total == 0 )); then
    echo "No wallpapers for theme '$theme'." >&2
    return 1
  fi
  index=$(( RANDOM % total ))
  IFS=$'\t' read -r filename url < <(
    jq -r --argjson i "$index" '.wallpapers[$i] | [.filename, .url] | @tsv' "$catalog"
  )
  cmd_set_default "$theme" "$filename" "$url"
}

# Install a random selection of a theme's wallpapers (default 5). Used by the
# "Random install (5)" button on the themes detail pane.
cmd_random_install() {
  local theme="$1" count="${2:-5}"
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
  local catalog total
  catalog="$DATASETS_DIR/$theme/catalog.json"
  total="$(jq -r '.wallpapers | length' "$catalog")"
  if (( total == 0 )); then
    echo "No wallpapers for theme '$theme'." >&2
    return 1
  fi
  if (( count > total )); then count=$total; fi
  if (( count < 1 )); then count=1; fi

  # Shuffle is a bulk action, so it honours both caps too (only the manual
  # install via `cmd_install` selectors stays free).
  local remaining=$(( MAX_LOCAL_FILES - $(count_local_files) ))
  (( remaining < 0 )) && remaining=0
  local bytes_remaining=$(( MAX_DISK_BYTES - $(count_local_bytes) ))
  (( bytes_remaining < 0 )) && bytes_remaining=0
  if (( remaining == 0 || bytes_remaining == 0 )); then
    echo "Local limits reached: nothing new to install." >&2
    return 0
  fi
  if (( count > remaining )); then count=$remaining; fi

  local -a sel_url=() sel_dest=() sel_sha=()
  local filename url sha size dest accepted=0
  while IFS=$'\t' read -r filename url sha size; do
    if (( accepted >= count )); then break; fi
    dest="$DEST_BASE/$theme/$filename"
    if [[ -f $dest ]]; then
      : # already installed: no budget cost
    elif (( size > bytes_remaining )); then
      continue
    else
      bytes_remaining=$((bytes_remaining - size))
    fi
    sel_url+=("$url")
    sel_dest+=("$dest")
    sel_sha+=("$sha")
    accepted=$((accepted + 1))
  done < <(jq -r '.wallpapers[] | [.filename, .url, .sha256, (.size_bytes // 0)] | @tsv' "$catalog" | shuf)

  mkdir -p "$DEST_BASE/$theme"
  local fail_file i total=${#sel_url[@]}
  fail_file="$(mktemp)"
  emit_progress "$theme" "$total"
  for i in "${!sel_url[@]}"; do
    download_one "${sel_url[$i]}" "${sel_dest[$i]}" "${sel_sha[$i]}" 2>>"$fail_file" &
    while (( $(jobs -rp | wc -l) >= PARALLEL_DOWNLOADS )); do
      wait -n || true
      emit_progress "$theme" "$total"
    done
  done
  while (( $(jobs -rp | wc -l) > 0 )); do
    wait -n || true
    emit_progress "$theme" "$total"
  done

  refresh_bg_cache
  if [[ -s $fail_file ]]; then
    cat "$fail_file" >&2
    rm -f -- "$fail_file"
    return 1
  fi
  rm -f -- "$fail_file"
  echo "Installed ${#sel_url[@]} random wallpaper(s) in $DEST_BASE/$theme."
}

# Automatic rotation: pick the next wallpaper of the CURRENT Omarchy theme and
# set it as the background. Only files already on disk are used, so no network
# is needed once the pool is installed.
#   default   the plugin's installs for the theme (narrowed to the collection's
#             catalog when it is available)
#   --all     every background of the theme (plugin + theme-bundled)
#   --random  pick at random instead of the next in name order
# Prints `ROTATE<TAB><path>` on success.
cmd_rotate() {
  local pool="plugin" random=0 arg
  for arg in "$@"; do
    case "$arg" in
      --all) pool="all" ;;
      --random) random=1 ;;
    esac
  done

  local theme
  theme="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
  if [[ -z $theme ]]; then
    echo "No current Omarchy theme." >&2
    return 1
  fi

  local f base
  local -a plugin_files=()
  if [[ -d "$DEST_BASE/$theme" ]]; then
    while IFS= read -r -d '' f; do
      base="$(basename -- "$f")"
      [[ $base == *.tmp ]] && continue
      is_allowed_image "$f" && plugin_files+=("$f")
    done < <(find -L "$DEST_BASE/$theme" -maxdepth 1 -type f -print0 2>/dev/null)
  fi

  # "Plugin wallpapers only" means the collection's files this plugin installed:
  # narrow the install dir to the catalog's filenames when the catalog is cached
  # (or can be fetched). Personal files dropped in the folder stay out of the
  # pool; if the catalog is unavailable the whole folder is used.
  if (( ${#plugin_files[@]} > 0 )); then
    local catalog="$DATASETS_DIR/$theme/catalog.json"
    ensure_catalog "$theme" >/dev/null 2>&1 || true
    if [[ -s $catalog ]]; then
      local -A known=()
      while IFS= read -r f; do
        [[ -n $f ]] && known["$DEST_BASE/$theme/$f"]=1
      done < <(jq -r '.wallpapers[].filename' "$catalog" 2>/dev/null || true)
      if (( ${#known[@]} > 0 )); then
        local -a narrowed=() cand
        for cand in "${plugin_files[@]}"; do
          [[ ${known["$cand"]+set} ]] && narrowed+=("$cand")
        done
        if (( ${#narrowed[@]} > 0 )); then plugin_files=("${narrowed[@]}"); fi
      fi
    fi
  fi

  local -a candidates=("${plugin_files[@]}")
  if [[ $pool == "all" ]]; then
    local dir
    for dir in \
      "$HOME/.local/state/omarchy/current/theme/backgrounds" \
      "$HOME/.config/omarchy/current/theme/backgrounds"; do
      [[ -d $dir ]] || continue
      while IFS= read -r -d '' f; do
        base="$(basename -- "$f")"
        [[ $base == *.tmp ]] && continue
        is_allowed_image "$f" && candidates+=("$f")
      done < <(find -L "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
    done
  fi

  # Stable, locale-independent order (same as omarchy-theme-bg-next).
  local -a sorted=()
  while IFS= read -r f; do
    [[ -n $f ]] && sorted+=("$f")
  done < <(printf '%s\n' "${candidates[@]}" 2>/dev/null | LC_ALL=C sort)
  local total=${#sorted[@]}
  if (( total == 0 )); then
    echo "No local wallpaper to rotate through for theme '$theme'." >&2
    return 0
  fi

  local current choice=""
  current="$(readlink -f "$STATE_BG" 2>/dev/null || true)"
  if (( random )); then
    if (( total > 1 )) && [[ -n $current ]]; then
      local -a no_current=()
      for f in "${sorted[@]}"; do [[ $f == "$current" ]] || no_current+=("$f"); done
      if (( ${#no_current[@]} > 0 )); then sorted=("${no_current[@]}"); total=${#sorted[@]}; fi
    fi
    choice="${sorted[$(( RANDOM % total ))]}"
  else
    local index=-1 i
    for i in "${!sorted[@]}"; do
      if [[ ${sorted[$i]} == "$current" ]]; then index=$i; break; fi
    done
    if (( index < 0 )); then
      choice="${sorted[0]}"
    else
      choice="${sorted[$(( (index + 1) % total ))]}"
    fi
  fi

  printf 'ROTATE\t%s\n' "$choice"
  omarchy-theme-bg-set "$choice" >/dev/null 2>&1 || {
    echo "Failed to set background: $choice" >&2
    return 1
  }
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  themes) cmd_themes ;;
  limits) cmd_limits ;;
  catalog) cmd_catalog "$@" ;;
  install) cmd_install "$@" ;;
  random-install) cmd_random_install "$@" ;;
  remove) cmd_remove "$@" ;;
  set-default) cmd_set_default "$@" ;;
  unset-default) cmd_unset_default "$@" ;;
  random-default) cmd_random_default "$@" ;;
  rotate) cmd_rotate "$@" ;;
  image) cmd_image "$@" ;;
  prewarm) cmd_prewarm "$@" ;;
  download) cmd_download "$@" ;;
  *) usage; exit 1 ;;
esac
