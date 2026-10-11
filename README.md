<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/shtl-logo-dark.svg">
    <img alt="shtl" src="assets/shtl-logo-light.svg" width="220">
  </picture>
</p>

# shtl

Keyboard-first window placement for [Hyprland](https://hypr.land). Open the panel, then your **left hand picks
where** (a slot, a workspace, a screen) and your **right hand picks what** (a window or an app). Two keys, no
mouse, no memorized chords: the panel shows what every key does right now.

> **Early preview (v0.2.0).** It's used daily, but expect rough edges. Issues and ideas are welcome.

<!-- demo: a short screen recording goes here -->

## What it does

- **Blueprints** are layout shapes: halves, thirds, a main window with a stack, a grid, or your own. Each workspace
  has one, and `G` cycles through them. Slots are `A S D F`.
- **Slots hold layers.** Put several windows in one slot and they stack; press the slot's key again to flip
  through them, or hold it to pick one.
- **The app pool** sits on your right hand (`Y U I O P` and `N M , . /`). Star the apps you use most: your
  **Stars** keep their key, and the free keys fill with your recent apps. Tap to bring an app's window into the selected slot (or
  launch it), hold to choose between its windows, and press `N` in that list for a new one.
- **Constellations** are saved layouts. Press `Super+S` with the panel open to save the workspace as one, and
  `1`–`9` to come back to it. A constellation rebuilds itself from its definition every time, and it **borrows**
  windows instead of stealing them: they keep their place where they were and stay there when you leave.
- **Workspaces and screens:** `Z X C V B` are this screen's five workspaces, `Tab` goes back to the last one and
  `Q` moves to the next screen. The header shows the **other screen** too: `E` / `R` flip what it shows without
  leaving yours, and `W W` swaps this workspace with the one it's showing (`W` then `Z X C V B` for another of
  its five). With three or more screens, `Shift+Q` picks which one that is.
- **Lending:** tap an app key to take its window, double-tap to borrow it instead. A borrowed window can sit in
  several workspaces at once; shtl shows it wherever it's on top and leaves a placeholder elsewhere. Every copy
  is equal: `Backspace` only lets go of it here (a window nothing else holds goes to the hidden shelf).
- **Pick up and put down:** `Shift` + a window key picks that window up (any layer), then select a slot anywhere
  and press `Enter`. Press it twice for a copy instead (borrowed where you put it). Optionally a mouse button
  (click a window, click a slot) or a key of your choice does the same; the carried window wears the accent and
  an outline shows where it would land.

Everything is set in **Settings** (`Super+,` with the panel open): the trigger, look (eight popular palettes or
your shell's), where the panel sits (top, center or bottom, with a pixel offset to clear a bar or dock),
behavior (including the pick-up button and key, and a debug log), your stars and blueprints.

## Requirements

- **Hyprland 0.56 or newer with a Lua config** (`~/.config/hypr/hyprland.lua`). shtl is a Lua layout; the classic
  `hyprland.conf` can't load it.
- **Quickshell** for the panel.
- **Fira Sans** (and optionally JetBrains Mono Nerd Font for the keycaps).
- **A QWERTY layout.** Other layouts work but the key positions won't match the panel yet.

## Install

**Arch and Arch-based** (the AUR package is on its way; AUR sign-ups are paused for now):

```sh
sudo pacman -U https://github.com/thesubtleties/shtl/releases/download/v0.2.0/shtl-0.2.0-1-any.pkg.tar.zst
```

or build the same package yourself:

```sh
git clone https://github.com/thesubtleties/shtl && cd shtl/packaging/aur && makepkg -si
```

Then:

```sh
shtl setup
```

It shows the exact two lines it adds to your Hyprland config (Caelestia users: to `hypr-user.lua`, which
Caelestia never overwrites), keeps a backup, and asks before changing anything. `shtl setup --undo` takes them out.

**From a checkout:** clone the repo anywhere and run `bin/shtl setup` from it, or add the line yourself:
`dofile("/path/to/shtl/hypr/shtl.lua")`.

shtl starts its own panel once Hyprland reloads.

## Opening the panel

Pick one in Settings → Behavior → *Open shtl with*:

| Trigger | How | Needs |
|---|---|---|
| **Key combo** (default) | `Super+Space` opens and closes the panel | nothing |
| **Hold Space** | hold Space for the panel, tap it for a space | [keyd](https://github.com/rvaiya/keyd) |
| **Keyboard key** | your keyboard sends `F13` while you hold a key | a keyboard that can (Wooting, QMK, ZMK) |

**About keyd:** holding a key that still types when tapped needs a key remapper below the compositor. keyd is
open source and in Arch's official repos, but it runs as root and sees every keystroke, as any remapper must.
It's opt-in for that reason. To use it:

```sh
sudo pacman -S keyd
sudo cp /usr/share/shtl/extras/keyd/shtl.conf /etc/keyd/shtl.conf
sudo systemctl enable --now keyd
sudo usermod -aG keyd "$USER"   # then log out and in
```

Then choose **Hold Space** in Settings → Behavior.

If keyd ever misbehaves, `Backspace + Escape + Enter` makes it exit.

## Keys (with the panel open)

| Left hand: where | | Right hand: what | |
|---|---|---|---|
| `A S D F` | select a slot (again: next layer, hold: pick a layer) | `H J K L ;` | windows on this workspace |
| `G` | next blueprint | `Shift` + `H J K L ;` | pick that window up (twice: a copy) |
| `Z X C V B` | this screen's workspaces | `Y`–`P`, `N`–`/` | app pool (hold: pick a window, `N`: new one) |
| `Tab` | back to the last workspace on this screen | `Backspace` | let go of the window here (hold: close it) |
| `Q` | next screen (`Shift+Q`: aim at another) | `Enter` | put down what you carry, or bring a window shown elsewhere here |
| `E` / `R` | the other screen's previous / next workspace | `1`–`9` | constellations |
| `W` | swap with the other screen (`W` again: what it shows) | `Super+,` | settings |
| `Super+S` | save as a constellation | | |

`Space` or `Esc` closes the panel.

## Privacy and what it touches

shtl makes **no network connections** and collects nothing. It reads Hyprland's state, writes its settings and
constellations to `~/.config/shtl/`, and keeps live state in `$XDG_RUNTIME_DIR`. It needs no root, except the
optional keyd setup above. Following your shell's colors reads Caelestia's palette file if it exists.

## Uninstall

`shtl setup --undo`, then `sudo pacman -R shtl` (or delete your checkout), and optionally `rm -r ~/.config/shtl`.
If you set up keyd for it: `sudo rm /etc/keyd/shtl.conf && sudo systemctl restart keyd`.

## License

Copyright © 2026 [sbtl.dev](https://sbtl.dev). shtl is free software: you can redistribute it and/or modify it
under the terms of the [GNU General Public License v3](LICENSE) or (at your option) any later version.
Bundles [rxi/json.lua](https://github.com/rxi/json.lua), which is MIT-licensed (its notice is kept in the file).
