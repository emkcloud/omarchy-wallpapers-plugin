// Pure logic for the wallpaper manager: TSV parsing, labels, cursor arithmetic
// and status text. No QML ids or state live here — the view owns the models,
// the processes and `selectedIndex`, and calls into these functions.
//
// QML side: `import "js/Model.js" as Model`.

// --- TSV parsers -----------------------------------------------------------

// `manager.sh themes` → array of theme rows.
function parseThemes(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (!line.trim()) continue
    var parts = line.split("\t")
    if (parts.length >= 6)
      out.push({
        name: parts[0],
        title: parts[1],
        catalogUrl: parts[2],
        collections: parseInt(parts[3], 10),
        count: parseInt(parts[4], 10),
        preview: parts[5],
        installed: parts.length > 6 ? parseInt(parts[6], 10) : 0,
        palette: parts.length > 7 ? parts[7] : "",
        description: parts.length > 8 ? parts[8] : "",
        image: parts.length > 9 ? parts[9] : "",
        themePresent: parts.length > 10 ? parts[10] : "1"
      })
  }
  return out
}

// `manager.sh catalog` → array of wallpaper rows.
function parseCatalog(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 10)
      out.push({
        filename: parts[0],
        name: parts[1],
        code: parts[2],
        url: parts[3],
        sha256: parts[4],
        installed: parts[5],
        isDefault: parts[6],
        preview: parts[7],
        sizeBytes: parseInt(parts[8], 10) || 0,
        collection: parts[9],
        resolution: parts.length > 10 ? parts[10] : "",
        width: parts.length > 11 ? parseInt(parts[11], 10) || 0 : 0,
        height: parts.length > 12 ? parseInt(parts[12], 10) || 0 : 0
      })
  }
  return out
}

// --- labels ----------------------------------------------------------------

// The dataset carries a readable `title` ("Tokyo Night"); tiles show it
// uppercased. Fallback for older datasets: normalize the slug.
function themeLabel(item) {
  var label = item && item.title ? item.title : (item ? item.name : "")
  return String(label).replace(/[-_]+/g, " ").toUpperCase()
}

// Slug used to compare a dataset theme name with the active Omarchy theme:
// case-insensitive, separators removed, so `osaka-jade`, `Osaka Jade` and
// `osaka_jade` all collapse to the same key.
function normalizeSlug(value) {
  return String(value || "").toLowerCase().replace(/[-_\s]+/g, "")
}

// First letter upper-case, rest untouched ("catppuccin" -> "Catppuccin").
function ucfirst(value) {
  var text = String(value || "")
  if (!text) return ""
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// Case-insensitive substring match of a search query against the theme name
// and title. Hyphens/underscores are treated as spaces on both sides, so
// "tokyo night" matches the `tokyo-night` slug.
function themeMatches(item, query) {
  var q = String(query || "").trim().toLowerCase().replace(/[-_]+/g, " ")
  if (!q) return true
  if (!item) return false
  var label = themeLabel(item).toLowerCase()
  var name = String(item.name || "").replace(/[-_]+/g, " ").toLowerCase()
  return label.indexOf(q) !== -1 || name.indexOf(q) !== -1
}

// Progress caption: whole percent, floored so 249/250 reads 99% (not 100%).
// Below 1% a whole number would round the progress away, so one decimal is
// shown instead ("0.8%"); below 0.1% the caption at least says "<0.1%".
function formatPercent(ratio) {
  var pct = Math.max(0, Math.min(1, Number(ratio) || 0)) * 100
  if (pct <= 0) return "0%"
  if (pct >= 1) return Math.floor(pct) + "%"
  if (pct < 0.1) return "<0.1%"
  return pct.toFixed(1) + "%"
}

// Human file size in MB with one decimal ("1.8 MB"); empty when unknown.
function formatSize(bytes) {
  var n = Number(bytes) || 0
  if (n <= 0) return ""
  return (n / 1048576).toFixed(1) + " MB"
}

// Case-insensitive substring match of a search query against a wallpaper's
// name or country code (both shown on the tile).
function wallpaperMatches(item, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  if (!item) return false
  return String(item.name || "").toLowerCase().indexOf(q) !== -1
    || String(item.code || "").toLowerCase().indexOf(q) !== -1
}

// --- theme state -----------------------------------------------------------

// "installed" when every catalog entry is present on disk, "partial" when only
// some are, "available" when none is.
function themeState(item) {
  if (!item) return "available"
  var total = item.count || 0
  var got = item.installed || 0
  if (total > 0 && got >= total) return "installed"
  if (got > 0) return "partial"
  return "available"
}

// Short caption under the theme name: "250 · installed" / "12/250 installed".
function themeStatusLabel(item) {
  if (!item) return ""
  var state = themeState(item)
  if (state === "partial") return item.installed + "/" + item.count + " installed"
  return String(item.count || 0) + " · " + (state === "installed" ? "installed" : "available")
}

// Dataset `palette` is a comma-separated hex list; split it for the swatches.
function paletteList(item) {
  if (!item || !item.palette) return []
  return String(item.palette).split(",").map(function(s) {
    return s.trim()
  }).filter(function(s) {
    return s.length > 0
  })
}

// --- cursor arithmetic -----------------------------------------------------

// Clamp a cursor move to the model bounds; `step` may be ±1, a whole row or a
// whole page. Also repairs a non-finite index (Nan/undefined).
function stepIndex(index, step, count) {
  if (count <= 0) return 0
  if (!isFinite(index)) index = 0
  return Math.max(0, Math.min(count - 1, index + step))
}

// --- keyboard --------------------------------------------------------------

// Map a `textKey` to a semantic action handled by the panel.
function textAction(text) {
  if (text === "d" || text === "D") return "default"
  if (text === "r" || text === "R") return "refresh"
  if (text === "i" || text === "I") return "install"
  if (text === "u" || text === "U") return "uninstall"
  return ""
}

// Themes-list shortcuts, alphabetical: A add remote source (placeholder),
// B browse, C custom install (placeholder), I install, R random install,
// U uninstall.
function themeTextAction(text) {
  switch (String(text).toLowerCase()) {
    case "a": return "add"
    case "b": return "browse"
    case "c": return "custom"
    case "i": return "install"
    case "r": return "random"
    case "u": return "uninstall"
  }
  return ""
}

// --- status text -----------------------------------------------------------

function themesStatus(count) {
  return count + (count === 1 ? " theme available" : " themes available")
}

function catalogStatus(count, theme) {
  return count + (count === 1 ? " wallpaper in " : " wallpapers in ") + theme
}

// --- config ----------------------------------------------------------------

// Merge the `paths` block of config.json over the shipped defaults.
function parsePaths(raw, fallback) {
  var base = fallback || {}
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.paths) return base
    return {
      scripts: cfg.paths.scripts || base.scripts,
      assets: cfg.paths.assets || base.assets,
      logo: cfg.paths.logo || base.logo
    }
  } catch (e) {
    return base
  }
}
