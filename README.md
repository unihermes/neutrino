# Neutrino

Provisions a full Arch Linux desktop from a fresh Minimal install with one
command. Clone, run, log in to Hyprland.

```bash
git clone https://github.com/<you>/neutrino.git
cd neutrino
./install.sh
```

## What it does

1. Full system sync, installs `base-devel git stow`
2. Bootstraps `yay` from `yay-bin` if it is not already present
3. Installs everything in `packages/pacman.txt` and `packages/aur.txt`
4. Symlinks `dotfiles/` into `$HOME` with GNU stow
5. Rebuilds font and icon caches, sets Thunar as the directory handler,
   writes the theme, icons and fonts to gsettings, and quiets the kernel
   command line
6. Applies the boot speed fixes: vfat in the initramfs, iwd no longer blocking
   the greeter, and systemd's unused TPM setup masked
7. Enables iwd, systemd-networkd, systemd-resolved, pipewire, bluetooth,
   power-profiles-daemon, the Bluetooth pairing agent, and the ly greeter

Every step is idempotent. `--needed` skips installed packages, `stow -R`
restows cleanly, `enable --now` is a no-op on an already-running unit. Safe to
rerun as many times as you like.

## Dotfiles only

`link.sh` does step 4 and nothing else -- no packages, no services, no sudo.
Use it on a machine where you only want the configs, or to relink after adding
a new directory under `dotfiles/`.

Apps write their own config when none exists -- Hyprland regenerates
`~/.config/hypr/hyprland.lua` on every start without one -- and that real file
then blocks stow from linking yours, so the app goes on reading its own default
and your repo config is never used. `link.sh` moves such files into a
timestamped `~/.config-backup-*` first. Nothing is deleted. This is the safe
inverse of `stow --adopt`, which would pull the app's file into the repo over
what you wrote.

```bash
./link.sh
```

`install.sh` calls it rather than duplicating the logic.

## Layout

```
neutrino/
├── install.sh
├── link.sh              # dotfiles only, no packages or services
├── wallpapers/          # what wallpaper.sh picks from
├── packages/
│   ├── pacman.txt        # native, one per line, # comments allowed
│   └── aur.txt
└── dotfiles/
    ├── hypr/.config/hypr/       # hyprland.lua, hypridle, hyprlock, helper scripts
    ├── quickshell/.config/quickshell/  # the bar, flyouts, Settings/System windows
    ├── swaync/.config/swaync/{config.json,style.css}
    ├── systemd/.config/systemd/user/   # bt-agent, wireplumber drop-in
    ├── fastfetch/.config/fastfetch/
    ├── wofi/.config/wofi/{config,style.css}
    ├── nvim/.config/nvim/init.lua
    ├── alacritty/.config/alacritty/alacritty.toml
    ├── zathura/.config/zathura/zathurarc
    ├── gtk/.config/gtk-3.0/settings.ini
    ├── gtk/.config/gtk-4.0/settings.ini
    ├── fontconfig/.config/fontconfig/fonts.conf
    ├── icons/.icons/default/index.theme   # cursor fallback
    ├── bash/.bashrc
    └── starship/.config/{starship.toml,starship-path.sh}
```

Each directory under `dotfiles/` mirrors its own path relative to `$HOME`, and
`link.sh` stows every one of them into place.
Because they are symlinks, editing a config on the live system edits the repo.

## Starting a session

The Minimal archinstall profile ships no display manager, so this repo installs
`ly`, a TUI greeter. `install.sh` enables it but does not start it, because ly
seizes a VT and would kill the install mid-run. Reboot and it greets you; pick
Hyprland from the session list with the arrow keys.

If ly never appears at boot, check the usual causes: it isn't installed, the
unit name is wrong (`ly@tty2.service` on ly 1.x), another display manager
already owns `display-manager.service`, or the default boot target isn't
`graphical.target`.

If Hyprland dies you get dumped back at the greeter with no error shown. Switch
to a TTY with `ctrl+alt+F3` and run it by hand to see what happened:

```bash
Hyprland
hyprctl configerrors
```

## Boot output

Boot and shutdown are quiet by default. To see systemd's `[ OK ]` lines --
worth it when a boot hangs and you need to know which unit it hung on:

```bash
BOOT_VERBOSE=1 ./install.sh
```

Run it again without the variable to go back to quiet. Either way the
bootloader entry is backed up to `*.neutrino.bak` first, and a result that has
lost its `root=` is refused rather than written.

## Boot speed

