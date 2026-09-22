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
  var label = item ? (item.title || item.name || "") : ""
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

// Upper-case the first letter of every word, leaving the rest untouched, so
// mixed datasets read consistently ("001 the old windmill" -> "001 The Old
// Windmill", "South Africa" and "USA" unchanged). Numeric prefixes stay as-is.
function titleCase(value) {
  var text = String(value || "")
  var out = ""
  var atWordStart = true
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (atWordStart && ch >= "a" && ch <= "z") {
      out += ch.toUpperCase()
      atWordStart = false
    } else {
      out += ch
      if (!/\s/.test(ch)) atWordStart = false
    }
    if (/\s/.test(ch)) atWordStart = true
  }
  return out
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

// Shorten `value` to at most `max` characters with a middle ellipsis, keeping
// the head and the tail (the tail carries the extension and resolution, so it
// must survive). Shorter strings are returned untouched.
function elideMiddle(value, max) {
  var s = String(value || "")
  var n = Number(max) || 0
  if (n < 3 || s.length <= n) return s
  var keep = n - 1
  var head = Math.ceil(keep / 2)
  var tail = keep - head
  return s.substring(0, head) + "…" + (tail > 0 ? s.substring(s.length - tail) : "")
}

// Human file size in MB with one decimal ("1.8 MB"); empty when unknown.
function formatSize(bytes) {
  var n = Number(bytes) || 0
  if (n <= 0) return ""
  return (n / 1048576).toFixed(1) + " MB"
}

// Case-insensitive substring match of a search query against a wallpaper's
// name or country code (both shown on the tile). `collection`, when set,
// narrows to a single collection first (exact match, `""` = every collection).
function wallpaperMatches(item, query, collection) {
  var col = String(collection || "")
  if (col && String((item && item.collection) || "") !== col) return false
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  if (!item) return false
  return String(item.name || "").toLowerCase().indexOf(q) !== -1
    || String(item.code || "").toLowerCase().indexOf(q) !== -1
}

// Unique collection names present in a wallpaper list, sorted, as Dropdown
// options: the "All collections" entry (value "") comes first, then every
// collection found. Rows without a collection are ignored.
function collectionOptions(items) {
  var seen = {}
  var names = []
  for (var i = 0; i < (items ? items.length : 0); i++) {
    var c = String((items[i] && items[i].collection) || "")
    if (!c || seen[c]) continue
    seen[c] = true
    names.push(c)
  }
  names.sort()
  var out = [{ value: "", label: "All collections" }]
  for (var j = 0; j < names.length; j++)
    out.push({ value: names[j], label: ucfirst(names[j]) })
  return out
}

// Most frequent non-empty resolution in a list ("2K" wins over a single "4K").
// Empty when no row carries one.
function dominantResolution(counts) {
  var best = ""
  var bestN = 0
  for (var key in counts) {
    if (counts[key] > bestN) {
      bestN = counts[key]
      best = key
    }
  }
  return best
}

// Whole-list totals for the "Full collection" card: wallpaper count, how many
// are installed, the total size in bytes and the dominant resolution.
function wallpaperTotals(items) {
  var out = { count: 0, installed: 0, sizeBytes: 0, resolution: "" }
  var resCount = {}
  for (var i = 0; i < (items ? items.length : 0); i++) {
    var item = items[i]
    if (!item) continue
    out.count++
    if (String(item.installed) === "1") out.installed++
    out.sizeBytes += Number(item.sizeBytes) || 0
    var res = String(item.resolution || "")
    if (res) resCount[res] = (resCount[res] || 0) + 1
  }
  out.resolution = dominantResolution(resCount)
  return out
}

