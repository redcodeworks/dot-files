# Homebrew on Linux. /home/linuxbrew isn't shared into containers (e.g. distrobox, which
# shares $HOME but not paths outside it), so guard everything brew-related on the binary
# actually existing rather than assuming a host environment.
if test -x /home/linuxbrew/.linuxbrew/bin/brew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)

    # `brew shellenv` sets up PATH/MANPATH/INFOPATH but doesn't touch fish's
    # completion search path at all -- formulae that ship fish completions
    # (zellij, bat, eza, curl, fastfetch, ...) install them under here, and
    # without this line fish never finds them despite the tools themselves
    # being on PATH correctly.
    if not contains /home/linuxbrew/.linuxbrew/share/fish/vendor_completions.d $fish_complete_path
        set -ga fish_complete_path /home/linuxbrew/.linuxbrew/share/fish/vendor_completions.d
    end

    # Prefer system tools over Homebrew's for anything both provide (Homebrew
    # shadowing system binaries such as gdbus can break desktop tools); brew
    # still wins for anything the system doesn't ship.
    set -gx PATH (string match -v /home/linuxbrew/.linuxbrew/bin -- $PATH)
    set -gx PATH (string match -v /home/linuxbrew/.linuxbrew/sbin -- $PATH)
    set -gx PATH $PATH /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin
end