On the XPS 13 the IPU6 camera stack stalls kernel module loading for about 10s
at boot, until the kernel gives up waiting on the `ov01a10` sensor. Anything
that needs a module in that window waits with it. `install.sh` routes the two
things the greeter was waiting on around the stall:

- **`/boot` mount.** The ESP is vfat, and vfat is a module, so the mount sat in
  the stall and held up `sysinit.target`. `vfat` is now in `MODULES=()` in
  `/etc/mkinitcpio.conf` (backed up to `*.neutrino.bak`).
- **iwd.** It is `Type=dbus` and needs crypto modules before it claims its bus
  name, and ly waits on `network.target`. A drop-in at
  `/etc/systemd/system/iwd.service.d/neutrino.conf` sets `Type=exec`.

It also masks `systemd-tpm2-setup-early` and `systemd-tpm2-setup`, about 2s,
unless `/etc/crypttab` asks for a TPM unlock. That stops the setup running and
leaves the TPM's contents alone, so Windows and BitLocker are unaffected.

Wi-Fi, Bluetooth and audio still finish loading about 10s in, after the greeter
is up. To see where time goes:

```bash
systemd-analyze
systemd-analyze blame | head
systemd-analyze critical-chain ly@tty2.service
```

## Theme

Everything is on one grayscale ramp. No hues anywhere: emphasis is carried by
lightness and weight instead.

```
#0b0b0b base     #121212 bar      #1a1a1a surface   #242424 overlay
#303030 border   #4d4d4d muted    #7a7a7a subtext   #c2c2c2 text
#ebebeb bright
```

Alacritty's 16 ANSI slots are a lightness ramp rather than hues, so coloured
output stays legible but monochrome -- you lose red-for-error in `git diff`,
compiler output and `ls`. The `[colors.normal]` and `[colors.bright]` blocks in
`alacritty.toml` are the only place to change if that trade is not worth it.

nvim carries its own scheme in `init.lua` rather than pulling a plugin, so
there is nothing to install and nothing to keep in sync.

Fonts are Ubuntu Nerd Font for sans-serif, serif and UI text, and UbuntuMono
Nerd Font for everything monospace: terminals, the editor, the bar and its
flyouts, wofi and notifications. One font that owns every glyph, icons and
powerline caps included, means nothing is drawn by fallback at another
font's metrics. Alacritty and the editor use the "Nerd Font Mono" variant,
which holds every glyph to one cell; the bar uses the proportional one.

## Regenerating the package lists

Once the system is in a state worth keeping:

```bash
pacman -Qqen > packages/pacman.txt   # explicit native
pacman -Qqem > packages/aur.txt      # foreign, meaning AUR
```

This flattens the comments in the current files. Keep a copy if you want them.

## Verifying names before trusting them

Nerd Font and icon theme names are inconsistent. Check the real strings:

```bash
fc-list : family | grep -i ubuntu | sort -u
ls /usr/share/icons | grep -i kora
fc-match sans-serif
fc-match monospace
```

## Notes

- **AUR safety.** Read the PKGBUILD diffs yay shows you. The legitimate Zen
  package is `zen-browser-bin`; `zen-browser-PATCHED-bin` was malware. This is
  why `install.sh` does not pass `--noconfirm` to the AUR step.
- **Thunar needs its extras.** No `gvfs` means no trash or mounting, no
  `tumbler` means no thumbnails. Both are in `pacman.txt`.
- **Networking is iwd plus systemd-networkd**, not NetworkManager. iwd joins
  the network, networkd runs DHCP, resolved does DNS. Connect with
  `iwctl station wlan0 connect <SSID>` (`iwctl device list` if the interface
  has another name). `install.sh` writes DHCP configs to
  `/etc/systemd/network` only when that directory has none.
- **Wayland ignores settings.ini for GTK3.** Thunar and other GTK3 apps take
  their theme, icons and fonts from gsettings, while fastfetch and GTK4 read
  `settings.ini`. That is how fastfetch can report kora while Thunar shows
  Adwaita. `install.sh` sets both. Change one, change the other.
- **Kora 2.0.0** dropped upstream symlinks and icons half-resolve in some
  panels. Check the AUR comments if theming looks wrong.

## Testing from zero

The point of the repo is that it works on a machine that has never seen it:

```bash
sudo pacman -S --needed git
git clone https://github.com/unihermes/neutrino.git ~/neutrino
cd ~/neutrino && ./install.sh
```

Clone to a path you intend to keep. Stow's symlinks point at the repo's
location on disk, so moving it afterwards leaves every config in `~/.config`
dangling.
