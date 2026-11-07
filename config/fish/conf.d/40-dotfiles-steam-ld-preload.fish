# A terminal added to Steam as a non-Steam game inherits Steam's LD_PRELOAD,
# which lists both the 32-bit and 64-bit gameoverlayrenderer.so. Every 64-bit
# process the shell starts then prints "wrong ELF class: ELFCLASS32" (harmless,
# but once per prompt). Drop the overlay entries here; other entries (extest) stay.
if set -q LD_PRELOAD; and string match -q '*gameoverlayrenderer.so*' -- $LD_PRELOAD
    set -l kept
    for p in (string split : -- $LD_PRELOAD)
        string match -q '*gameoverlayrenderer.so' -- $p; or set -a kept $p
    end
    if set -q kept[1]
        set -gx LD_PRELOAD (string join : -- $kept)
    else
        set -e LD_PRELOAD
    end
end
