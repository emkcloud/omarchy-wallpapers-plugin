# omarchy-wallpapers-plugin

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
- `curl`, `jq`, `python3` (per `manager.sh` e `wallpapers.py`).

## Note tecniche

- Le anteprime vengono caricate direttamente dall'URL remoto del catalogo
  (la griglia carica solo le immagini visibili, quindi è lazy allo scroll).
- Le operazioni install/remove delegano a `scripts/wallpapers.py` del repo
  wallpapers (verifica sha256, skip se già aggiornato, refresh della cache sfondi).
- I colori seguono il tema Omarchy attivo (`qs.Commons.Color` / `Style`).

## Licenza

[MIT](LICENSE)