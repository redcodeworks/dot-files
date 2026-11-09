# SPDX-License-Identifier: MIT
# dot-files: copy the files in config/ into ~/.config. Run `just` for this list; every recipe calls tools/dotctl.sh.
# Needs only just and bash.

default:
    @just --list --unsorted

# Copy config/ into ~/.config. mode=preserve (default) keeps files you changed; mode=overwrite replaces them (old versions are backed up). Optionally name apps: just install preserve fish niri
install mode="preserve" *apps:
    @tools/dotctl.sh install {{ if mode == "overwrite" { "--overwrite" } else if mode == "preserve" { "" } else { error("mode must be preserve or overwrite") } }} {{apps}}

# Show what an install would do: new, same, update (safe to replace) or modified (you changed it), per file
status *apps:
    @tools/dotctl.sh status {{apps}}

# Show unified diffs between your files and the repo's for everything that differs
diff *apps:
    @tools/dotctl.sh diff {{apps}}

# List the apps and files this repo manages
list:
    @tools/dotctl.sh list

# Print the manual step each app needs after install (tools/hints/<app>.txt); no app names = all apps
hint *apps:
    @tools/dotctl.sh hint {{apps}}

# Install the command-line tools the configs use from the Brewfile with Homebrew (--dry-run lists them and the command only)
brew *args:
    @tools/dotctl.sh brew {{args}}

# GNOME: back up, then load config/gnome/*.dconf into dconf and enable the extensions that are installed (--dry-run shows the plan)
gnome-apply *args:
    @tools/dotctl.sh gnome-apply {{args}}

# Run the test suite (development)
[private]
test:
    tools/test.sh

# Scan the tracked files for personal or secret data (development; also runs as a git hook and in CI)
[private]
leak-check *args:
    tools/leak-check.sh {{args}}

# Use the git hooks in githooks/ (runs the leak check before every commit and push)
[private]
setup-hooks:
    git config core.hooksPath githooks
