#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Live ripgrep search in fzf; writes file:line to the private directory from tmpdir.sh for helix's C-f binding.
set -u
result=$(fzf --disabled --ansi \
    --bind 'start:reload:rg --column --line-number --no-heading --color=always --smart-case -- "" . 2>/dev/null || true' \
    --bind 'change:reload:rg --column --line-number --no-heading --color=always --smart-case -- {q} . 2>/dev/null || true' \
    --delimiter : \
    --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
    --preview-window 'right:55%' \
    --prompt 'Search: ')

[ -z "$result" ] && exit 0

file=$(printf '%s' "$result" | cut -d: -f1)
line=$(printf '%s' "$result" | cut -d: -f2)
printf '%s:%s' "$file" "$line" > "$("$(dirname "$0")/tmpdir.sh")/rg-result"