// Aggregate a wallpaper list by collection: one entry per collection present,
// sorted by name, with count / installed / total size and the dominant
// resolution. Rows without a collection are ignored. Used by the custom-install
// screen to build one card per collection.
function collectionSummary(items) {
  var map = {}
  var order = []
  for (var i = 0; i < (items ? items.length : 0); i++) {
    var item = items[i]
    if (!item) continue
    var name = String(item.collection || "")
    if (!name) continue
    var entry = map[name]
    if (!entry) {
      entry = map[name] = { count: 0, installed: 0, sizeBytes: 0, resCount: {} }
      order.push(name)
    }
    entry.count++
    if (String(item.installed) === "1") entry.installed++
    entry.sizeBytes += Number(item.sizeBytes) || 0
    var res = String(item.resolution || "")
    if (res) entry.resCount[res] = (entry.resCount[res] || 0) + 1
  }
  order.sort()
  var out = []
  for (var j = 0; j < order.length; j++) {
    var e = map[order[j]]
    out.push({
      name: order[j],
      label: ucfirst(order[j]),
      count: e.count,
      installed: e.installed,
      sizeBytes: e.sizeBytes,
      resolution: dominantResolution(e.resCount)
    })
  }
  return out
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

// Themes-list shortcuts: A add remote source (placeholder), B browse,
// C custom install (placeholder), F shuffle in 5 random wallpapers, I install
// all, R refresh, U uninstall all, ? help. (Setup is a global shortcut handled
// by the panel, so it is not mapped here.)
function themeTextAction(text) {
  switch (String(text).toLowerCase()) {
    case "a": return "add"
    case "b": return "browse"
    case "c": return "custom"
    case "f": return "shuffle"
    case "i": return "install"
    case "r": return "refresh"
    case "u": return "uninstall"
    case "?": return "help"
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

// --- help ------------------------------------------------------------------
// The Help screen is data-driven: `help/index.json` describes the sidebar and
// the external resources, `help/roadmap.json` the right column, and one
// Markdown file per topic is rendered by HelpView/MarkdownView. These helpers
// validate that data (a malformed file degrades to an empty screen, never a
// crash) and split a Markdown subset into typed blocks.

function emptyHelpIndex() {
  return { sections: [], resources: [], feature: null }
}

function parseHelpIndex(raw) {
  var empty = emptyHelpIndex()
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.sections) return empty
    var sections = []
    for (var i = 0; i < cfg.sections.length; i++) {
      var src = cfg.sections[i]
      if (!src) continue
      var items = []
      var rawItems = src.items || []
      for (var j = 0; j < rawItems.length; j++) {
        var it = rawItems[j]
        if (!it || !it.file) continue
        items.push({
          id: String(it.id || it.file),
          title: String(it.title || it.id || it.file),
          file: String(it.file)
        })
      }
      sections.push({ title: String(src.title || ""), items: items })
    }
    var resources = []
    var rawResources = cfg.resources || []
    for (var k = 0; k < rawResources.length; k++) {
      var res = rawResources[k]
      if (!res) continue
      // `link` is a key into config.links (resolved by the view); `url` is an
      // optional literal fallback.
      if (!res.link && !res.url) continue
      resources.push({
        title: String(res.title || res.link || res.url),
        link: String(res.link || ""),
        url: String(res.url || "")
      })
    }
    var feature = null
    if (cfg.feature && (cfg.feature.link || cfg.feature.url)) {
      feature = {
        title: String(cfg.feature.title || "+ Propose feature"),
        link: String(cfg.feature.link || ""),
        url: String(cfg.feature.url || "")
      }
    }
    return { sections: sections, resources: resources, feature: feature }
  } catch (e) {
    return empty
  }
}

// Flat list of the index items, in sidebar order: the keyboard cursor and the
// "N topics" caption both count these.
function helpFlatItems(index) {
  var out = []
  var sections = index && index.sections ? index.sections : []
  for (var i = 0; i < sections.length; i++) {
    var items = sections[i].items || []
    for (var j = 0; j < items.length; j++) out.push(items[j])
  }
  return out
}

// Sidebar rows: section captions interleaved with items, each item carrying its
// flat cursor index so the view can highlight it without a second lookup.
function helpSidebarEntries(index) {
  var out = []
  var flat = 0
  var sections = index && index.sections ? index.sections : []
  for (var i = 0; i < sections.length; i++) {
    var section = sections[i]
    if (section.title) out.push({ type: "section", title: section.title })
    var items = section.items || []
    for (var j = 0; j < items.length; j++) {
      out.push({
        type: "item",
        id: items[j].id,
        title: items[j].title,
        file: items[j].file,
        flat: flat
      })
      flat++
    }
  }
  return out
}

function parseRoadmap(raw) {
  var empty = { title: "Roadmap", subtitle: "", items: [] }
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.items) return empty
    var items = []
    for (var i = 0; i < cfg.items.length; i++) {
      var it = cfg.items[i]
      if (!it) continue
      // Deliberately minimal: the roadmap is a plain list of upcoming changes,
      // each one just a title and a description.
      items.push({
        title: String(it.title || ""),
        description: String(it.description || "")
      })
    }
    return {
      title: String(cfg.title || "Roadmap"),
      subtitle: String(cfg.subtitle || ""),
      items: items
    }
  } catch (e) {
    return empty
  }
}

