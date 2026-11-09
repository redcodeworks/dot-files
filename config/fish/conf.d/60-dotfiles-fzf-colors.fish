# fzf colours, Gruvbox Material dark. Set with a plain exported variable (rebuilt on every start),
# so FZF_DEFAULT_OPTS does not grow each time the shell starts. Any FZF_DEFAULT_OPTS you export
# elsewhere is kept in front.
status is-interactive; or return

set -l fzf_theme_opts "\
--color=bg+:#32302f
--color=bg:#282828
--color=spinner:#d4be98
--color=hl:#ea6962
--color=fg:#d4be98
--color=header:#ea6962
--color=info:#a9b665
--color=pointer:#d4be98
--color=marker:#d4be98
--color=fg+:#d4be98
--color=prompt:#a9b665
--color=hl+:#ea6962
--color=selected-bg:#7c6f64
--color=border:#32302f
--color=label:#d4be98"

if set -q FZF_DEFAULT_OPTS[1]; and test -n "$FZF_DEFAULT_OPTS"; and not string match -q '*--color=bg+:#32302f*' -- $FZF_DEFAULT_OPTS
    set -gx FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS
$fzf_theme_opts"
else
    set -gx FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
