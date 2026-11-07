status is-interactive; or return

# Default autosuggestion color is too dim against a dark background to read. nord3 (4c566a)
# was still too muted; nord9 is a lighter frost-blue with more visible contrast while
# staying dimmer than foreground text.
set -g fish_color_autosuggestion 81a1c1

# Selection / search-match / completion-pager highlight used `--background=brblack`,
# i.e. ANSI colour 8 -- invisible against the background with some palettes, and
# unreadable when colour 8 is a lighter dim-text grey (#928374).
# Explicit Gruvbox Material surface (bg4) instead.
set -g fish_color_selection white --background=504945 --bold
set -g fish_color_search_match white --background=504945 --bold
set -g fish_pager_color_selected_background --background=504945

alias diff="diff --color=auto"
alias ip="ip -c=auto"
alias ipy=ipython
alias lt="eza --tree --icons -a -I '.git|__pycache__|.mypy_cache|.ipynb_checkpoints'"
alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias ..="cd .."
alias ...="cd ../.."

# -i asks before overwriting an existing file.
alias cp="cp -i"
alias mv="mv -i"

# eza's own switch for "always behave like --icons=auto": brings icons back for plain
# `eza` (and any ls/ll/l. abbreviations defined elsewhere) without redefining them.
# Explicit --icons flags (lt above) still win.
set -gx EZA_ICONS_AUTO 1