// Inline subset of Markdown for Text.StyledText: bold, italic, inline code
// (tinted with `codeColor`) and links. Input is escaped first, so the markup we
// emit is the only markup that survives.
function inlineMarkdown(text, codeColor) {
  var s = String(text || "")
  s = s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  var codes = []
  s = s.replace(/`([^`]+)`/g, function(match, code) {
    codes.push(code)
    return "\u0000" + (codes.length - 1) + "\u0000"
  })
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
  s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
  s = s.replace(/(^|[^*])\*([^*]+)\*/g, "$1<i>$2</i>")
  s = s.replace(/\u0000(\d+)\u0000/g, function(match, index) {
    return '<font color="' + String(codeColor || "#e5c07b") + '">'
      + codes[parseInt(index, 10)] + "</font>"
  })
  return s
}

function splitTableRow(line) {
  var s = String(line)
  if (s.charAt(0) === "|") s = s.slice(1)
  if (s.charAt(s.length - 1) === "|") s = s.slice(0, -1)
  return s.split("|").map(function(cell) {
    return cell.trim()
  })
}

function isTableSeparator(line) {
  return /^\s*\|?\s*:?-{2,}/.test(String(line))
}

// Markdown subset → array of blocks for MarkdownView:
//   { type: "heading", level, text }
//   { type: "paragraph", text }
//   { type: "code", lang, text }
//   { type: "table", headers, rows }
//   { type: "note", text }
//   { type: "list", ordered, items }
//   { type: "rule" }
function parseMarkdown(raw) {
  var lines = String(raw || "").replace(/\r\n?/g, "\n").split("\n")
  var blocks = []
  var i = 0

  function blank(line) { return String(line).trim() === "" }
  function startsBlock(line, next) {
    if (blank(line)) return true
    if (/^\s*```/.test(line)) return true
    if (/^(#{1,6})\s+/.test(line)) return true
    if (/^\s*[-*_](\s*[-*_]){2,}\s*$/.test(line)) return true
    if (/^\s*>\s?/.test(line)) return true
    if (/^\s*([-*+]|\d+\.)\s+/.test(line)) return true
    if (line.indexOf("|") !== -1 && next !== undefined && isTableSeparator(next)) return true
    return false
  }

  while (i < lines.length) {
    var line = lines[i]
    if (blank(line)) {
      i++
      continue
    }

    var fence = line.match(/^\s*```(\w*)\s*$/)
    if (fence) {
      var code = []
      i++
      while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) {
        code.push(lines[i])
        i++
      }
      if (i < lines.length) i++
      blocks.push({ type: "code", lang: fence[1] || "", text: code.join("\n") })
      continue
    }

    var heading = line.match(/^(#{1,6})\s+(.*)$/)
    if (heading) {
      blocks.push({ type: "heading", level: heading[1].length, text: heading[2].trim() })
      i++
      continue
    }

    if (/^\s*[-*_](\s*[-*_]){2,}\s*$/.test(line)) {
      blocks.push({ type: "rule" })
      i++
      continue
    }

    if (line.indexOf("|") !== -1 && isTableSeparator(lines[i + 1])) {
      var headers = splitTableRow(line)
      i += 2
      var rows = []
      while (i < lines.length && lines[i].indexOf("|") !== -1 && !blank(lines[i])) {
        rows.push(splitTableRow(lines[i]))
        i++
      }
      blocks.push({ type: "table", headers: headers, rows: rows })
      continue
    }

    if (/^\s*>\s?/.test(line)) {
      var note = []
      while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
        note.push(lines[i].replace(/^\s*>\s?/, ""))
        i++
      }
      blocks.push({ type: "note", text: note.join(" ").trim() })
      continue
    }

    if (/^\s*([-*+]|\d+\.)\s+/.test(line)) {
      var ordered = /^\s*\d+\./.test(line)
      var items = []
      var baseIndent = -1
      var current = null
      while (i < lines.length) {
        var cur = lines[i]
        if (blank(cur)) break
        var bullet = cur.match(/^(\s*)([-*+]|\d+\.)\s+(.*)$/)
        if (bullet) {
          if (current) items.push(current)
          // Indentation (tabs as two spaces) gives the nesting depth, so a
          // sub-list stays indented instead of flattening to the top level.
          var indent = bullet[1].replace(/\t/g, "  ").length
          if (baseIndent < 0) baseIndent = indent
          current = {
            text: bullet[3].trim(),
            depth: Math.max(0, Math.round((indent - baseIndent) / 2)),
            // Set when a continuation line follows: the renderer spaces list
            // blocks (multi-line items) apart, one-liners stay compact.
            multiline: false
          }
          i++
          continue
        }
        // A wrapped/lazy line belongs to the item above, unless it opens another
        // block type.
        if (current && !/^(#{1,6})\s+/.test(cur) && !/^\s*```/.test(cur)
            && !/^\s*>\s?/.test(cur)) {
          current.text += " " + cur.trim()
          current.multiline = true
          i++
          continue
        }
        break
      }
      if (current) items.push(current)
      blocks.push({ type: "list", ordered: ordered, items: items })
      continue
    }

    var paragraph = []
    while (i < lines.length
        && !startsBlock(lines[i], lines[i + 1])) {
      paragraph.push(lines[i].trim())
      i++
    }
    blocks.push({ type: "paragraph", text: paragraph.join(" ") })
  }
  return blocks
}

