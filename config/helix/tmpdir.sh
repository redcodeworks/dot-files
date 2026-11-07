#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Print a private per-user scratch directory for the helix key bindings in config.toml (file picker
# results). $XDG_RUNTIME_DIR is already private to the user; without it a mode-700 directory in /tmp is
# created and must be owned by you and not a symlink, otherwise this exits with an error.
set -eu
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    dir="$XDG_RUNTIME_DIR/helix-dotfiles"
else
    dir="/tmp/helix-dotfiles-$(id -u)"
fi
[ -d "$dir" ] || mkdir -m 700 -- "$dir"
if [ -L "$dir" ] || [ ! -O "$dir" ]; then
    echo "tmpdir.sh: $dir is not a directory owned by you" >&2
    exit 1
fi
chmod 700 -- "$dir"
printf '%s\n' "$dir"
