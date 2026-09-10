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
6. Enables NetworkManager, pipewire, and the VMware guest tools

Every step is idempotent. `--needed` skips installed packages, `stow -R`
restows cleanly, `enable --now` is a no-op on an already-running unit. Safe to
rerun as many times as you like.

## Layout

```
neutrino/
├── install.sh
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

The Minimal archinstall profile ships no display manager, so log in on a TTY
and start the compositor by hand:

```bash
Hyprland
```

If it dies immediately on VMware's virtual GPU, uncomment the software
rendering env lines at the top of `~/.config/hypr/hyprland.conf`, one block at
a time, and read `~/.local/share/hyprland/hyprland.log`.

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
