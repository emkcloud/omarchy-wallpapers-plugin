// Unit tests for interface/js/Model.js. Pure JS, no dependencies: run with
//
//   node --test tests/
//
// Only built-in Node modules are used (no install, no network).

const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../interface/js/Model.js");

// --- parseThemes -----------------------------------------------------------

test("parseThemes reads a full row", () => {
  const raw = "tokyo-night\tTokyo Night\thttps://c\t3\t250\tp.png\t250\t#111,#222\tdesc\timg.png\t1";
  const rows = Model.parseThemes(raw);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0], {
    name: "tokyo-night",
    title: "Tokyo Night",
    catalogUrl: "https://c",
    collections: 3,
    count: 250,
    preview: "p.png",
    installed: 250,
    palette: "#111,#222",
    description: "desc",
    image: "img.png",
    themePresent: "1"
  });
});

test("parseThemes fills defaults for a short row", () => {
  const rows = Model.parseThemes("gruvbox\tGruvbox\thttps://g\t2\t250\tp.png");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].installed, 0);
  assert.equal(rows[0].palette, "");
  assert.equal(rows[0].image, "");
  assert.equal(rows[0].themePresent, "1");
});

test("parseThemes skips blank and too-short lines and handles CRLF", () => {
  const raw = "\nbad\tline\tonly\nosaka-jade\tOsaka Jade\thttps://o\t1\t250\tp.png\r\n";
  const rows = Model.parseThemes(raw);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].name, "osaka-jade");
});

// --- parseCatalog ----------------------------------------------------------

test("parseCatalog reads a full row", () => {
  const raw = "f.webp\tAndorra\tAD\thttps://u\tabc123\t1\t1\tprev.jpg\t1887437\tcountries\t2K\t2560\t1440";
  const rows = Model.parseCatalog(raw);
  assert.deepEqual(rows[0], {
    filename: "f.webp",
    name: "Andorra",
    code: "AD",
    url: "https://u",
    sha256: "abc123",
    installed: "1",
    isDefault: "1",
    preview: "prev.jpg",
    sizeBytes: 1887437,
    collection: "countries",
    resolution: "2K",
    width: 2560,
    height: 1440
  });
});

test("parseCatalog defaults the trailing fields and skips short rows", () => {
  const rows = Model.parseCatalog("f.webp\tAndorra\tAD\thttps://u\tsha\t0\t0\tp.jpg\t100\tcountries\nshort\trow");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].resolution, "");
  assert.equal(rows[0].width, 0);
  assert.equal(rows[0].height, 0);
});

// --- labels ----------------------------------------------------------------

test("themeLabel uppercases and normalizes separators", () => {
  assert.equal(Model.themeLabel({ title: "Tokyo Night", name: "tokyo-night" }), "TOKYO NIGHT");
  assert.equal(Model.themeLabel({ name: "osaka_jade" }), "OSAKA JADE");
  assert.equal(Model.themeLabel({}), "");
  assert.equal(Model.themeLabel(null), "");
});

test("normalizeSlug collapses separators and case", () => {
  assert.equal(Model.normalizeSlug("Osaka-Jade"), "osakajade");
  assert.equal(Model.normalizeSlug("osaka_jade"), "osakajade");
  assert.equal(Model.normalizeSlug(" osaka jade "), "osakajade");
  assert.equal(Model.normalizeSlug(""), "");
});

test("ucfirst uppercases only the first letter", () => {
  assert.equal(Model.ucfirst("catppuccin"), "Catppuccin");
  assert.equal(Model.ucfirst(""), "");
  assert.equal(Model.ucfirst(null), "");
});

test("titleCase uppercases each word, leaving the rest untouched", () => {
  assert.equal(Model.titleCase("001 the old windmill"), "001 The Old Windmill");
  assert.equal(Model.titleCase("helicopter on the roof"), "Helicopter On The Roof");
  assert.equal(Model.titleCase("South Africa"), "South Africa");
  assert.equal(Model.titleCase("USA"), "USA");
  assert.equal(Model.titleCase(""), "");
  assert.equal(Model.titleCase(null), "");
});

test("themeMatches treats hyphens as spaces and searches title and name", () => {
  const item = { name: "tokyo-night", title: "Tokyo Night" };
  assert.equal(Model.themeMatches(item, "tokyo night"), true);
  assert.equal(Model.themeMatches(item, "TOKYO"), true);
  assert.equal(Model.themeMatches(item, "zzz"), false);
  assert.equal(Model.themeMatches(item, ""), true);
  assert.equal(Model.themeMatches(null, "x"), false);
});

