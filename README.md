# dot-files

My desktop configuration (Fedora Atomic, GNOME and niri, a terminal-centred workflow), reduced to the parts that are
useful for reproducing the setup. A `just` recipe copies them into `~/.config`; nothing personal is in here.

## Requirements

[`just`](https://github.com/casey/just) and bash. Nothing else is needed to install. The tools the configs call (helix, yazi, zellij, ...) come from `just brew`; GNOME extensions are installed separately.

## Install and usage

```
git clone https://github.com/redcodeworks/dot-files && cd dot-files
just list                    # apps and files
just status                  # per file: new, same, update (safe to replace) or modified (you changed it)
just diff                    # diffs for everything that differs
just install                 # copy into ~/.config, keeping every file you changed
just install overwrite       # replace files you changed too (the old versions are backed up)
just install preserve fish   # only some apps
```

`install` never deletes files, and it never overwrites a file you edited unless you say `overwrite`. A file you have not
touched since the last install is updated silently, so pulling this repo and running `just install` keeps you current.
Backups of overwritten files go to `~/.local/state/dot-files/backup/<timestamp>/`. Set `DOT_DEST` to install somewhere
else. Files come from `config/<app>/...` and land in `~/.config/<app>/...`.

Most of it is **drop-in files** (`conf.d`, `include`d fragments) with numbered names, so they sit next to your own files
instead of replacing them. Where an app needs one line in your own main config to pick a fragment up, it is listed below.

### Recipes for scripts and ujust

These recipe names and their output are stable, so another script (for example a `ujust` checklist) can call them from a checkout:

| Recipe | What it does |
|---|---|
| `just install [preserve\|overwrite] [app ...]` | copy `config/` into `~/.config` |
| `just status [app ...]` | per file: new, same, update or modified |
| `just diff [app ...]` | diffs for everything that differs |
| `just list` | apps and files this repo manages |
| `just describe [app]` | one line per app, `<app>`, a tab, a short description (the same order as `just list`); handy for building an app chooser |
| `just hint [app ...]` | print the manual step an app needs after install (the table below, from `tools/hints/<app>.txt`); no names means all apps; an app without a step prints `nothing to do`; an unknown app is an error naming the known ones |
| `just brew [--dry-run]` | `brew bundle` on the repo's `Brewfile` (command-line tools the configs use, formulae only); `--dry-run` only lists the formulae and the command; needs Homebrew, no sudo |
| `just gnome-apply [--dry-run]` | for each `config/gnome/*.dconf`: back up the current values of its path to `~/.local/state/dot-files/backup/<timestamp>/dconf-<name>.ini`, then `dconf load` it, printing what it changes, the path and the undo line; then enable the GNOME Shell extensions that are installed and list the missing ones with where each comes from (the image, or extensions.gnome.org via the Extension Manager app; nothing is installed for you). Refuses to run as root; needs `dconf` and `gsettings`; safe to run again |

## Picking the files up

`just install` copies the files; most apps then need one step by hand (`just hint <app>` prints it). Nothing is switched on without it, except the
fish and environment.d files, which are read automatically.

| App | What `just install` drops | Your step |
|---|---|---|
| ghostty | `ghostty/dotfiles.ghostty`, `dotfiles.d/`, `themes/` | Add `config-file = ?dotfiles.ghostty` to your ghostty config. The fragments load after the file that names them, so they override that file; put your own overrides in a second file loaded after (`config-file = ?my.ghostty`) |
| kitty | `kitty/dotfiles.d/*.conf` | Add `globinclude dotfiles.d/*.conf` to `kitty.conf` |
| niri | `niri/config.example.kdl`, `niri/dotfiles.d/` | Paste the `include` lines you want from `config.example.kdl` into your `config.kdl`. Needs niri 25.11+. Every included file must exist (or use `optional=true`); a deleted fragment breaks the config. The Noctalia include is commented out |
| zellij | theme and layout | `theme "dotfiles-gruvbox-material-dark"` in `config.kdl`; layout with `zellij --layout dotfiles-yazelix` |
| lazygit | `dotfiles-gruvbox-material.yml` | Set `LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.config/lazygit/dotfiles-gruvbox-material.yml"`, or merge the file into your `config.yml` |
| helix | `config.toml`, `languages.toml`, `rg-fzf.sh`, `tmpdir.sh` | They are main files: with `preserve` yours are kept (merge by hand). The theme line is commented out |
| btop | theme file | `color_theme = "dotfiles-gruvbox-material-dark"` in `btop.conf` |
| yazi | `yazi.toml`, `keymap.toml`, `theme.toml`, `init.lua` | Install the plugins and flavor: `ya pkg add yazi-rs/plugins:git yazi-rs/plugins:piper yazi-rs/plugins:full-border yazi-rs/plugins:smart-enter yazi-rs/plugins:mount ndtoan96/ouch boydaihungst/mediainfo matt-dong-123/gruvbox-material`. Previewers also call `glow`, `ouch`, `mediainfo`, `jq`, `eza` |
| fish | `conf.d/*.fish`, `functions/y.fish`, `fish_greeting.fish` | Nothing: `conf.d` is read automatically. No fisher plugins are needed |
| environment.d | brew PATH | Nothing; read at your next login |
| gnome | `gnome/*.dconf`, `30-enable-extensions.sh` | `just gnome-apply` (or by hand: `dconf load <path> < file`, the path and an undo line are in each file's header; the extensions must be installed first, then `bash ~/.config/gnome/30-enable-extensions.sh`) |
| gamemode, noctalia, xdg-desktop-portal | `*.example.*` files | Examples: copy to the real name (`~/.config/gamemode.ini`, `~/.config/noctalia/config.toml`, `~/.config/xdg-desktop-portal/niri-portals.conf`) and edit |

### What it changes on your machine

- fish (interactive shells only): `cp` and `mv` ask before overwriting (`-i`); `diff` and `ip` use colour; new short
  names `..`, `...`, `lt`, `fp`, `ipy`; `y` runs yazi and changes into the folder you quit in; a fastfetch
  greeting; `EZA_ICONS_AUTO=1`; fzf colours through `FZF_DEFAULT_OPTS` (your own value is kept in front);
  `~/.local/bin` is added to `PATH`; `EDITOR` and `SUDO_EDITOR` point to helix when it is installed; the brew and rustup
  environments are loaded if present.
- environment.d adds Homebrew's `bin` at the end of `PATH` for your session.
- niri `10-environment.kdl` sets `QT_QPA_PLATFORMTHEME=gtk3` and `PROTON_ENABLE_HDR=0`. The askpass variables are commented out.
- niri Noctalia fragment (off by default): starts Noctalia, sets a global corner radius, blur on every window, and turns on
  the niri debug flag `honor-xdg-activation-with-invalid-serial`, which weakens focus-steal protection.
- ghostty: the `ssh-terminfo` feature copies Ghostty's terminfo to hosts you ssh into.
- The GNOME `10-app-folders.dconf` replaces your app-grid folder list; `41-auto-move-windows.dconf` replaces the list of which app opens on which workspace (it holds the owner's app ids, edit it first); the others set the keys named in their headers (Auto Move Windows, Tiling Shell and ArcMenu have a file each).

Third-party material is in `NOTICE`. The root `LICENSE` (MIT) covers everything unless a file's SPDX header or `NOTICE` says otherwise.

GTK, libadwaita and GNOME Shell themes and icon sets are not in this repo: they come from their own repo, [gnome-themes](https://github.com/redcodeworks/gnome-themes).

## Contributing

This is a personal setup, so there is no support and I am not looking for outside contributions or pull requests. If
something here is useful to you, fork it and make it yours.

## License

MIT (`LICENSE`), unless a file's SPDX header or `NOTICE` says otherwise. Third-party material is listed in `NOTICE`, with
licence texts in `LICENSES/`.

## Credits

- Colour values: [Gruvbox Material](https://github.com/sainnhe/gruvbox-material) by sainnhe (MIT) and [Gruvbox](https://github.com/morhetz/gruvbox) by morhetz.
- The btop theme is adapted from the `gruvbox_material_dark` theme bundled with [btop](https://github.com/aristocratos/btop) (Apache-2.0).
- The niri example config and a few fragments reproduce parts of the default config of [niri](https://github.com/YaLTeR/niri) (GPL-3.0-or-later).
- The `y` fish function is adapted from the shell wrapper in the [Yazi](https://yazi-rs.github.io) documentation (MIT).
- Not included, but used by the setup: GNOME Shell extensions, yazi plugins and its gruvbox-material flavor, Papirus icons, and the Nerd Fonts named in the configs, each under its own licence.
- Written with Claude, Anthropic's coding assistant.

## About this repo

This is a personal project for my own machine, so please excuse the slop. It was written with Claude (Anthropic's coding
assistant) and I have only tested it on my own setup. I will not maintain it beyond my own needs. If you find something
valuable here, please fork it and take it from there, no need to ask.
