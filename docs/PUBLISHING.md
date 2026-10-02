# Publishing to the marketplace

What it takes for this plugin to be **accepted** by the Omarchy plugin
marketplace, and what to check before submitting. Read this together with
`docs/SECURITY.md` (the controls) and `docs/RELEASE.md` (how to cut a release).

## How acceptance works

The marketplace does not take a plugin on trust. It is accepted only after a
**verification issue** (`[Verify]: <plugin-id>`) is opened in
`omacom/omarchy-plugin-marketplace` and passes. Only the **exact target commit**
named in that issue can become a verified snapshot, so any code change means a
new commit and a new target.

The verification has three parts:

1. **Automated confirmation** — repository, plugin id/set and exact commit.
2. **Automated security baseline** — detects only its *documented patterns*.
   Passing it is not a security audit and does not prove the plugin safe.
3. **Human review** — a person traces where untrusted data goes and blocks on
   any execution, path or network boundary they can reach.

Because the human review finds issues **one at a time**, fixing only the
reported line guarantees another round. Audit the whole class *before*
submitting.

## The one rule

> Every value from outside (CDN catalogue, `datasets.json`, environment,
> arguments) is **text**, not a number, not a path, not a URL, not a command —
> until it is validated at the point it enters.

For each remote field, ask **where it ends up** and validate it there.

## Pre-submission checklist

### Untrusted data → sink

- [ ] **File name** — `is_safe_filename()` (bare name: no `/`, no `.`/`..`, no
      leading `-`) and an allowed image extension; the destination stays under
      `DEST_BASE` (`download_one` re-checks with `realpath -m`).
- [ ] **Theme key / name** — `require_safe_theme()` on every command that takes a
      theme; `is_safe_filename()` on the keys of `datasets.json` wherever they
      build a path (`prefetch_catalogs`, `cmd_themes`).
- [ ] **Numbers** — `is_nonneg_int()` before **any** `$(( ))`. Bash *re-evaluates*
      a variable's value in arithmetic context, so `a[$(cmd)]` runs a command.
      Never pass a remote value straight into arithmetic.
- [ ] **URLs** — `is_remote_url()` (`http(s)://` only) and pass them to `curl`
      **after `--`**, so they cannot be read as options (leading `-`) or as
      `file://` local reads.
- [ ] **`jq` arguments** — use `--arg` / `--argjson`, never string-interpolate a
      remote value into the filter.
- [ ] **No `eval`, no `source`, no unquoted expansion** of a remote value.

### QML

- [ ] No `eval` / `Qt.evaluate` / `Function(...)` on remote strings.
- [ ] `Process.command` stays an **array** (it uses `execve`, not a shell).
- [ ] No remote string is used as a local path / `FileView` source.
- [ ] External links come from the tracked `config/` / `help/`, not the catalogue.

### Static checks (see `docs/TESTING.md`)

- [ ] `bash -n scripts/manager.sh`
- [ ] `node --test`
- [ ] `qmllint` — no `Error:` lines
- [ ] `omarchy plugin validate .`
- [ ] `shellcheck scripts/manager.sh` if installed — useful, but **not** a
      substitute for the manual data-flow audit above.

### Release consistency

- [ ] `manifest.json` `version` == tag == release title.
- [ ] `config/config.json` `base` untouched unless a new snapshot was requested.
- [ ] `AGENTS.md` is a regular gitignored file, never a symlink.

## Known traps

The bugs not to reintroduce are listed in `docs/DEVELOPMENT.md` (see 11 and 12).
The short version:

- A catalogue `filename` becomes a path segment — validate before appending.
- A catalogue `size_bytes` becomes Bash arithmetic — validate before `$(( ))`.
- A dataset theme key becomes a directory — validate before building the path.
- A catalogue URL becomes a `curl` argument — require a scheme and pass it after
  `--`.

## When a finding arrives

1. Fix the **class**, not the single line: search the whole script for the same
   sink and fix every instance.
2. Add the control to `docs/SECURITY.md` and the bug to
   `docs/DEVELOPMENT.md`.
3. Bump the version, commit, push, then update the **Target commit** in the
   verification issue (or open a new one if it is pinned) and reply there.
