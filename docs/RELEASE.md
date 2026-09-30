# Release guide

How to cut a plugin release with consistent GitHub Release notes. Read this
whenever a release is requested.

A release has **three** parts, always in this order:

1. **Version** — bump `manifest.json` `version`.
2. **Tag** — annotated tag with the same number, pushed.
3. **GitHub Release** — same number, with notes in the house style.

> The **CDN snapshot** (`config/config.json` `base`) is separate and not part of
> a release. Do not touch it unless the user asked for a new snapshot.

## 1. Version

Bump `version` in `manifest.json`. It must equal the tag and the release title
(e.g. all `1.5.0`), and be higher than the last one.

Then commit everything still uncommitted, with a concise message.

## 2. Tag and push

```bash
git tag -a <version> -m "<version>"
git push origin main
git push origin <version>
```

## 3. GitHub Release

**Title**: just the version (`1.5.0`).

**Notes**: start with `## What's new in <version>`, then a single-level bullet
list (`-`). Rules:

- **One line per item**, plain, no wrapping. Concise: the point, not the whole
  story.
- Lead with a short label and an em dash: `- Faster opening — the catalogue is a
  plain array, not a slow ListModel build.`
- Cover user-visible changes first (features, fixes, UX), then tooling/docs.
  Skip internal refactors that the user cannot see unless they matter.
- Match the language of the previous releases (English).
- Do not pad: 6–10 bullets is the usual size.

Create it from a notes file so the formatting is exact:

```bash
gh release create <version> --title "<version>" --notes-file /tmp/rel.md
# or edit an existing one:
gh release edit <version> --notes-file /tmp/rel.md
```

Verify at the end:

```bash
gh release list | head -3          # the new one must be Latest
gh release view <version> --json body -q .body
```

## Example (1.4.1 style)

```markdown
## What's new in 1.4.1

- Instant Custom install — the catalogue is now cached in memory and prefetched in the background.
- Updated wallpaper collection — moved to the 1.2.0 snapshot.
- Key hints — the Custom install footer now shows `i` install / `u` uninstall.
- Docs — added the Custom install topic to the Help screen.
```

## Checklist

- [ ] `manifest.json` version bumped and higher than the last.
- [ ] `git status` clean; changes committed.
- [ ] `node --test`, `qmllint`, `bash -n`, `omarchy plugin validate` green
      (see `docs/TESTING.md`).
- [ ] Tag created and pushed.
- [ ] Release notes in the house style, one line per bullet.
- [ ] `gh release list` shows it as **Latest**.