test("wallpaperMatches searches name and code", () => {
  const item = { name: "Andorra", code: "AD" };
  assert.equal(Model.wallpaperMatches(item, "and"), true);
  assert.equal(Model.wallpaperMatches(item, "ad"), true);
  assert.equal(Model.wallpaperMatches(item, "zz"), false);
  assert.equal(Model.wallpaperMatches(item, ""), true);
});

test("wallpaperMatches narrows by collection when given", () => {
  const row = { name: "Andorra", code: "AD", collection: "countries" };
  assert.equal(Model.wallpaperMatches(row, "", "countries"), true);
  assert.equal(Model.wallpaperMatches(row, "", "shelters"), false);
  assert.equal(Model.wallpaperMatches(row, "and", "shelters"), false);
  assert.equal(Model.wallpaperMatches(row, "", ""), true);
});

test("collectionOptions lists unique sorted collections with All first", () => {
  const rows = [
    { collection: "shelters" },
    { collection: "countries" },
    { collection: "countries" },
    { collection: "" }
  ];
  assert.deepEqual(Model.collectionOptions(rows), [
    { value: "", label: "All collections" },
    { value: "countries", label: "Countries" },
    { value: "shelters", label: "Shelters" }
  ]);
  assert.deepEqual(Model.collectionOptions(null), [
    { value: "", label: "All collections" }
  ]);
});

test("wallpaperTotals sums count, installed, size and dominant resolution", () => {
  const rows = [
    { collection: "shelters", installed: "1", sizeBytes: 100, resolution: "2K" },
    { collection: "countries", installed: "0", sizeBytes: 200, resolution: "4K" },
    { collection: "countries", installed: "1", sizeBytes: 300, resolution: "2K" },
    { collection: "", installed: "0", sizeBytes: 50, resolution: "2K" }
  ];
  assert.deepEqual(Model.wallpaperTotals(rows), {
    count: 4,
    installed: 2,
    sizeBytes: 650,
    resolution: "2K"
  });
  assert.deepEqual(Model.wallpaperTotals(null), {
    count: 0,
    installed: 0,
    sizeBytes: 0,
    resolution: ""
  });
});

test("collectionSummary aggregates per collection, sorted, ignoring blanks", () => {
  const rows = [
    { collection: "shelters", installed: "1", sizeBytes: 100, resolution: "2K" },
    { collection: "countries", installed: "0", sizeBytes: 200, resolution: "4K" },
    { collection: "countries", installed: "1", sizeBytes: 300, resolution: "2K" },
    { collection: "countries", installed: "0", sizeBytes: 400, resolution: "2K" },
    { collection: "", installed: "0", sizeBytes: 50, resolution: "2K" }
  ];
  assert.deepEqual(Model.collectionSummary(rows), [
    { name: "countries", label: "Countries", count: 3, installed: 1, sizeBytes: 900, resolution: "2K" },
    { name: "shelters", label: "Shelters", count: 1, installed: 1, sizeBytes: 100, resolution: "2K" }
  ]);
  assert.deepEqual(Model.collectionSummary(null), []);
});

test("formatPercent floors whole percents and keeps sub-1% decimals", () => {
  assert.equal(Model.formatPercent(0), "0%");
  assert.equal(Model.formatPercent(1), "100%");
  assert.equal(Model.formatPercent(0.996), "99%");
  assert.equal(Model.formatPercent(0.5), "50%");
  assert.equal(Model.formatPercent(0.008), "0.8%");
  assert.equal(Model.formatPercent(0.0005), "<0.1%");
  assert.equal(Model.formatPercent(2), "100%");
  assert.equal(Model.formatPercent(-1), "0%");
});

test("elideMiddle keeps head and tail within the limit", () => {
  const long = "omarchy-country-AU-Australia-2K.webp";
  const short = Model.elideMiddle(long, 20);
  assert.equal(short.length, 20);
  assert.ok(short.includes("…"));
  assert.ok(short.startsWith("omarchy"));
  assert.ok(short.endsWith(".webp"));
  assert.equal(Model.elideMiddle("short.webp", 20), "short.webp");
  assert.equal(Model.elideMiddle("short.webp", 2), "short.webp");
});

test("formatSize renders MB with one decimal", () => {
  assert.equal(Model.formatSize(0), "");
  assert.equal(Model.formatSize(1048576), "1.0 MB");
  assert.equal(Model.formatSize(1887437), "1.8 MB");
  assert.equal(Model.formatSize(-5), "");
});

// --- theme state -----------------------------------------------------------

test("themeState classifies installed / partial / available", () => {
  assert.equal(Model.themeState({ count: 250, installed: 250 }), "installed");
  assert.equal(Model.themeState({ count: 250, installed: 5 }), "partial");
  assert.equal(Model.themeState({ count: 250, installed: 0 }), "available");
  assert.equal(Model.themeState({ count: 0, installed: 0 }), "available");
  assert.equal(Model.themeState(null), "available");
});

