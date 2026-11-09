#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Test suite for dotctl.sh (install, hint, brew, gnome-apply), the justfile, .gitignore and leak-check.sh. Uses temp directories only.
#   tools/test.sh
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
chk() { if [ "$1" = ok ]; then pass=$((pass+1)); echo "  PASS $2"; else fail=$((fail+1)); echo "  FAIL $2"; fi; }
eq() { [ "$1" = "$2" ] && chk ok "$3" || chk fail "$3 (got '$1', want '$2')"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

echo "=== dotctl"
mkdir -p "$T/src/fish/conf.d" "$T/src/niri" "$T/src/ghostty"
printf 'set -g a 1\n' > "$T/src/fish/conf.d/10-a.fish"
printf 'layout {}\n' > "$T/src/niri/config.kdl"
printf '#!/bin/sh\necho hi\n' > "$T/src/niri/run.sh"; chmod +x "$T/src/niri/run.sh"
printf 'font-size = 11\n' > "$T/src/ghostty/config"
export DOT_SRC="$T/src" DOT_DEST="$T/dest" DOT_STATE="$T/state"
D=tools/dotctl.sh; cd "$root" || exit 1
$D install --dry-run >/dev/null; [ ! -e "$T/dest" ] && chk ok "dry run writes nothing" || chk fail "dry run wrote files"
$D install >/dev/null
eq "$(find "$T/dest" -type f | wc -l | tr -d ' ')" 4 "install copies every file"
[ -x "$T/dest/niri/run.sh" ] && chk ok "executable bit preserved" || chk fail "executable bit lost"
eq "$($D status | awk '{print $1}' | sort -u | tr '\n' ' ')" "same " "status: everything same after install"
out=$($D install); echo "$out" | grep -q "0 new, 0 replaced, 0 kept, 4 already identical" && chk ok "second install is a no-op" || chk fail "second install not a no-op: $out"
# the user edits one file; the repo edits another one the user did not touch
printf 'set -g a 2\n' > "$T/dest/fish/conf.d/10-a.fish"
printf 'layout { gaps 8 }\n' > "$T/src/niri/config.kdl"
eq "$($D status | grep 10-a | awk '{print $1}')" modified "status: edited file is modified"
eq "$($D status | grep config.kdl | awk '{print $1}')" update "status: untouched file with a new repo version is update"
$D diff | grep -q '^=== fish/conf.d/10-a.fish (modified)' && chk ok "diff lists the modified file" || chk fail "diff misses the modified file"
$D install >/dev/null
eq "$(cat "$T/dest/fish/conf.d/10-a.fish")" "set -g a 2" "preserve keeps the edited file"
eq "$(cat "$T/dest/niri/config.kdl")" "layout { gaps 8 }" "preserve updates the untouched file"
# repo changes the file the user also edited: still kept
printf 'set -g a 3\n' > "$T/src/fish/conf.d/10-a.fish"; $D install >/dev/null
eq "$(cat "$T/dest/fish/conf.d/10-a.fish")" "set -g a 2" "preserve keeps the edit even when the repo changed too"
# a file the repo does not have is never deleted
printf 'mine\n' > "$T/dest/fish/conf.d/99-mine.fish"; $D install overwrite >/dev/null 2>&1; $D install --overwrite >/dev/null
eq "$(cat "$T/dest/fish/conf.d/10-a.fish")" "set -g a 3" "overwrite replaces the edited file"
eq "$(cat "$T/dest/fish/conf.d/99-mine.fish")" "mine" "files the repo does not have are never deleted"
bk=$(find "$T/state/backup" -name 10-a.fish 2>/dev/null | head -1); eq "$(cat "$bk" 2>/dev/null)" "set -g a 2" "overwrite saves the old version under backup/"
# an existing file with no install record and different content counts as modified (never clobbered by default)
rm -rf "$T/dest" "$T/state"; mkdir -p "$T/dest/ghostty"; printf 'font-size = 99\n' > "$T/dest/ghostty/config"
$D install >/dev/null; eq "$(cat "$T/dest/ghostty/config")" "font-size = 99" "a pre-existing different file is kept"
# app filter
rm -rf "$T/dest" "$T/state"; $D install fish >/dev/null
[ -e "$T/dest/fish/conf.d/10-a.fish" ] && [ ! -e "$T/dest/niri/config.kdl" ] && chk ok "app filter installs only the named app" || chk fail "app filter"
$D list | grep -q '^fish ' && chk ok "list names the apps" || chk fail "list"
just install bogus >/dev/null 2>&1 && chk fail "just install rejects an unknown mode" || chk ok "just install rejects an unknown mode"
# destination paths that go through a symlink are refused, never written through
rm -rf "$T/dest" "$T/state" "$T/elsewhere"; mkdir -p "$T/dest" "$T/elsewhere"; ln -s "$T/elsewhere" "$T/dest/niri"
$D install >/dev/null 2>&1; [ -z "$(ls -A "$T/elsewhere")" ] && chk ok "no write through a symlinked destination directory" || chk fail "wrote through a symlinked directory"
$D status | grep -q "^refused .*niri/config.kdl" && chk ok "status reports refused for the symlinked path" || chk fail "status does not report the symlink"
# names with spaces keep a working ledger (same, then update)
rm -rf "$T/dest" "$T/state"; mkdir -p "$T/src/my app"; printf 'v1\n' > "$T/src/my app/a b.conf"
$D install >/dev/null; eq "$($D status | grep 'a b.conf' | awk '{print $1}')" same "file name with spaces: same after install"
printf 'v2\n' > "$T/src/my app/a b.conf"; eq "$($D status | grep 'a b.conf' | awk '{print $1}')" update "file name with spaces: update (ledger lookup works)"
rm -rf "$T/src/my app"
unset DOT_SRC DOT_DEST DOT_STATE

echo "=== .gitignore"
G="$T/g"; mkdir -p "$G" && cp -r .gitignore "$G/" && (cd "$G" && git init -q)
ign() { (cd "$G" && mkdir -p "$(dirname "$1")" && : > "$1" && git check-ignore -q "$1"); }
for p in config/ssh/id_ed25519 config/app/.env config/app/secrets.toml config/x/vault.kdbx config/x/key.pem config/x/known_hosts config/Yubico/u2f_keys config/gh/hosts.yml config/fish/fish_history config/app/state.sqlite config/app/session.json config/app/api-token.txt config/tailscale/state notes.txt scratch/a.txt; do
    ign "$p" && chk ok "ignored: $p" || chk fail "NOT ignored: $p"
done
for p in config/fish/conf.d/10-aliases.fish config/niri/config.kdl config/ghostty/config config/helix/config.toml config/starship.toml tools/dotctl.sh README.md justfile; do
    ign "$p" && chk fail "wrongly ignored: $p" || chk ok "tracked: $p"
done

echo "=== leak-check"
L="$T/leak"; mkdir -p "$L" && cp -r tools githooks .gitignore "$L/" && mkdir -p "$L/config/app" && (cd "$L" && git init -q)
echo '# Example config' > "$L/config/app/clean.conf"; echo 'font = mono' >> "$L/config/app/clean.conf"
# shellcheck disable=SC2120
lc() { (cd "$L" && git add -A -f >/dev/null 2>&1; LEAK_PATTERNS_FILE="${LEAK_PATTERNS_FILE:-/nonexistent}" tools/leak-check.sh "$@" 2>&1); }
lc | grep -q "leak-check: clean" && chk ok "clean tree passes" || chk fail "clean tree flagged"
# fake secrets, assembled from pieces so that this file itself stays clean
GH="ghp""_$(printf 'abcdefghij%.0s' 1 2 3 4)"; AWS="AK""IA$(printf 'ABCDEFGH%.0s' 1 2)"; PK="-----BEGIN OPENSSH ""PRIVATE KEY-----"
MAIL="someone""@corp.com"; IP="10.1""."2.3; MAC="aa:bb:cc:dd:""ee:ff"; MID="$(printf '0123456789abcdef%.0s' 1 2)"; HP="/home/""alice/projects"
plant() { echo "$2" > "$L/config/app/$1"; r=$(lc); echo "$r" | grep -q "$3" && chk ok "detects $4" || { chk fail "misses $4"; echo "$r" | tail -3; }; rm -f "$L/config/app/$1"; }
plant a.conf "key = $GH" 'github-token' "a GitHub token"
plant b.conf "x = $AWS" 'aws-key' "an AWS key"
plant c.conf "$PK" 'private-key' "a private key block"
plant d.conf "mail = $MAIL" 'email' "an e-mail address"
plant e.conf "host = $IP" 'private-ipv4' "a private IPv4 address"
plant f.conf "path = $HP" 'home-path' "a real user's home path"
plant g.conf "api_""key = abcd1234abcd1234abcd" 'credential-assignment' "a credential assignment"
plant h.conf "id = $MID" 'machine-id' "a 32-hex id"
plant i.conf "mac = $MAC" 'mac-address' "a MAC address"
echo 'path = /home/user/x' > "$L/config/app/k.conf"; lc | grep -q "home-path" && chk fail "placeholder /home/user is flagged" || chk ok "placeholder /home/user passes"; rm -f "$L/config/app/k.conf"
echo "mail = a""@corp.com # leak-check: allow" > "$L/config/app/l.conf"; lc | grep -q "email" && chk fail "allow marker ignored" || chk ok "allow marker skips a line"; rm -f "$L/config/app/l.conf"
echo "mail = bot""@users.noreply.github.com" > "$L/config/app/m.conf"; lc | grep -q "email" && chk fail "noreply address flagged" || chk ok "noreply address passes"; rm -f "$L/config/app/m.conf"
echo 'x' > "$L/config/app/id_rsa"; lc | grep -q "forbidden name" && chk ok "detects a forbidden file name (id_rsa)" || chk fail "misses id_rsa"; rm -f "$L/config/app/id_rsa"
echo 'x' > "$L/stray.txt"; lc | grep -q "outside the allow-listed" && chk ok "detects a file outside the allow-list" || chk fail "misses the stray root file"; rm -f "$L/stray.txt"; (cd "$L" && git rm -q --cached -f stray.txt 2>/dev/null)
echo 'employer = Contoso' > "$L/config/app/n.conf"; printf 'contoso\n' > "$T/pat"
r=$(cd "$L" && git add -A -f >/dev/null 2>&1; LEAK_PATTERNS_FILE="$T/pat" tools/leak-check.sh 2>&1); echo "$r" | grep -q "personal: contoso" && chk ok "detects a personal string from the patterns file" || chk fail "misses the personal string"; rm -f "$L/config/app/n.conf"
echo 'x' > "$L/config/app/api-token.txt"; r=$(cd "$L" && git add -A >/dev/null 2>&1; LEAK_PATTERNS_FILE="$T/pat" tools/leak-check.sh --strict 2>&1); echo "$r" | grep -q "drops it" && chk ok "--strict reports a file dropped by .gitignore" || chk fail "--strict misses a dropped file"
rm -f "$L/config/app/api-token.txt"
r=$(cd "$L" && git add -A -f >/dev/null 2>&1; LEAK_PATTERNS_FILE=/nonexistent tools/leak-check.sh --strict 2>&1); echo "$r" | grep -q "missing (--strict)" && chk ok "--strict fails without a personal-strings file" || chk fail "--strict ignores the missing patterns file"

# ---- further leak-check cases (fixtures assembled from pieces) ----
UPW="API_""KEY=abcd1234abcd1234abcd1234"; GT="GITHUB_TO""KEN=abcdefghijklmnop1234"; CG="100.101"".102.103"; V6="fd7a"":115c:a1e0:ab12:4843:cd96:625b:8b92"
TS="host""name.tail1234.ts"".net"; DM="aa-bb-cc-dd-""ee-ff"; SK="ssh-ed""25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghijklmnopqrstuvwxyz0123"
WP="C:\\Us""ers\\Bob\\x"; MP="/Us""ers/bob/x"; RM="/run/me""dia/bob/usb"; HU="/home/""Bob/x"; MON='output "Dell Inc. DELL U2720Q ABC1234" {'
plant A1.conf "$UPW" 'credential-assignment' "an UPPERCASE credential assignment"
plant A2.conf "$GT" 'credential-assignment' "an uppercase token assignment"
plant A3.conf "ip = $CG" 'cgnat-ipv4' "a Tailscale CGNAT address"
plant A4.conf "ip = $V6" 'ipv6' "an IPv6 ULA address"
plant A5.conf "name = $TS" 'tailnet-name' "a .ts.net name"
plant A6.conf "mac = $DM" 'mac-address' "a dash-separated MAC"
plant A7.conf "key $SK" 'ssh-public-key' "an ssh public key"
plant A8.conf "p = $WP" 'windows-path' "a Windows user path"
plant A9.conf "p = $MP" 'mac-path' "a macOS user path"
plant B1.conf "p = $RM" 'media-path' "a /run/media user path"
plant B2.conf "p = $HU" 'home-path' "a capitalised home path"
plant B3.conf "$MON" 'monitor-name' "a niri monitor make/model/serial name"
# the allow marker never silences secrets or personal strings
echo "$UPW # leak-check: allow" > "$L/config/app/C1.conf"; lc | grep -q "credential-assignment" && chk ok "allow marker does not silence a credential" || chk fail "allow marker silenced a credential"; rm -f "$L/config/app/C1.conf"
echo "employer = Contoso # leak-check: allow" > "$L/config/app/C2.conf"; printf 'contoso\n' > "$T/pat"
r=$(cd "$L" && git add -A -f >/dev/null 2>&1; LEAK_PATTERNS_FILE="$T/pat" tools/leak-check.sh 2>&1); echo "$r" | grep -q "personal: contoso" && chk ok "allow marker does not silence a personal string" || chk fail "allow marker silenced a personal string"; rm -f "$L/config/app/C2.conf"
# non-ASCII file names are scanned, not skipped
PW="pass""word: hunter2hunter2hunter2"; printf '%s\n' "$PW" > "$L/config/app/caf\303\251.conf"; lc | grep -q "credential-assignment" && chk ok "a non-ASCII file name is scanned" || chk fail "a non-ASCII file name was skipped"; rm -f "$L/config/app/caf"*.conf
# binary files and symlinks are refused
printf 'abc\000def\001\002' > "$L/config/app/blob.dat"; lc | grep -q "binary file" && chk ok "a file with NUL bytes is refused" || chk fail "a NUL-byte file passed"; rm -f "$L/config/app/blob.dat"
printf '\377\376\372\371 invalid utf8' > "$L/config/app/blob2.dat"; lc | grep -q "binary file" && chk ok "a file that is not valid UTF-8 is refused" || chk fail "a non-UTF-8 file passed"; rm -f "$L/config/app/blob2.dat"
ln -s /etc/hostname "$L/config/app/link.conf"; lc | grep -q "symlink" && chk ok "symlinks are refused" || chk fail "a symlink passed"; rm -f "$L/config/app/link.conf"; (cd "$L" && git rm -q --cached -f config/app/link.conf 2>/dev/null)
# --staged scans the staged blob, not the working copy
echo "$UPW" > "$L/config/app/S1.conf"; (cd "$L" && git add -f config/app/S1.conf); echo "clean now" > "$L/config/app/S1.conf"
r=$(cd "$L" && LEAK_PATTERNS_FILE=/nonexistent tools/leak-check.sh --staged 2>&1); echo "$r" | grep -q "credential-assignment" && chk ok "--staged scans the staged blob even if the file was cleaned afterwards" || chk fail "--staged missed a staged secret"
(cd "$L" && git rm -q --cached -f config/app/S1.conf); rm -f "$L/config/app/S1.conf"
# --history finds a secret that was committed and later removed
(cd "$L" && git add -A -f >/dev/null 2>&1 && git commit -q -m base >/dev/null 2>&1) ; echo "$UPW" > "$L/config/app/H1.conf"; (cd "$L" && git add -f -A >/dev/null 2>&1 && git commit -q -m "add"; git rm -q -f config/app/H1.conf; git commit -q -m "remove")
r=$(cd "$L" && LEAK_PATTERNS_FILE=/nonexistent tools/leak-check.sh --history 2>&1); echo "$r" | grep -q "history" && echo "$r" | grep -q "credential-assignment" && chk ok "--history finds a secret removed in a later commit" || chk fail "--history missed a removed secret"
printf 'contoso\n' > "$T/pat"; (cd "$L" && git commit -q --allow-empty -m "work for Contoso")
r=$(cd "$L" && LEAK_PATTERNS_FILE="$T/pat" tools/leak-check.sh --history 2>&1); echo "$r" | grep -q "personal: contoso" && chk ok "--history checks commit messages for personal strings" || chk fail "--history missed a commit message"

# ---- second-review cases ----
JS='{"pass''word": "hunter2hunter2hunter2"}'; JK='{"api_''key": "abcd1234abcd1234abcd1234"}'
BR="Authorization: Bea""rer abcdefghijklmnop1234"; SW="https://hooks.sla""ck.com/services/T0123ABCD/B0123ABCD/abcdefghijklmnop"; SK="sk""-abcdefghijklmnopqrstuvwxyz0123"
plant D1.json "$JS" 'credential-assignment' "a quoted JSON password"
plant D2.json "$JK" 'credential-assignment' "a quoted JSON api key"
plant D3.conf "$BR" 'bearer-token' "a Bearer header"
plant D4.conf "url = $SW" 'slack-webhook' "a Slack webhook"
plant D5.conf "k = $SK" 'api-secret-key' "an sk- API key"
printf 'owner = \xd0\xb5vin\n' > "$L/config/app/U1.conf"
lc | grep -q "non-ASCII" && chk ok "a non-ASCII (look-alike) character is refused" || chk fail "a non-ASCII character passed"; rm -f "$L/config/app/U1.conf"
# a rename with an edit is scanned by --staged
(cd "$L" && git add -A -f >/dev/null 2>&1; git commit -q -m r0 2>/dev/null)
printf 'line one\nline two\nline three\nline four\n' > "$L/config/app/R1.conf"; (cd "$L" && git add -f config/app/R1.conf && git commit -q -m r1)
(cd "$L" && git mv config/app/R1.conf config/app/R2.conf); printf 'line one\nline two\nline three\nline four\nmail = %s\n' "$MAIL" > "$L/config/app/R2.conf"; (cd "$L" && git add -f config/app/R2.conf)
r=$(cd "$L" && LEAK_PATTERNS_FILE=/nonexistent tools/leak-check.sh --staged 2>&1); echo "$r" | grep -q "\[email\]" && chk ok "--staged scans renamed files" || chk fail "--staged skips renamed files"
(cd "$L" && git rm -q --cached -f config/app/R2.conf config/app/R1.conf 2>/dev/null; git commit -q -m r2 2>/dev/null); rm -f "$L/config/app/R2.conf" "$L/config/app/R1.conf"
# --history now covers e-mail, IP and home path, not only secrets
echo "x = z""@corp.com" > "$L/config/app/G1.conf"; echo "ip = 192.168.5"".5" >> "$L/config/app/G1.conf"; echo "p = /home/""bob/x" >> "$L/config/app/G1.conf"
(cd "$L" && git add -f config/app/G1.conf && git commit -q -m g1 && git rm -q -f config/app/G1.conf && git commit -q -m g2)
r=$(cd "$L" && LEAK_PATTERNS_FILE=/nonexistent tools/leak-check.sh --history 2>&1); for c in email private-ipv4 home-path; do echo "$r" | grep -q "\[$c\]" && chk ok "--history finds a removed $c" || chk fail "--history misses a removed $c"; done
# --strict: a file dropped by .gitignore outside config/ is reported too
mkdir -p "$L/.github/workflows"; echo "name: x" > "$L/.github/workflows/secrets.yml"
r=$(cd "$L" && git add -A >/dev/null 2>&1; LEAK_PATTERNS_FILE="$T/pat" tools/leak-check.sh --strict 2>&1); echo "$r" | grep -q "secrets.yml.*drops it" && chk ok "--strict reports a dropped file outside config/" || chk fail "--strict misses a silently dropped workflow file"
rm -rf "$L/.github/workflows/secrets.yml"

# the declared public identity and AGENTS.md are allowed
(cd "$L" && git config user.email "owner""@host.test"); echo "License (c) Owner <owner""@host.test>" > "$L/config/app/P1.conf"
lc | grep -q "\[email\]" && chk fail "the git user.email was flagged" || chk ok "the repo's own git user.email is allowed"; rm -f "$L/config/app/P1.conf"; (cd "$L" && git config --unset user.email)
echo "notes" > "$L/AGENTS.md"; lc | grep -q "AGENTS.md is outside" && chk fail "AGENTS.md rejected by the allow-list" || chk ok "AGENTS.md is on the allow-list"; rm -f "$L/AGENTS.md"

echo "=== hint, brew, gnome-apply"
for d in config/*/; do app=$(basename "$d")
    [ -f "tools/hints/$app.txt" ] && chk ok "hint file for $app" || chk fail "no tools/hints/$app.txt"
    grep -qi -- "$app" README.md && chk ok "README mentions $app" || chk fail "README does not mention $app"
done
for h in tools/hints/*.txt; do [ -d "config/$(basename "$h" .txt)" ] && chk ok "hint $h belongs to an app" || chk fail "hint $h has no config/ app"; done
D=tools/dotctl.sh
out=$($D hint ghostty); eq "$(echo "$out" | head -1)" "== ghostty" "hint: heading line"
echo "$out" | grep -q 'config-file = ?dotfiles.ghostty' && chk ok "hint: ghostty text" || chk fail "hint: ghostty text"
$D hint yazi | grep -q 'ya pkg add yazi-rs/plugins:git' && chk ok "hint: yazi ya pkg add" || chk fail "hint: yazi"
mkdir -p "$T/h/src/known" "$T/h/src/bare" "$T/h/hints"; echo "do this" > "$T/h/hints/known.txt"
eq "$(DOT_SRC="$T/h/src" DOT_HINTS="$T/h/hints" $D hint bare)" "$(printf '== bare\nnothing to do')" "hint: an app without a hint prints nothing to do"
err=$(DOT_SRC="$T/h/src" DOT_HINTS="$T/h/hints" $D hint nope 2>&1); rc=$?
[ "$rc" -ne 0 ] && echo "$err" | grep -q 'unknown app: nope (known apps: bare known)' && chk ok "hint: unknown app is an error naming the known apps" || chk fail "hint: unknown app: $err"
[ "$($D hint | grep -c '^== ')" = "$(find config -mindepth 1 -maxdepth 1 -type d | wc -l)" ] && chk ok "hint without names covers every app" || chk fail "hint without names"
just hint kitty | grep -q globinclude && chk ok "just hint" || chk fail "just hint"

# brew
$D brew --dry-run | grep -q '^would run: brew bundle --file=.*/Brewfile$' && chk ok "brew --dry-run prints the command" || chk fail "brew --dry-run"
eq "$($D brew --dry-run | sed -n 's/^  //p' | wc -l | tr -d ' ')" "$(grep -c '^brew "' Brewfile)" "brew --dry-run lists every formula"
grep -qE '^(cask|tap|vscode|mas) ' Brewfile && chk fail "Brewfile has a cask, tap or other non-formula line" || chk ok "Brewfile: formulae only"
mkdir -p "$T/bb"; printf '#!/bin/sh\necho "brew $*" > "%s/brew.log"\n' "$T/bb" > "$T/bb/brew"; chmod +x "$T/bb/brew"
DOT_BREW="$T/bb/brew" $D brew >/dev/null; grep -q "^brew bundle --file=$root/Brewfile$" "$T/bb/brew.log" && chk ok "brew runs brew bundle on the repo Brewfile" || chk fail "brew bundle call: $(cat "$T/bb/brew.log" 2>&1)"
err=$(DOT_BREW=/nonexistent/brew $D brew 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$err" | grep -q 'brew is not installed' && chk ok "brew: clear error without brew" || chk fail "brew without brew"
for f in config/gnome/*.dconf; do
    grep -qE '^# Load:[[:space:]]+dconf load [^[:space:]]+ <' "$f" && grep -q '^# Undo:' "$f" && chk ok "header has Load and Undo: $f" || chk fail "header lacks Load or Undo: $f"
done

# gnome-apply with stubbed dconf, gsettings and gnome-extensions
G="$T/ga"; mkdir -p "$G/bin" "$G/src/gnome" "$G/state" "$G/data"
cat > "$G/bin/dconf" <<'STUB'
#!/bin/sh
f="$STUBDATA/$(echo "$2" | tr / _)"
case "$1" in
  dump) if [ -f "$f" ]; then cat "$f"; else printf '[/]\nold=1\n'; fi ;;
  load) cat > "$f"; echo "load $2" >> "$STUBDATA/dconf.log" ;;
esac
STUB
cat > "$G/bin/gsettings" <<'STUB'
#!/bin/sh
[ "$1" = get ] && cat "$STUBDATA/enabled" 2>/dev/null || echo "@as []"
STUB
cat > "$G/bin/gnome-extensions" <<'STUB'
#!/bin/sh
case "$1" in
  list) cat "$STUBDATA/installed" ;;
  enable) echo "$2" >> "$STUBDATA/enable.log"; grep -q "'$2'" "$STUBDATA/enabled" 2>/dev/null || echo "['$2']" >> "$STUBDATA/enabled" ;;
esac
STUB
chmod +x "$G/bin/"*
printf '# SPDX-License-Identifier: MIT\n# Sets alpha.\n# Load:   dconf load /org/test/alpha/ < 10-alpha.dconf\n# Undo:   dconf reset -f /org/test/alpha/\n[/]\nk=1\n' > "$G/src/gnome/10-alpha.dconf"
printf '# SPDX-License-Identifier: MIT\n# Sets beta.\n# Load:   dconf load /org/test/beta/ < 20-beta.dconf\n# Undo:   dconf reset -f /org/test/beta/\n[/]\nk=2\n' > "$G/src/gnome/20-beta.dconf"
printf '#!/usr/bin/env bash\nuuids=(\n    have@ext   # leak-check: allow\n    gone@ext   # leak-check: allow\n)\n' > "$G/src/gnome/30-enable-extensions.sh"
echo "have@ext" > "$G/data/installed"
ga() { PATH="$G/bin:$PATH" STUBDATA="$G/data" DOT_SRC="$G/src" DOT_STATE="$G/state" $D gnome-apply "$@" 2>&1; }
r=$(ga --dry-run); rc=$?
eq "$rc" 0 "gnome-apply --dry-run succeeds"
[ ! -e "$G/data/dconf.log" ] && [ ! -e "$G/data/enable.log" ] && [ ! -e "$G/state/backup" ] && chk ok "dry run loads, enables and backs up nothing" || chk fail "dry run changed something"
echo "$r" | grep -q 'changes: Sets alpha.' && echo "$r" | grep -q 'path:    /org/test/alpha/' && echo "$r" | grep -q 'Undo: dconf reset -f /org/test/alpha/' && chk ok "plan shows change, path and undo" || chk fail "plan output: $r"
r=$(ga); rc=$?
eq "$rc" 0 "gnome-apply succeeds"
eq "$(tail -2 "$G/data/_org_test_alpha_")" "$(printf '[/]\nk=1')" "gnome-apply loads the file into its path"
eq "$(cat "$G/data/dconf.log" | tr '\n' ' ')" "load /org/test/alpha/ load /org/test/beta/ " "gnome-apply loads every file"
bk=$(find "$G/state/backup" -name 'dconf-10-alpha.ini' | head -1)
eq "$(cat "$bk" 2>/dev/null)" "$(printf '[/]\nold=1')" "backup holds the values from before the load"
[ -f "$(dirname "$bk")/dconf-20-beta.ini" ] && chk ok "a backup file per dconf file" || chk fail "missing beta backup"
echo "$r" | grep -q 'missing   gone@ext' && echo "$r" | grep -q 'enabled   have@ext' && echo "$r" | grep -q 'Extension Manager' && chk ok "missing extension listed with the Extension Manager hint, installed one enabled" || chk fail "extension output: $r"
eq "$(cat "$G/data/enable.log")" "have@ext" "only the installed extension was enabled"
sleep 1; r=$(ga); eq "$?" 0 "second run succeeds"
eq "$(tail -2 "$G/data/_org_test_alpha_")" "$(printf '[/]\nk=1')" "rerun: same values loaded (idempotent)"
echo "$r" | grep -q 'already   have@ext' && eq "$(wc -l < "$G/data/enable.log" | tr -d ' ')" 1 "rerun: nothing enabled twice" || chk fail "rerun extension output: $r"
bk2=$(find "$G/state/backup" -name 'dconf-10-alpha.ini' | wc -l | tr -d ' '); eq "$bk2" 2 "rerun makes a fresh backup, keeps the old"
# a file without a Load line stops the run before anything is loaded
printf '# SPDX-License-Identifier: MIT\n# Broken.\n# Undo: dconf reset -f /x/\n[/]\nk=1\n' > "$G/src/gnome/15-bad.dconf"; rm -f "$G/data/dconf.log"
r=$(ga); rc=$?; [ "$rc" -ne 0 ] && echo "$r" | grep -q '15-bad.dconf' && [ ! -e "$G/data/dconf.log" ] && chk ok "a header without a Load line fails by name before loading" || chk fail "missing header: $r"
rm -f "$G/src/gnome/15-bad.dconf"
# missing tools
mkdir -p "$G/nobin"; for t in bash sed head grep awk date basename mkdir id cat tr wc dirname; do ln -sf "$(command -v $t)" "$G/nobin/$t"; done
r=$(PATH="$G/nobin" DOT_SRC="$G/src" DOT_STATE="$G/state" "$(command -v bash)" $D gnome-apply 2>&1); rc=$?
[ "$rc" -ne 0 ] && echo "$r" | grep -q 'dconf not found' && chk ok "clear error when dconf is missing" || chk fail "missing dconf: $r"
cp "$G/bin/dconf" "$G/nobin/dconf"; r=$(PATH="$G/nobin" DOT_SRC="$G/src" DOT_STATE="$G/state" "$(command -v bash)" $D gnome-apply 2>&1)
echo "$r" | grep -q 'gsettings not found' && chk ok "clear error when gsettings is missing" || chk fail "missing gsettings: $r"
unset D

echo "=== this repo"
cd "$root" || exit 1; r=$(tools/leak-check.sh 2>&1); echo "$r" | tail -1 | grep -q "clean" && chk ok "tools/leak-check.sh is clean on this repo" || { chk fail "leak-check findings on this repo"; echo "$r" | head -10; }
for f in tools/*.sh githooks/*; do bash -n "$f" && chk ok "bash -n $f" || chk fail "bash -n $f"; done
if command -v shellcheck >/dev/null 2>&1; then shellcheck -S warning tools/*.sh >/dev/null 2>&1 && chk ok "shellcheck" || { chk fail "shellcheck"; shellcheck -S warning tools/*.sh | head; }; else echo "  skip shellcheck (not installed)"; fi

echo; echo "TOTAL: $pass PASS, $fail FAIL"
[ "$fail" -eq 0 ]
