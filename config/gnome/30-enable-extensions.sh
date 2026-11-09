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
    arcmenu@arcmenu.com                                      # ArcMenu, application menu; from extensions.gnome.org  # leak-check: allow
    hotedge@jonathan.jdoda.ca                                # Hot Edge, pressure-edge overview trigger; from extensions.gnome.org  # leak-check: allow
    CoverflowAltTab@palatis.blogspot.com                     # Coverflow Alt-Tab, window switcher; from extensions.gnome.org  # leak-check: allow
    clipboard-indicator@tudmotu.com                          # Clipboard Indicator, clipboard history; from extensions.gnome.org  # leak-check: allow
    tilingshell@ferrarodomenico.com                          # Tiling Shell, window tiling; from extensions.gnome.org  # leak-check: allow
    dash-to-dock@micxgx.gmail.com                            # Dash to Dock; from extensions.gnome.org  # leak-check: allow
    blur-my-shell@aunetx                                     # Blur my Shell; from extensions.gnome.org  # leak-check: allow
    caffeine@patapon.info                                    # Caffeine, inhibit screen suspend; from extensions.gnome.org  # leak-check: allow
    appindicatorsupport@rgcjonas.gmail.com                   # AppIndicator and KStatusNotifierItem support; from extensions.gnome.org  # leak-check: allow
    auto-move-windows@gnome-shell-extensions.gcampax.github.com # Auto Move Windows (gnome-shell-extensions); from extensions.gnome.org  # leak-check: allow
    background-logo@fedorahosted.org                         # Background Logo; ships with the image  # leak-check: allow
    gsconnect@andyholmes.github.io                           # GSConnect, phone integration; ships with the image  # leak-check: allow
    user-theme@gnome-shell-extensions.gcampax.github.com     # User Themes (gnome-shell-extensions); ships with the image  # leak-check: allow
)
for u in "${uuids[@]}"; do
    if gnome-extensions enable "$u" 2>/dev/null; then echo "enabled  $u"; else echo "skipped  $u (not installed?)"; fi
done