// --- config ----------------------------------------------------------------

// The versioned CloudFront base from config.json, without the trailing slash.
// The "Archive RAW" links derive `<base>/datasets/datasets.json` from it, so
// they always point at the dataset of the version currently in use.
function parseBase(raw, fallback) {
  var fb = String(fallback || "").replace(/\/+$/, "")
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.base) return fb
    return String(cfg.base).replace(/\/+$/, "")
  } catch (e) {
    return fb
  }
}

// Merge the `links` block of config.json over the shipped defaults. Links are
// data so the Help screen and the GitHub button can be repointed without a code
// change. `database` has no default: the Archive RAW target is derived from
// `base` (see parseBase), and an explicit value here overrides it.
function parseLinks(raw, fallback) {
  var base = fallback || {}
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.links) return base
    return {
      repo: cfg.links.repo || base.repo,
      donation: cfg.links.donation || base.donation,
      issues: cfg.links.issues || base.issues,
      releases: cfg.links.releases || base.releases,
      database: cfg.links.database || base.database || ""
    }
  } catch (e) {
    return base
  }
}

// Merge the `paths` block of config.json over the shipped defaults.
function parsePaths(raw, fallback) {
  var base = fallback || {}
  try {
    var cfg = JSON.parse(String(raw || "{}"))
    if (!cfg || !cfg.paths) return base
    return {
      scripts: cfg.paths.scripts || base.scripts,
      assets: cfg.paths.assets || base.assets,
      logo: cfg.paths.logo || base.logo,
      help: cfg.paths.help || base.help
    }
  } catch (e) {
    return base
  }
}

// Export CommonJS for the unit tests under `tests/`. QML imports this file as a
// JS module and never defines `module`, so the guard is a no-op there.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseThemes,
    parseCatalog,
    themeLabel,
    normalizeSlug,
    ucfirst,
    titleCase,
    themeMatches,
    formatPercent,
    elideMiddle,
    formatSize,
    wallpaperMatches,
    collectionOptions,
    wallpaperTotals,
    collectionSummary,
    themeState,
    themeStatusLabel,
    paletteList,
    stepIndex,
    textAction,
    themeTextAction,
    themesStatus,
    catalogStatus,
    emptyHelpIndex,
    parseHelpIndex,
    helpFlatItems,
    helpSidebarEntries,
    parseRoadmap,
    inlineMarkdown,
    splitTableRow,
    isTableSeparator,
    parseMarkdown,
    parseBase,
    parseLinks,
    parsePaths
  }
}
