#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Scan this repo for personal or secret data before it can be committed or pushed. Exit status 1 on any finding.
#   tools/leak-check.sh [--staged] [--history] [--strict]
#     (default)  tracked files plus untracked files that .gitignore does not drop (what `git add -A` would commit)
#     --staged   the STAGED content (blobs from the index, not the working copy) of files staged for the next commit
#     --history  every commit on every branch: added lines, commit messages, author names and e-mails
#     --strict   also fail when the personal-strings file is missing, and on files that exist under config/ but are
#                silently dropped by .gitignore (so a wanted file is never lost without notice)
# Checks: (1) paths must live under the allow-listed top-level names; (2) forbidden file names; (3) binary files, symlinks
# and unreadable files are refused; (4) risky content (keys, tokens, e-mail addresses, private/Tailscale IPs, IPv6, MAC
# addresses, home paths of a real user, ssh public keys, monitor make/model/serial names, 32-hex machine ids,
# password-like assignments); (5) YOUR personal strings, one regular expression per line in an UNTRACKED file:
# $LEAK_PATTERNS_FILE, default ~/.config/dot-files/leak-patterns; (6) gitleaks when installed.
# A line containing "leak-check: allow" is skipped for the harmless classes only (e-mail, IP, MAC, home path, machine
# id, monitor name). It never silences keys, tokens, credential assignments, ssh keys or your personal strings.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); cd "$root"
staged=0; strict=0; history=0
for a in "$@"; do case "$a" in --staged) staged=1 ;; --strict) strict=1 ;; --history) history=1 ;; *) echo "unknown option $a" >&2; exit 2 ;; esac; done
bad=0
say() { echo "LEAK  $*"; bad=$((bad+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# ---- pattern tables -------------------------------------------------------------------------------------------
# class|regex|honours-the-allow-marker (1/0)
emailre='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
classes=(
  'private-key|-----BEGIN [A-Z0-9 ]*PRIVATE KEY|0'
  'ssh-public-key|(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[a-z0-9]+|sk-ssh-ed25519@openssh\.com)[[:space:]]+AAAA[A-Za-z0-9+/=]{20,}|0'
  'aws-key|AKIA[0-9A-Z]{16}|0'
  'github-token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|0'
  'slack-token|xox[baprs]-[A-Za-z0-9-]{10,}|0'
  'google-api-key|AIza[0-9A-Za-z_-]{35}|0'
  'slack-webhook|hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+|0'
  'discord-webhook|discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|0'
  'api-secret-key|(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,})|0'
  'bearer-token|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}|0'
  'jwt|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|0'
  'credential-assignment|(password|passwd|secret|token|api[_-]?key|apikey|auth)[A-Za-z_-]*["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9+/_.-]{12,}|0'
  'private-ipv4|(^|[^0-9.])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)|1'
  'cgnat-ipv4|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)|1'
  'tailnet-name|[a-z0-9-]+\.ts\.net|1'
  'ipv6|(^|[^0-9a-fA-F:])(fd[0-9a-f]{2}|fe80)(:[0-9a-fA-F]{0,4}){2,7}|1'
  'mac-address|([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|1'
  'machine-id|(^|[^0-9a-fA-F])[0-9a-f]{32}([^0-9a-fA-F]|$)|1'
  'monitor-name|^[[:space:]]*output[[:space:]]+"[^"]+[[:space:]][^"]+"|1'
  'windows-path|[A-Za-z]:\\Users\\[A-Za-z]|1'
  'mac-path|/Users/[A-Za-z][A-Za-z0-9._-]*|1'
  'media-path|/run/media/[A-Za-z][A-Za-z0-9._-]*|1'
  'home-path|/(var/)?home/[A-Za-z_][A-Za-z0-9_.-]*|1'
)
ok_user='user|username|you|example|name|linuxbrew|youruser|me'   # placeholders allowed after /home/ and /Users/ ...

# the owner's declared public identity (this repo's git user.email) may appear, e.g. in LICENSE
pub_email=$(git config user.email 2>/dev/null || true)

# ---- file list ------------------------------------------------------------------------------------------------
files=()
if [ "$history" -eq 0 ]; then
    if [ "$staged" -eq 1 ]; then
        while IFS= read -r -d '' f; do files+=("$f"); done < <(git -c core.quotepath=off diff --cached --name-only -z --diff-filter=ACMR)
    else
        while IFS= read -r -d '' f; do files+=("$f"); done < <(git -c core.quotepath=off ls-files -z --cached --others --exclude-standard)
    fi
    [ "${#files[@]}" -gt 0 ] || { echo "leak-check: nothing to scan"; exit 0; }
fi

allowed='^(\.gitignore|\.github|githooks|tools|config|justfile|README\.md|AGENTS\.md|LICENSE|LICENSES|NOTICE)(/|$)'
forbid='(^|/)(\.env(\..*)?|\.netrc|_netrc|\.npmrc|\.pypirc|\.pgpass|\.git-credentials|id_(rsa|dsa|ecdsa|ed25519)[^/]*|known_hosts[^/]*|authorized_keys[^/]*|u2f_keys|auth\.json|hosts\.yml|rclone\.conf|monitors\.xml|mimeapps\.list|\.vault-pass[^/]*)$|\.(key|pem|p12|pfx|p8|jks|keystore|kdbx|kdb|asc|gpg|pgp|age|ppk|keytab|tfstate|tfvars|pcap|ics|vcf|mbox|sqlite3?|db|sql|dump|log|ovpn|pdf|zip|tar|gz|7z|rar|qcow2|iso|img|png|jpe?g|gif|webp|svg|heic|ttf|otf|woff2?|mp[34]|bin)$|(^|/)(\.ssh|ssh|\.gnupg|gnupg|keyrings|kwalletd|Yubico|tailscale|borg|vorta|goa-1\.0|evolution|aws|gcloud|azure|kube|1Password|Bitwarden|keepassxc|\.password-store|gsconnect|bluetooth)/'

# non-ASCII characters (look-alike letters, zero-width spaces) can hide a personal string from the pattern list
nonascii() {  # nonascii FILE SHOWN
    local ln
    while IFS=: read -r ln _; do [ -n "$ln" ] && say "$2:$ln [non-ASCII character: look-alikes and invisible characters can hide personal strings]"; done \
        < <(LC_ALL=C grep -n -P '[^\x00-\x7F]' "$1" 2>/dev/null)
}

# scan one file's text for the risky classes (path shown as $2, content read from $1)
scan_text() {
    local content="$1" shown="$2" spec name rx honour ln rest m
    for spec in "${classes[@]}"; do
        name=${spec%%|*}; rest=${spec#*|}; honour=${rest##*|}; rx=${rest%|*}
        while IFS=: read -r ln rest; do
            [ -z "$ln" ] && continue
            if [ "$honour" = 1 ]; then case "$rest" in *"leak-check: allow"*) continue ;; esac; fi
            case "$name" in
                home-path|mac-path|media-path)
                    m=$(printf '%s' "$rest" | grep -oiE -- "$rx" | head -1); m=${m##*/}
                    [[ "${m,,}" =~ ^($ok_user)$ ]] && continue ;;
            esac
            say "$shown:$ln [$name] $(printf '%s' "$rest" | cut -c1-90)"
        done < <(grep -n -i -E -- "$rx" "$content" 2>/dev/null)
    done
    while IFS=: read -r ln rest; do
        [ -z "$ln" ] && continue
        case "$rest" in *"leak-check: allow"*) continue ;; esac
        m=$(printf '%s' "$rest" | grep -oE "$emailre" | head -1)
        case "$m" in *@example.*|*@users.noreply.github.com|noreply@*|*@localhost|"") continue ;; esac
        [ -n "$pub_email" ] && [ "$m" = "$pub_email" ] && continue
        say "$shown:$ln [email] $m"
    done < <(grep -n -E "$emailre" "$content" 2>/dev/null)
}

pf="${LEAK_PATTERNS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dot-files/leak-patterns}"
personal=()
if [ -f "$pf" ]; then mapfile -t personal < <(grep -v -E '^[[:space:]]*(#|$)' "$pf")
else
    echo "note: no personal-strings file at $pf (one regular expression per line: your name, hostnames, employer ...)"
    [ "$strict" -eq 1 ] && say "personal-strings file missing (--strict)"
fi

if [ "$history" -eq 1 ]; then
    # (H) every commit: messages, authors, added lines
    git rev-parse --verify -q HEAD >/dev/null || { echo "leak-check: no commits yet"; exit 0; }
    git log --all --format='%an <%ae>%n%cn <%ce>%n%B' > "$tmp/meta.txt" || say "git log failed (the history was NOT scanned)"
    git log --all -p --no-color --format='commit %H' > "$tmp/patch.txt" || say "git log -p failed (the history was NOT scanned)"
    grep -E '^\+' "$tmp/patch.txt" | grep -v -E '^\+\+\+' | sed 's/^+//' > "$tmp/added.txt"
    scan_text "$tmp/added.txt" "history (added lines)"; scan_text "$tmp/meta.txt" "history (commit metadata)"
    # non-ASCII everywhere except in AGENTS.md (the one file that may contain it)
    git log --all -p --no-color --format='commit %H' -- . ':(exclude)AGENTS.md' | grep -E '^\+' | grep -v -E '^\+\+\+' | sed 's/^+//' > "$tmp/added-na.txt"
    nonascii "$tmp/added-na.txt" "history (added lines)"
    for src in meta patch; do
        for spec in "${classes[@]}"; do
            name=${spec%%|*}; rest=${spec#*|}; rx=${rest%|*}
            case "$name" in private-key|ssh-public-key|aws-key|github-token|slack-token|google-api-key|jwt|credential-assignment) ;; *) continue ;; esac
            grep -q -i -E -- "$rx" "$tmp/$src.txt" && say "history ($src): [$name] somewhere in the history"
        done
        for p in "${personal[@]}"; do grep -q -i -E -- "$p" "$tmp/$src.txt" && say "history ($src): [personal: $p]"; done
    done
    if command -v gitleaks >/dev/null 2>&1; then gitleaks detect --no-banner --redact >/dev/null 2>&1 || say "gitleaks found something in the history"; fi
    if [ "$bad" -gt 0 ]; then echo "leak-check: $bad finding(s) in the history"; exit 1; fi
    echo "leak-check: history clean ($(git rev-list --all --count) commits)"; exit 0
