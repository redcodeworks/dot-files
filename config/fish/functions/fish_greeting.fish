function fish_greeting --description 'Small fastfetch summary instead of the default fish welcome message'
    type -q fastfetch; or return
    fastfetch --config ~/.config/fastfetch/dotfiles.jsonc
end
