# fzf colors that follow the terminal palette: only the 16 ANSI colors and the terminal default (-1), no fixed hex,
# so fzf looks right on any palette (Gruvbox Material in a Gruvbox Material terminal, something else elsewhere).
# The current line is drawn reversed (works on dark and light backgrounds); pointer, prompt and info are green,
# matches and header are red, marker and spinner are yellow.
# Set with a plain exported variable (rebuilt on every start), so FZF_DEFAULT_OPTS does not grow each time the shell
# starts. Any FZF_DEFAULT_OPTS you export elsewhere is kept in front. A value carrying an older version of these
# options (the earlier fixed-hex colors, or this one) is cut back to your own part first, then rebuilt.
status is-interactive; or return

set -l fzf_theme_opts "--color=16,bg:-1,bg+:-1,fg:-1,fg+:-1:bold:reverse,hl:1,hl+:1,header:1,info:2,pointer:2,prompt:2,marker:3,spinner:3"

set -l fzf_user_opts (string replace -r -- '\n?--color=(bg\+:#|16,bg:-1,bg\+:-1,fg:-1)[\s\S]*$' '' "$FZF_DEFAULT_OPTS")
if test -n "$fzf_user_opts"
    set -gx FZF_DEFAULT_OPTS "$fzf_user_opts
$fzf_theme_opts"
else
    set -gx FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