test("themeStatusLabel matches the tile caption", () => {
  assert.equal(Model.themeStatusLabel({ count: 250, installed: 250 }), "250 · installed");
  assert.equal(Model.themeStatusLabel({ count: 250, installed: 5 }), "5/250 installed");
  assert.equal(Model.themeStatusLabel({ count: 250, installed: 0 }), "250 · available");
  assert.equal(Model.themeStatusLabel(null), "");
});

test("paletteList splits and trims the comma list", () => {
  assert.deepEqual(Model.paletteList({ palette: "#111, #222" }), ["#111", "#222"]);
  assert.deepEqual(Model.paletteList({}), []);
  assert.deepEqual(Model.paletteList(null), []);
});

// --- cursor / keyboard / status --------------------------------------------

test("stepIndex clamps and repairs a non-finite index", () => {
  assert.equal(Model.stepIndex(0, 1, 5), 1);
  assert.equal(Model.stepIndex(4, 1, 5), 4);
  assert.equal(Model.stepIndex(0, -1, 5), 0);
  assert.equal(Model.stepIndex(2, 10, 5), 4);
  assert.equal(Model.stepIndex(NaN, 1, 5), 1);
  assert.equal(Model.stepIndex(2, 1, 0), 0);
});

test("textAction maps the wallpaper-screen keys", () => {
  assert.equal(Model.textAction("d"), "default");
  assert.equal(Model.textAction("R"), "refresh");
  assert.equal(Model.textAction("i"), "install");
  assert.equal(Model.textAction("U"), "uninstall");
  assert.equal(Model.textAction("x"), "");
});

test("themeTextAction maps the themes-screen keys", () => {
  assert.equal(Model.themeTextAction("a"), "add");
  assert.equal(Model.themeTextAction("F"), "shuffle");
  assert.equal(Model.themeTextAction("?"), "help");
  assert.equal(Model.themeTextAction("z"), "");
});

test("status captions pluralize", () => {
  assert.equal(Model.themesStatus(1), "1 theme available");
  assert.equal(Model.themesStatus(3), "3 themes available");
  assert.equal(Model.catalogStatus(1, "tokyo-night"), "1 wallpaper in tokyo-night");
  assert.equal(Model.catalogStatus(2, "tokyo-night"), "2 wallpapers in tokyo-night");
});

// --- Markdown --------------------------------------------------------------

test("parseMarkdown folds wrapped list lines into one item", () => {
  const blocks = Model.parseMarkdown("- **A** — prima\n  riga continuata\n- **B** — seconda");
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].type, "list");
  assert.equal(blocks[0].ordered, false);
  assert.equal(blocks[0].items.length, 2);
  assert.equal(blocks[0].items[0].text, "**A** — prima riga continuata");
  assert.equal(blocks[0].items[0].multiline, true);
  assert.equal(blocks[0].items[1].multiline, false);
});

test("parseMarkdown keeps nested list depth", () => {
  const blocks = Model.parseMarkdown("- top\n  - child\n- top2");
  assert.equal(blocks[0].type, "list");
  assert.equal(blocks[0].items.length, 3);
  assert.equal(blocks[0].items[0].depth, 0);
  assert.equal(blocks[0].items[1].depth, 1);
  assert.equal(blocks[0].items[2].depth, 0);
});

test("parseMarkdown detects ordered lists", () => {
  const blocks = Model.parseMarkdown("1. one\n2. two");
  assert.equal(blocks[0].type, "list");
  assert.equal(blocks[0].ordered, true);
  assert.equal(blocks[0].items.length, 2);
});

test("parseMarkdown parses headings, code, tables, notes and rules", () => {
  const raw = [
    "# Title",
    "```sh",
    "echo hi",
    "```",
    "| a | b |",
    "|---|---|",
    "| 1 | 2 |",
    "> a note",
    "---"
  ].join("\n");
  const blocks = Model.parseMarkdown(raw);
  const types = blocks.map((b) => b.type);
  assert.deepEqual(types, ["heading", "code", "table", "note", "rule"]);
  assert.equal(blocks[0].level, 1);
  assert.equal(blocks[1].lang, "sh");
  assert.equal(blocks[1].text, "echo hi");
  assert.deepEqual(blocks[2].headers, ["a", "b"]);
  assert.deepEqual(blocks[2].rows, [["1", "2"]]);
  assert.equal(blocks[3].text, "a note");
});

