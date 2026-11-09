#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copy the files under config/ into ~/.config (or $DOT_DEST). Needs only bash, coreutils and diff.
#   dotctl.sh install [--overwrite] [--dry-run] [app ...]   copy files (default: keep your changes)
#   dotctl.sh status [app ...]                                new / same / update / modified, per file
#   dotctl.sh diff [app ...]                                  unified diffs for files that differ
#   dotctl.sh list                                            managed apps and files
#   dotctl.sh hint [app ...]                                  the manual step an app needs after install (tools/hints/<app>.txt)
#   dotctl.sh brew [--dry-run]                                brew bundle --file=<repo>/Brewfile (command-line tools the configs use)
#   dotctl.sh gnome-apply [--dry-run]                         back up, then load config/gnome/*.dconf; enable installed extensions
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

    hint)
        hints="${DOT_HINTS:-$root/tools/hints}"
        known=$( { [ -d "$src" ] && find "$src" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'; find "$hints" -maxdepth 1 -name '*.txt' -printf '%f\n' 2>/dev/null | sed 's/\.txt$//'; } | LC_ALL=C sort -u)
        [ "${#apps[@]}" -gt 0 ] || mapfile -t apps <<< "$known"
        for app in "${apps[@]}"; do
            printf '%s\n' "$known" | grep -Fxq -- "$app" || { echo "unknown app: $app (known apps: $(printf '%s' "$known" | tr '\n' ' ' | sed 's/ $//'))" >&2; exit 1; }
        done
        first=1
        for app in "${apps[@]}"; do
            [ "$first" -eq 1 ] || echo; first=0
            echo "== $app"
            if [ -f "$hints/$app.txt" ]; then cat "$hints/$app.txt"; else echo "nothing to do"; fi
        done ;;

    brew)
        bf="${DOT_BREWFILE:-$root/Brewfile}"
        [ -f "$bf" ] || { echo "no Brewfile at $bf" >&2; exit 1; }
        if [ "$dry" -eq 1 ]; then
            echo "Brewfile: $bf"
            echo "formulae:"
            sed -n 's/^brew "\([^"]*\)".*/  \1/p' "$bf"
            echo "would run: brew bundle --file=$bf"
            exit 0
        fi
        brewbin="${DOT_BREW:-brew}"
        if ! command -v "$brewbin" >/dev/null 2>&1; then
            if [ -z "${DOT_BREW:-}" ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then brewbin=/home/linuxbrew/.linuxbrew/bin/brew
            else echo "brew is not installed or not on PATH (see https://brew.sh); nothing was done" >&2; exit 1; fi
        fi
        exec "$brewbin" bundle --file="$bf" ;;

    gnome-apply)
        [ "$(id -u)" -ne 0 ] || { echo "gnome-apply changes the dconf settings of a user session: run it as your own user, not root" >&2; exit 1; }
        for t in dconf gsettings; do command -v "$t" >/dev/null 2>&1 || { echo "$t not found (needs a GNOME session's dconf and gsettings tools)" >&2; exit 1; }; done
        gdir="$src/gnome"; [ -d "$gdir" ] || { echo "no gnome directory at $gdir" >&2; exit 1; }
        shopt -s nullglob; dfiles=("$gdir"/*.dconf); shopt -u nullglob
        [ "${#dfiles[@]}" -gt 0 ] || { echo "no *.dconf files in $gdir" >&2; exit 1; }
        # read every header first: one bad file stops the run before anything is loaded
        declare -A dpath dundo ddesc
        for f in "${dfiles[@]}"; do
            n=$(basename "$f")
            dpath[$n]=$(sed -n 's/^# Load:[[:space:]]*dconf load \([^[:space:]]*\)[[:space:]]*<.*/\1/p' "$f" | head -1)
            [ -n "${dpath[$n]}" ] || { echo "$n: header has no '# Load:   dconf load <path> < <file>' line" >&2; exit 1; }
            dundo[$n]=$(sed -n 's/^# \(Undo:.*\)/\1/p' "$f" | head -1 | sed 's/[[:space:]]\{2,\}/ /g')
            [ -n "${dundo[$n]}" ] || { echo "$n: header has no '# Undo:' line" >&2; exit 1; }
            ddesc[$n]=$(grep -m1 -v -e '^# SPDX' -e '^#!' -e '^[^#]' "$f" | sed 's/^# \{0,1\}//')
        done
        ts=$(date +%Y%m%d-%H%M%S); bdir="$state/backup/$ts"
        [ "$dry" -eq 1 ] && echo "dry run: nothing is backed up or loaded"
        for f in "${dfiles[@]}"; do
            n=$(basename "$f"); b="dconf-${n%.dconf}.ini"
            echo "$n"
            echo "  changes: ${ddesc[$n]}"
            echo "  path:    ${dpath[$n]}"
            echo "  ${dundo[$n]}"
            if [ "$dry" -eq 1 ]; then
                echo "  would back up the current values to $bdir/$b, then: dconf load ${dpath[$n]}"
            else
                mkdir -p "$bdir"
                dconf dump "${dpath[$n]}" > "$bdir/$b" || { echo "dconf dump ${dpath[$n]} failed; not loading $n" >&2; exit 1; }
                dconf load "${dpath[$n]}" < "$f" || { echo "dconf load ${dpath[$n]} failed ($n)" >&2; exit 1; }
                echo "  loaded; previous values in $bdir/$b"
            fi
        done
        echo
        # extensions: the list comes from 30-enable-extensions.sh; only installed ones are enabled, nothing is installed
        ext="$gdir/30-enable-extensions.sh"
        if [ ! -f "$ext" ]; then echo "no 30-enable-extensions.sh: extensions skipped"; exit 0; fi
        command -v gnome-extensions >/dev/null 2>&1 || { echo "gnome-extensions not found: extensions skipped (GNOME Shell only)" >&2; exit 1; }
        mapfile -t uuids < <(awk '/^uuids=\(/{on=1;next} on&&/^\)/{exit} on{print $1}' "$ext")
        installed=$(gnome-extensions list 2>/dev/null || true)
        enabled_now=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
        echo "extensions$([ "$dry" -eq 1 ] && echo ' (dry run)'):"
        missing=()
        for u in "${uuids[@]}"; do
            if ! printf '%s\n' "$installed" | grep -Fxq -- "$u"; then
                echo "  missing   $u"; missing+=("$u")
            elif printf '%s' "$enabled_now" | grep -Fq -- "'$u'"; then
                echo "  already   $u"
            elif [ "$dry" -eq 1 ]; then
                echo "  would enable $u"
            elif gnome-extensions enable "$u" 2>/dev/null; then
                echo "  enabled   $u"
            else
                echo "  failed    $u (a new extension may need a log out and in first)"
            fi
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo
            echo "${#missing[@]} extension(s) not installed, not enabled. Install them with the Extension Manager app, then run this again."
        fi ;;

    *) sed -n '3,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
