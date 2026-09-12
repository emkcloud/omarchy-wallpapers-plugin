# omarchy-wallpapers-plugin

> ⚠️ **DO NOT USE IN DEVELOPMENT.**
> This plugin is experimental and under active development. It may break,
> change behavior, or be removed at any time without notice. Do not rely on it
> in a development environment or on machines where stability matters.

Omarchy shell plugin: **`emkcloud.wallpaper-manager`**.

Sfoglia i wallpaper del repository [emkcloud/omarchy-wallpapers](https://github.com/emkcloud/omarchy-wallpapers):
scarica `datasets.json` per mostrare i temi disponibili, poi il `catalog.json` del
tema scelto e presenta i wallpaper in griglia con anteprima. Per ogni wallpaper
(oppure in blocco per l'intero tema) puoi:

- **Install** — copia il wallpaper nel tema Omarchy locale
  (`~/.config/omarchy/backgrounds/<theme>/`).
- **Remove** — elimina il wallpaper dal tema locale.
- **Set default** — imposta il wallpaper come sfondo corrente
  (tramite `omarchy-theme-bg-set`).

## Installazione

Da questo repository (radice = plugin):

```bash
omarchy plugin add https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes
```

Oppure in locale per lo sviluppo:

```bash
ln -s /home/massimo/Repositories/omarchy-wallpapers-plugin \
      ~/.config/omarchy/plugins/emkcloud.wallpaper-manager
omarchy-shell shell rescanPlugins
omarchy-shell shell enablePlugin emkcloud.wallpaper-manager '{}'
```

## Utilizzo

Apri il plugin con:

```bash
omarchy-shell shell summon emkcloud.wallpaper-manager '{}'
```

1. Scegli un tema dalla lista (i temi vengono dal repo remoto).
2. Sfoglia la griglia: frecce / `j k h l` per muoverti, `Invio` = install,
   `Del` = remove, `D` = set default, `Esc` = indietro.
3. I bottoni in alto gestiscono le operazioni in blocco (installa/rimuovi tutto).

## Requisiti

- Omarchy con shell Quickshell.
- `curl`, `jq` (per `manager.sh`).

## Note tecniche

- Le anteprime vengono caricate direttamente dall'URL remoto del catalogo
  (la griglia carica solo le immagini visibili, quindi è lazy allo scroll).
- I metadati (lista temi e cataloghi) vengono scaricati dal tag pinnato e
  messi in cache in `datasets/` **al primo avvio** (`datasets.json` + tutti i
  cataloghi, ~1 MB). Da lì in poi liste e griglie funzionano in locale; a ogni
  aggiornamento del plugin la cache del vecchio tag viene sostituita. Se un
  catalogo non si scarica, viene ripreso alla prima apertura del tema.
- Le operazioni install/remove sono native in `manager.sh` (verifica sha256,
  skip se già aggiornato, download parallelo, refresh della cache sfondi).
- Il ref del repo upstream è pinnato in `config/config.json` (`release`):
  `manager.sh` riscrive su quel ref ogni URL embedded nei JSON, così i clienti
  restano su una snapshot testata finché non si aggiorna il plugin
  (`omarchy plugin update`).
- Il layout è in `config/config.json` (`paths`: `scripts`, `assets`, `logo`,
  `datasets`): script, logo e cache vengono risolti da lì, quindi si possono
  spostare senza toccare il QML.
- I colori seguono il tema Omarchy attivo (`qs.Commons.Color` / `Style`).

## Licenza

[MIT](LICENSE)