fi

# ---- per file ---------------------------------------------------------------------------------------------------
for f in "${files[@]}"; do
    [[ "$f" =~ $allowed ]] || say "$f is outside the allow-listed top-level names"
    [[ "$f" =~ $forbid ]] && say "$f has a forbidden name or lives in a private directory"
    if [ "$staged" -eq 1 ]; then
        git show ":$f" > "$tmp/blob" 2>/dev/null || { say "$f cannot be read from the index"; continue; }
        content="$tmp/blob"
    else
        if [ -L "$f" ]; then say "$f is a symlink (not allowed)"; continue; fi
        [ -f "$f" ] || { say "$f is listed but is not a readable regular file"; continue; }
        content="$f"
    fi
    [ -s "$content" ] || continue
    if [ "$(tr -d '\000' < "$content" | wc -c)" != "$(wc -c < "$content")" ] || ! iconv -f UTF-8 -t UTF-8 "$content" >/dev/null 2>&1; then
        say "$f is a binary file or not valid UTF-8 text (not allowed)"; continue
    fi
    [ "$f" = AGENTS.md ] || nonascii "$content" "$f"   # the one file that is allowed to contain non-ASCII text
    scan_text "$content" "$f"
    for p in "${personal[@]}"; do
        while IFS=: read -r ln rest; do [ -n "$ln" ] && say "$f:$ln [personal: $p]"; done < <(grep -n -i -E -- "$p" "$content" 2>/dev/null)
        printf '%s' "$f" | grep -qiE -- "$p" && say "$f [personal string in the path: $p]"
    done
done

# ---- silently dropped files under config/ -------------------------------------------------------------------------
if [ "$strict" -eq 1 ]; then
    while IFS= read -r -d '' f; do say "$f exists in a tracked folder but .gitignore drops it (rename it, or deliberately keep it out)"; done \
        < <(git -c core.quotepath=off ls-files -z --others --ignored --exclude-standard -- config .github githooks tools LICENSES 2>/dev/null | grep -z -v '/\.gitkeep$')
fi

# ---- gitleaks -----------------------------------------------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
    if [ "$staged" -eq 1 ]; then gitleaks protect --staged --no-banner --redact >/dev/null 2>&1 || say "gitleaks found something in the staged changes"
    else gitleaks detect --no-git --source . --no-banner --redact >/dev/null 2>&1 || say "gitleaks found something in the working tree"; fi
else echo "note: gitleaks not installed (CI runs it)"; fi

if [ "$bad" -gt 0 ]; then echo "leak-check: $bad finding(s)"; exit 1; fi
echo "leak-check: clean (${#files[@]} files)"
