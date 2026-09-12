// Pure logic for the wallpaper manager: TSV parsing, labels, cursor arithmetic
// and status text. No QML ids or state live here — the view owns the models,
// the processes and `selectedIndex`, and calls into these functions.
//
// QML side: `import "Model.js" as Model`.

// --- TSV parsers -----------------------------------------------------------

// `manager.sh themes` → array of theme rows.
function parseThemes(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 6)
      out.push({
        name: parts[0],
        title: parts[1],
        catalogUrl: parts[2],
        collections: parseInt(parts[3], 10),
        count: parseInt(parts[4], 10),
        preview: parts[5]
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
