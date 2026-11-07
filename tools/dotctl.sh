#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copy the files under config/ into ~/.config (or $DOT_DEST). Needs only bash, coreutils and diff.
#   dotctl.sh install [--overwrite] [--dry-run] [app ...]   copy files (default: keep your changes)
#   dotctl.sh status [app ...]                                new / same / update / modified, per file
#   dotctl.sh diff [app ...]                                  unified diffs for files that differ
#   dotctl.sh list                                            managed apps and files
# An "app" is a top-level directory of config/ (fish, niri, ...). Default mode keeps your changes:
#   - missing file ......................... copied
#   - identical ............................ left alone
#   - differs, you never edited it ......... replaced with the new version (it matches what was installed before)
#   - differs, you edited it (or unknown) .. kept; `status` and `diff` show it, --overwrite replaces it
# --overwrite replaces every differing file; the old versions are saved under $DOT_STATE/backup/<timestamp>/.
# A destination path that goes through a symlink is refused, never written through. Files you have and the repo does not are never deleted. Environment: DOT_DEST (~/.config),
# DOT_SRC (<repo>/config), DOT_STATE (${XDG_STATE_HOME:-~/.local/state}/dot-files).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="${DOT_SRC:-$root/config}"
dest="${DOT_DEST:-${XDG_CONFIG_HOME:-$HOME/.config}}"
state="${DOT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dot-files}"
ledger="$state/installed.sha256"

cmd="${1:-}"; [ $# -gt 0 ] && shift
overwrite=0; dry=0; apps=()
for a in "$@"; do
    case "$a" in
        --overwrite) overwrite=1 ;;
        --dry-run) dry=1 ;;
        -*) echo "unknown option: $a" >&2; exit 2 ;;
        *) apps+=("$a") ;;
    esac
done

[ -d "$src" ] || { echo "no config directory at $src" >&2; exit 1; }
hash_of() { sha256sum < "$1" | cut -d' ' -f1; }
recorded() { [ -f "$ledger" ] && awk -F'\t' -v p="$1" '$2 == p {print $1; exit}' "$ledger" || true; }
record() {  # record REL HASH (exact-path replace, tab separated so names with spaces work)
    [ "$dry" -eq 1 ] && return 0
    mkdir -p "$state"; touch "$ledger"
    awk -F'\t' -v p="$1" '$2 != p' "$ledger" > "$ledger.tmp"
    printf '%s\t%s\n' "$2" "$1" >> "$ledger.tmp"; mv "$ledger.tmp" "$ledger"
}
unsafe_dest() {  # true when a component below $dest is a symlink (a write would land somewhere else)
    local rel="$1" cur="$dest" part
    local IFS=/
    for part in $rel; do cur="$cur/$part"; [ -L "$cur" ] && return 0; done
    return 1
}
files() {   # relative paths of managed files, filtered by app
    local f rel app keep
    while IFS= read -r f; do
        rel="${f#"$src"/}"; keep=1
        if [ "${#apps[@]}" -gt 0 ]; then
            keep=0; for app in "${apps[@]}"; do case "$rel" in "$app"/*|"$app") keep=1 ;; esac; done
        fi
        [ "$keep" -eq 1 ] && printf '%s\n' "$rel"
    done < <(find "$src" -type f ! -name '.gitkeep' ! -name '*
*' | LC_ALL=C sort)
}
state_of() {  # new | same | update | modified   for REL
    local rel="$1" s="$src/$1" d="$dest/$1" sh dh rh
    if unsafe_dest "$rel"; then echo refused; return; fi
    [ -e "$d" ] || { echo new; return; }
    sh=$(hash_of "$s"); dh=$(hash_of "$d")
    [ "$sh" = "$dh" ] && { echo same; return; }
    rh=$(recorded "$rel")
    if [ -n "$rh" ] && [ "$rh" = "$dh" ]; then echo update; else echo modified; fi
}
put() {  # copy REL into dest, keeping the mode
    local rel="$1"
    mkdir -p "$(dirname "$dest/$rel")"
    cp -p -- "$src/$rel" "$dest/$rel"
}

case "$cmd" in
    list)
        apps=(); files | awk -F/ '{c[$1]++} END {for (a in c) printf "%-16s %d file(s)\n", a, c[a]}' | LC_ALL=C sort
        echo; files ;;

    status)
        n=0
        while IFS= read -r rel; do
            st=$(state_of "$rel"); n=$((n+1))
            case "$st" in
                new) tag="new       " ;; same) tag="same      " ;;
                update) tag="update    " ;; modified) tag="modified  " ;; refused) tag="refused   " ;;
            esac
            printf '%s %s\n' "$tag" "$rel"
        done < <(files)
        [ "$n" -gt 0 ] || echo "nothing matches" ;;

    diff)
        while IFS= read -r rel; do
            st=$(state_of "$rel")
            case "$st" in update|modified) echo "=== $rel ($st)"; diff -u --label "your $rel" --label "repo $rel" "$dest/$rel" "$src/$rel" || true ;; esac
        done < <(files) ;;

    install)
        if [ "$dry" -eq 0 ] && command -v flock >/dev/null 2>&1; then mkdir -p "$state"; exec 9> "$state/lock"; flock -n 9 || { echo "another install is running" >&2; exit 1; }; fi
        ts=$(date +%Y%m%d-%H%M%S); copied=0; replaced=0; kept=0; same=0
        while IFS= read -r rel; do
            st=$(state_of "$rel")
            case "$st" in
                new)
                    echo "install   $rel"; [ "$dry" -eq 1 ] || { put "$rel"; record "$rel" "$(hash_of "$src/$rel")"; }; copied=$((copied+1)) ;;
                refused)
                    echo "refused   $rel (a symlink in the destination path; not writing through it)"; kept=$((kept+1)) ;;
                same)
                    record "$rel" "$(hash_of "$src/$rel")"; same=$((same+1)) ;;
                update)
                    echo "update    $rel"; [ "$dry" -eq 1 ] || { put "$rel"; record "$rel" "$(hash_of "$src/$rel")"; }; replaced=$((replaced+1)) ;;
                modified)
                    if [ "$overwrite" -eq 1 ]; then
                        echo "overwrite $rel (old copy in $state/backup/$ts)"
                        if [ "$dry" -eq 0 ]; then
                            mkdir -p "$state/backup/$ts/$(dirname "$rel")"; cp -p -- "$dest/$rel" "$state/backup/$ts/$rel"
                            put "$rel"; record "$rel" "$(hash_of "$src/$rel")"
                        fi
                        replaced=$((replaced+1))
                    else
                        echo "kept      $rel (your version differs; see: just diff, or install with overwrite)"; kept=$((kept+1))
                    fi ;;
            esac
        done < <(files)
        echo "$([ "$dry" -eq 1 ] && echo 'dry run: ')$copied new, $replaced replaced, $kept kept, $same already identical" ;;

    *) sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
