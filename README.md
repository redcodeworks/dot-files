# dot-files

My desktop configuration (Fedora Atomic, GNOME and niri, a terminal-centred workflow), reduced to the parts that are
useful for reproducing the setup. A `just` recipe copies them into `~/.config`; nothing personal is in here.

This is a personal project for my own machine, so please excuse the slop. It was written with Claude (Anthropic's coding
assistant) and I have only tested it on my own setup. More serious maintainers are welcome to take anything that looks
useful, no need to ask.

## Requirements

[`just`](https://github.com/casey/just) and bash. Nothing else is needed to install.

## Use

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

## Picking the files up

`just install` copies the files; most apps then need one step by hand. Nothing is switched on without it, except the
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
| gnome | `gnome/*.dconf`, `30-enable-extensions.sh` | `dconf load <path> < file` (the path and an undo line are in each file's header); the extensions must be installed first, then `bash ~/.config/gnome/30-enable-extensions.sh` |
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
- The GNOME `10-app-folders.dconf` replaces your app-grid folder list; the others set the keys named in their headers.

Third-party material is in `NOTICE`. The root `LICENSE` (MIT) covers everything unless a file's SPDX header or `NOTICE` says otherwise.

GTK, libadwaita and GNOME Shell themes and icon sets are not in this repo: they are deployed by their own repo, [gnome-themes](https://github.com/redcodeworks/gnome-themes).

## Contributing

`main` is protected. Push your work to `testing` (`git push origin HEAD:testing`); CI runs the tests there
(`tools/test.sh`, also runnable locally, plus a secret scan). Open a pull request from `testing` into `main`; it can be
merged only when both CI jobs pass.

## Keeping private things out

`.gitignore` is an allow-list (everything is ignored unless named) with a long deny-list of keys, tokens, histories,
databases and application state inside the allowed folders. `tools/leak-check.sh` scans for secrets, e-mail addresses,
private IP and MAC addresses, home paths and a private list of personal strings kept outside the repo
(`~/.config/dot-files/leak-patterns`, one regular expression per line). `just setup-hooks` runs it before every commit and push.

Licence: MIT (`LICENSE`); third-party material is listed in `NOTICE`.
