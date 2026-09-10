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
5. Rebuilds font and icon caches, sets Thunar as the directory handler
6. Enables NetworkManager, pipewire, the VMware guest tools, and the ly greeter

Every step is idempotent. `--needed` skips installed packages, `stow -R`
restows cleanly, `enable --now` is a no-op on an already-running unit. Safe to
rerun as many times as you like.

## Dotfiles only

`link.sh` does step 4 and nothing else -- no packages, no services, no sudo.
Use it on a machine where you only want the configs, or to relink after adding
a new directory under `dotfiles/`.

Apps write their own config when none exists -- Hyprland regenerates
`~/.config/hypr/hyprland.conf` on every start without one -- and that real file
then blocks stow from linking yours, so the app goes on reading its own default
and your repo config is never used. `link.sh` moves such files into a
timestamped `~/.config-backup-*` first. Nothing is deleted. This is the safe
inverse of `stow --adopt`, which would pull the app's file into the repo over
what you wrote.

```bash
./link.sh
```

`install.sh` calls it rather than duplicating the logic.

## Stripping a system back to base

`strip.sh` removes every explicitly-installed package that is not on the keep
list, then orphaned dependencies, then this repo's dotfile symlinks. It is for
turning a machine that has accumulated things into one install.sh can
provision from a known state -- the same starting point as a fresh snapshot,
without reinstalling Arch.

```bash
./strip.sh            # dry run, prints the full transaction, changes nothing
./strip.sh --apply    # asks you to type STRIP, then does it
```

If a candidate turns out to be required by a package that is staying, pacman
refuses the whole transaction. `strip.sh` reads the name out of that error,
drops it from the removal set and asks again, repeating until pacman is
satisfied -- so a dependency you did not think of does not stop the run. It
reports everything it rescued. That is recomputed on every run and does not
need saving.

Edit `packages/keep.txt` before running. It protects the kernel, the boot
path, NetworkManager, sudo and git by default, and a built-in list refuses to
remove those regardless. **If this machine uses iwd, dhcpcd or a bootloader
package like grub, add it to keep.txt first** -- removing your only network
daemon leaves you with no way to reinstall anything.

It does not touch `/etc`, home directories, or anything not owned by pacman.

## Layout

```
neutrino/
├── install.sh
├── link.sh              # dotfiles only, no packages or services
├── strip.sh             # roll a system back to base Arch
├── packages/
│   ├── pacman.txt        # native, one per line, # comments allowed
│   └── aur.txt
└── dotfiles/
    ├── hypr/.config/hypr/hyprland.conf
    ├── quickshell/.config/quickshell/shell.qml
    ├── nvim/.config/nvim/init.lua
    ├── alacritty/.config/alacritty/alacritty.toml
    ├── zathura/.config/zathura/zathurarc
    ├── gtk/.config/gtk-3.0/settings.ini
    ├── gtk/.config/gtk-4.0/settings.ini
    └── fontconfig/.config/fontconfig/fonts.conf
```

Each directory under `dotfiles/` mirrors its own path relative to `$HOME`, so
`stow -t "$HOME" -R -- */` from inside `dotfiles/` links everything into place.
Because they are symlinks, editing a config on the live system edits the repo.

## Starting a session

The Minimal archinstall profile ships no display manager, so this repo installs
`ly`, a TUI greeter. `install.sh` enables it but does not start it, because ly
seizes a VT and would kill the install mid-run. Reboot and it greets you; pick
Hyprland from the session list with the arrow keys.

If Hyprland dies on VMware's virtual GPU you get dumped back at the greeter
with no error shown. Switch to a TTY with `ctrl+alt+F2` and run it by hand to
see what actually happened:

```bash
Hyprland
tail -40 ~/.local/share/hyprland/hyprland.log
```

Then uncomment the software rendering env lines at the top of
`~/.config/hypr/hyprland.conf`, one block at a time.

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
- **Kora 2.0.0** dropped upstream symlinks and icons half-resolve in some
  panels. Check the AUR comments if theming looks wrong.
- **UEFI must be set before installing Arch.** Changing VM firmware afterwards
  breaks the bootloader.
- **Pasting into the VMware console.** Multi-line pastes while a command is
  still running get buffered and mangled, and commands silently do not run.
  Write to a file and `bash` it.

## Testing from zero

The point of the repo is that it works on a machine that has never seen it.
Roll the VM back to the clean post-archinstall snapshot, then:

```bash
sudo pacman -S --needed git
git clone https://github.com/<you>/neutrino.git && cd neutrino && ./install.sh
```