test("parseMarkdown joins paragraph lines and splits on blank lines", () => {
  const blocks = Model.parseMarkdown("one\ntwo\n\nthree");
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].text, "one two");
  assert.equal(blocks[1].text, "three");
});

test("inlineMarkdown escapes then applies the subset", () => {
  assert.equal(Model.inlineMarkdown("**bold**", "#fff"), "<b>bold</b>");
  assert.equal(Model.inlineMarkdown("*it*", "#fff"), "<i>it</i>");
  assert.equal(Model.inlineMarkdown("[t](https://u)", "#fff"), '<a href="https://u">t</a>');
  assert.equal(Model.inlineMarkdown("`x`", "#fff"), '<font color="#fff">x</font>');
  assert.equal(Model.inlineMarkdown("<x>", "#fff"), "&lt;x&gt;");
});

test("splitTableRow trims the outer pipes", () => {
  assert.deepEqual(Model.splitTableRow("| a | b |"), ["a", "b"]);
  assert.deepEqual(Model.splitTableRow("a | b"), ["a", "b"]);
});

test("isTableSeparator detects the header rule", () => {
  assert.equal(Model.isTableSeparator("|---|---|"), true);
  assert.equal(Model.isTableSeparator("| a | b |"), false);
});

// --- help index / roadmap --------------------------------------------------

test("parseHelpIndex reads sections, resources and feature", () => {
  const raw = JSON.stringify({
    sections: [
      { title: "CONFIGURATION", items: [{ id: "setup", title: "Setup", file: "setup.md" }] }
    ],
    resources: [{ title: "Full guide", link: "repo" }],
    feature: { title: "+ Propose feature", link: "issues" }
  });
  const index = Model.parseHelpIndex(raw);
  assert.equal(index.sections.length, 1);
  assert.equal(index.sections[0].items[0].file, "setup.md");
  assert.equal(index.resources[0].link, "repo");
  assert.equal(index.feature.link, "issues");
});

test("parseHelpIndex degrades to empty on malformed input", () => {
  assert.deepEqual(Model.parseHelpIndex("not json"), Model.emptyHelpIndex());
  assert.deepEqual(Model.parseHelpIndex(""), Model.emptyHelpIndex());
});

test("helpFlatItems and helpSidebarEntries flatten in order", () => {
  const index = Model.parseHelpIndex(JSON.stringify({
    sections: [
      { title: "A", items: [{ id: "a1", title: "A1", file: "a1.md" }] },
      { title: "B", items: [{ id: "b1", title: "B1", file: "b1.md" }] }
    ]
  }));
  assert.deepEqual(Model.helpFlatItems(index).map((i) => i.id), ["a1", "b1"]);
  const entries = Model.helpSidebarEntries(index);
  assert.deepEqual(entries.map((e) => e.type), ["section", "item", "section", "item"]);
  assert.equal(entries[1].flat, 0);
  assert.equal(entries[3].flat, 1);
});

test("parseRoadmap reads items and degrades on malformed input", () => {
  const roadmap = Model.parseRoadmap(JSON.stringify({
    title: "Roadmap",
    subtitle: "soon",
    items: [{ title: "4K", description: "upscale" }]
  }));
  assert.equal(roadmap.title, "Roadmap");
  assert.equal(roadmap.items.length, 1);
  assert.equal(roadmap.items[0].title, "4K");
  assert.deepEqual(Model.parseRoadmap("nope"), { title: "Roadmap", subtitle: "", items: [] });
});

// --- config parsers --------------------------------------------------------

test("parseLinks merges over the fallback", () => {
  const base = { repo: "fb", donation: "d", issues: "i", releases: "r", database: "db" };
  const links = Model.parseLinks(JSON.stringify({ links: { repo: "x" } }), base);
  assert.equal(links.repo, "x");
  assert.equal(links.donation, "d");
  assert.deepEqual(Model.parseLinks("nope", base), base);
});

test("parseBase reads config.base and trims the trailing slash", () => {
  assert.equal(Model.parseBase(JSON.stringify({ base: "https://cdn/x/1.2.0/" }), "fb"), "https://cdn/x/1.2.0");
  assert.equal(Model.parseBase("nope", "https://cdn/x/1.2.0/"), "https://cdn/x/1.2.0");
  assert.equal(Model.parseBase(JSON.stringify({}), "https://cdn/x"), "https://cdn/x");
});

test("parsePaths merges over the fallback", () => {
  const base = { scripts: "s", assets: "a", logo: "l", help: "h" };
  const paths = Model.parsePaths(JSON.stringify({ paths: { help: "docs" } }), base);
  assert.equal(paths.help, "docs");
  assert.equal(paths.scripts, "s");
  assert.deepEqual(Model.parsePaths("nope", base), base);
});
