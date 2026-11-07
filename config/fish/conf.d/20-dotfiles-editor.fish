# helix is the brew `hx` here. Absolute path for SUDO_EDITOR/sudoedit, which doesn't rely on
# the caller's PATH. Falls back to whatever `hx` is on PATH.
if test -x /home/linuxbrew/.linuxbrew/bin/hx
    set -gx EDITOR /home/linuxbrew/.linuxbrew/bin/hx
    set -gx SUDO_EDITOR /home/linuxbrew/.linuxbrew/bin/hx
else if type -q hx
    set -gx EDITOR hx
    set -gx SUDO_EDITOR hx
end
