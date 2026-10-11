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

> **Early preview (v0.1.0).** It's used daily, but expect rough edges. Issues and ideas are welcome.

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
  windows instead of stealing them: they keep their place on their home workspace and go back when you leave.
- **Workspaces and screens:** `Z X C V B` are this screen's five workspaces, `Tab` goes back to the last one,
  `Q` moves to the next screen, and `W` swaps this workspace with one on the other screen.
- **Lending:** tap an app key to take its window, double-tap to borrow it instead. A borrowed window can sit in
  several workspaces at once; shtl shows it wherever it's on top and leaves a placeholder elsewhere.

Everything is set in **Settings** (`Super+,` with the panel open): the trigger, look (eight popular palettes or
your shell's), where the panel sits (top, center or bottom, with a pixel offset to clear a bar or dock),
behavior, your stars and blueprints.

## Requirements

- **Hyprland 0.56 or newer with a Lua config** (`~/.config/hypr/hyprland.lua`). shtl is a Lua layout; the classic
  `hyprland.conf` can't load it.
- **Quickshell** for the panel.
- **Fira Sans** (and optionally JetBrains Mono Nerd Font for the keycaps).
- **A QWERTY layout.** Other layouts work but the key positions won't match the panel yet.

## Install

**Arch (AUR):** `paru -S shtl` (or your AUR helper of choice), then add one line to `~/.config/hypr/hyprland.lua`:

```lua
dofile("/usr/share/shtl/hypr/shtl.lua")
```

**From a checkout:** clone the repo anywhere and point that line at it, e.g.
`dofile(os.getenv("HOME") .. "/src/shtl/hypr/shtl.lua")`.

Reload Hyprland (or log in again). shtl starts its own panel.

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
| `G` | next blueprint | `Y`–`P`, `N`–`/` | app pool (hold: pick a window, `N`: new one) |
| `Z X C V B` | this screen's workspaces | `Backspace` | shelve the window (hold: close it) |
| `Tab` | back to the last workspace on this screen | `Enter` | bring a window shown elsewhere here |
| `Q` / `W` | next screen / swap workspaces across screens | `1`–`9` | constellations |
| `Super+S` | save as a constellation | `Super+,` | settings |

`Space` or `Esc` closes the panel.

## Privacy and what it touches

shtl makes **no network connections** and collects nothing. It reads Hyprland's state, writes its settings and
constellations to `~/.config/shtl/`, and keeps live state in `$XDG_RUNTIME_DIR`. It needs no root, except the
optional keyd setup above. Following your shell's colors reads Caelestia's palette file if it exists.

## Uninstall

Remove the `dofile` line, `sudo pacman -R shtl` (or delete your checkout), and optionally `rm -r ~/.config/shtl`.
If you set up keyd for it: `sudo rm /etc/keyd/shtl.conf && sudo systemctl restart keyd`.

## License

Copyright © 2026 [sbtl.dev](https://sbtl.dev). shtl is free software: you can redistribute it and/or modify it
under the terms of the [GNU General Public License v3](LICENSE) or (at your option) any later version.
Bundles [rxi/json.lua](https://github.com/rxi/json.lua), which is MIT-licensed (its notice is kept in the file).
