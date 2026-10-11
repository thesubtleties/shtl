// Copyright (C) 2026 sbtl.dev. shtl is free software under the GNU GPL v3 or later; see LICENSE.
// shtl colors. "default" is shtl's own palette; "shell" follows the desktop shell's Material You
// palette (Caelestia writes one on every wallpaper change; matugen-based shells use the same roles).
// Anything from the shell that would be hard to read falls back to the default, so a pale or washed-out
// wallpaper can't make the panel unusable.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: t

    property string mode: "catppuccin"  // a palette below, or "shell"
    property var shell: null            // Material role -> color, from the shell's scheme file
    property var look: ({})             // material, radius, edge, typeface, density (published by Lua)
    property string shellFont: "Rubik"  // Caelestia's sans unless its shell.json says otherwise

    // The look beyond color
    readonly property real radiusScale: (look.radius ?? 12) / 12           // 12 = "soft", the original
    readonly property real cardAlpha: look.material === "glass" ? 0.62 : look.material === "frosted" ? 0.8 : 0.96
    readonly property real surfaceAlpha: look.material === "glass" ? 0.42 : look.material === "frosted" ? 0.6 : 1
    readonly property string sans: look.typeface === "mono" ? "JetBrainsMono NF"
        : look.typeface === "shell" ? shellFont : "Fira Sans"
    readonly property string condensed: (look.typeface ?? "fira") === "fira" ? "Fira Sans Condensed" : sans
    readonly property bool compact: look.density === "compact"
    readonly property string edgeStyle: look.edge ?? "line"
    readonly property bool following: mode === "shell" && shell !== null

    // Built-in palettes, from each scheme's official palette (dark variants). `teal` is the second tone:
    // windows shown somewhere else.
    readonly property var palettes: ({
        catppuccin: { label: "Catppuccin", bg: "#11111b", card: "#1e1e2e", surface: "#313244", line: "#45475a",
                      edge: "#585b70", fg: "#cdd6f4", muted: "#9399b2", accent: "#cba6f7", onAccent: "#11111b",
                      danger: "#f38ba8", teal: "#94e2d5" },
        tokyonight: { label: "Tokyo Night", bg: "#16161e", card: "#1a1b26", surface: "#292e42", line: "#3b4261",
                      edge: "#545c7e", fg: "#c0caf5", muted: "#737aa2", accent: "#7aa2f7", onAccent: "#16161e",
                      danger: "#f7768e", teal: "#73daca" },
        kanagawa:   { label: "Kanagawa", bg: "#16161d", card: "#1f1f28", surface: "#2a2a37", line: "#363646",
                      edge: "#54546d", fg: "#dcd7ba", muted: "#938aa9", accent: "#7e9cd8", onAccent: "#1f1f28",
                      danger: "#e46876", teal: "#7aa89f" },
        gruvbox:    { label: "Gruvbox", bg: "#1d2021", card: "#282828", surface: "#3c3836", line: "#504945",
                      edge: "#665c54", fg: "#ebdbb2", muted: "#a89984", accent: "#fabd2f", onAccent: "#282828",
                      danger: "#fb4934", teal: "#8ec07c" },
        nord:       { label: "Nord", bg: "#242933", card: "#2e3440", surface: "#3b4252", line: "#434c5e",
                      edge: "#4c566a", fg: "#eceff4", muted: "#9aa3b5", accent: "#88c0d0", onAccent: "#2e3440",
                      danger: "#bf616a", teal: "#a3be8c" },
        rosepine:   { label: "Rosé Pine", bg: "#191724", card: "#1f1d2e", surface: "#26233a", line: "#403d52",
                      edge: "#524f67", fg: "#e0def4", muted: "#908caa", accent: "#ebbcba", onAccent: "#191724",
                      danger: "#eb6f92", teal: "#9ccfd8" },
        everforest: { label: "Everforest", bg: "#1e2326", card: "#272e33", surface: "#2e383c", line: "#374145",
                      edge: "#414b50", fg: "#d3c6aa", muted: "#9da9a0", accent: "#a7c080", onAccent: "#1e2326",
                      danger: "#e67e80", teal: "#83c092" },
        dracula:    { label: "Dracula", bg: "#191a21", card: "#282a36", surface: "#343746", line: "#44475a",
                      edge: "#565970", fg: "#f8f8f2", muted: "#a4abcc", accent: "#bd93f9", onAccent: "#191a21",
                      danger: "#ff5555", teal: "#8be9fd" },
    })
    // the palette in use; following the shell starts from it and replaces what reads well
    readonly property var base: palettes[mode] ?? palettes.catppuccin

    // WCAG contrast between two colors
    function luminance(c) {
        const q = Qt.lighter(c, 1.0)
        const ch = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        return 0.2126 * ch(q.r) + 0.7152 * ch(q.g) + 0.0722 * ch(q.b)
    }
    function contrast(a, b) {
        const la = luminance(a), lb = luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    function withAlpha(c, a) {
        const q = Qt.lighter(c, 1.0)
        return Qt.rgba(q.r, q.g, q.b, a)
    }

    function fromShell(s) {
        const p = Object.assign({}, base)
        const surfaces = {
            bg: s.surfaceContainerLowest ?? s.background, card: s.surfaceContainer ?? s.surface,
            surface: s.surfaceContainerHigh ?? s.surfaceVariant, line: s.outlineVariant,
            edge: s.outline, fg: s.onSurface, muted: s.onSurfaceVariant,
        }
        // surfaces move together, and only if the text stays readable on them
        if (surfaces.card && surfaces.fg && contrast(surfaces.fg, surfaces.card) >= 7
            && (!surfaces.muted || contrast(surfaces.muted, surfaces.card) >= 3.5)) {
            for (const k in surfaces) if (surfaces[k]) p[k] = surfaces[k]
        }
        if (s.primary && contrast(s.primary, p.card) >= 3) {
            p.accent = s.primary
            p.onAccent = s.onPrimary && contrast(s.onPrimary, s.primary) >= 4.5 ? s.onPrimary
                : contrast("#000000", s.primary) > contrast("#ffffff", s.primary) ? "#000000" : "#ffffff"
        }
        if (s.error && contrast(s.error, p.card) >= 3) p.danger = s.error
        if (s.tertiary && contrast(s.tertiary, p.card) >= 3) p.teal = s.tertiary
        return p
    }

    readonly property var p: following ? fromShell(shell) : base

    readonly property color bg: withAlpha(p.bg, surfaceAlpha < 1 ? 0.5 : 1)
    readonly property color card: withAlpha(p.card, cardAlpha)
    readonly property color surface: withAlpha(p.surface, surfaceAlpha)
    readonly property color line: p.line
    readonly property color edge: p.edge          // idle slot outlines
    readonly property color fg: p.fg
    readonly property color muted: p.muted
    readonly property color accent: p.accent
    readonly property color accentSoft: withAlpha(p.accent, 0.16)
    readonly property color accentEdge: Qt.darker(p.accent, 1.3)
    readonly property color onAccent: p.onAccent
    readonly property color danger: p.danger
    readonly property color dangerSoft: withAlpha(p.danger, 0.16)
    readonly property color teal: p.teal
    readonly property color slotIdle: withAlpha(p.fg, 0.02)
    readonly property color placeholderBg: withAlpha(p.bg, 0.72)
    readonly property color placeholderEdge: withAlpha(p.accent, 0.35)
    readonly property color capFace: Qt.lighter(p.surface, 1.18)
    readonly property color capLip: Qt.darker(p.surface, 1.55)

    // Caelestia's own settings: just its font, for typeface "shell"
    FileView {
        path: Quickshell.env("HOME") + "/.config/caelestia/shell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const f = JSON.parse(text()).appearance?.font?.family?.sans
                t.shellFont = f && f !== "" ? f : "Rubik"
            } catch (e) {}
        }
    }

    // Caelestia's palette (rewritten on every wallpaper change)
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                const roles = {}
                for (const k in data.colours) roles[k] = "#" + data.colours[k]
                t.shell = roles
            } catch (e) {
                // half-written; the next change rewrites it
            }
        }
        onLoadFailed: t.shell = null
    }
}
