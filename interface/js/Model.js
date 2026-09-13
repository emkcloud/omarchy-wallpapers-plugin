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
    if (parts.length >= 8)
      out.push({
        filename: parts[0],
        name: parts[1],
        code: parts[2],
        url: parts[3],
        sha256: parts[4],
        installed: parts[5],
        isDefault: parts[6],
        preview: parts[7]
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
