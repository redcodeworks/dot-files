#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Turn on a set of GNOME Shell extensions. Run it by hand: bash ~/.config/gnome/30-enable-extensions.sh
# The extensions themselves are NOT installed here: install them from extensions.gnome.org or Extension
# Manager first. Ones that are missing are reported and skipped. Unlike loading a dconf list, this ADDS to
# what you already have enabled and never replaces your list. Undo one: gnome-extensions disable <uuid>
# (A new extension may need a log out and in before it can be enabled.)
set -u
command -v gnome-extensions >/dev/null || { echo "gnome-extensions not found (GNOME Shell only)" >&2; exit 1; }
uuids=(
    GPaste@gnome-shell-extensions.gnome.org                  # leak-check: allow
    caffeine@patapon.info                                    # leak-check: allow
    gamemodeshellextension@trsnaqe.com                       # leak-check: allow
    arcmenu@arcmenu.com                                      # leak-check: allow
    CoverflowAltTab@palatis.blogspot.com                     # leak-check: allow
    pip-on-top@rafostar.github.com                           # leak-check: allow
    grand-theft-focus@zalckos.github.com                     # leak-check: allow
    dash-to-dock@micxgx.gmail.com                            # leak-check: allow
    hotedge@jonathan.jdoda.ca                                # leak-check: allow
    user-theme@gnome-shell-extensions.gcampax.github.com     # leak-check: allow
    blur-my-shell@aunetx                                     # leak-check: allow
    appindicatorsupport@rgcjonas.gmail.com                   # leak-check: allow
    forge@jmmaranan.com                                      # leak-check: allow
    clipboard-indicator@tudmotu.com                          # leak-check: allow
    tilingshell@ferrarodomenico.com                          # leak-check: allow
)
for u in "${uuids[@]}"; do
    if gnome-extensions enable "$u" 2>/dev/null; then echo "enabled  $u"; else echo "skipped  $u (not installed?)"; fi
done
