// Copyright (C) 2026 sbtl.dev. shtl is free software under the GNU GPL v3 or later; see LICENSE.
// shtl settings: look, behavior, stars (pinned apps), blueprints. Opens with Super+, (or the gear) while the
// panel is open; Esc closes. Every change is sent whole to Lua (shtl.apply_settings), which checks it,
// saves ~/.config/shtl/settings.json and publishes it back; this window only draws what Lua published.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import QtQuick.Shapes
import "Marks.js" as Marks

PanelWindow {
    id: win

    required property var theme
    readonly property var cfg: theme.st.settings ?? null
    property string tab: "look"
    readonly property string licenseName: "GNU General Public License v3"
    readonly property string licenseUrl: "https://www.gnu.org/licenses/gpl-3.0.html"

    visible: cfg !== null
    screen: Quickshell.screens.find(s => s.name === theme.st.monitor) ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shtl-settings"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: 1040
    implicitHeight: Math.min(900, (screen ? screen.height : 1080) - 120) // the Look tab is the tallest

    onVisibleChanged: if (!visible) editor.active = false

    // Settings travel whole: copy, change, send.
    function edit(change) {
        const c = JSON.parse(JSON.stringify(cfg))
        for (const k of ["presets", "apps", "keys", "slot_keys", "version"]) delete c[k]
        change(c)
        theme.lua("shtl.apply_settings(" + theme.luaString(JSON.stringify(c)) + ")")
    }
    function close() { theme.lua("shtl.close_settings()") }

    // Blueprint trees: a leaf is a slot (no `split`); a node splits its box side by side ("h") or stacked
    // ("v") at `ratio`. Boxes are fractions {x, y, w, h}; paths are lists of "a" / "b".
    function leaves(t, box, path, out) {
        box = box ?? { x: 0, y: 0, w: 1, h: 1 }
        path = path ?? []
        out = out ?? []
        if (!t || !t.split) {
            out.push({ box: box, path: path })
        } else if (t.split === "h") {
            const w = box.w * t.ratio
            leaves(t.a, { x: box.x, y: box.y, w: w, h: box.h }, path.concat("a"), out)
            leaves(t.b, { x: box.x + w, y: box.y, w: box.w - w, h: box.h }, path.concat("b"), out)
        } else {
            const hh = box.h * t.ratio
            leaves(t.a, { x: box.x, y: box.y, w: box.w, h: hh }, path.concat("a"), out)
            leaves(t.b, { x: box.x, y: box.y + hh, w: box.w, h: box.h - hh }, path.concat("b"), out)
        }
        return out
    }
    function dividers(t, box, path, out) {
        box = box ?? { x: 0, y: 0, w: 1, h: 1 }
        path = path ?? []
        out = out ?? []
        if (!t || !t.split) return out
        if (t.split === "h") {
            const w = box.w * t.ratio
            out.push({ split: "h", box: box, path: path, at: box.x + w })
            dividers(t.a, { x: box.x, y: box.y, w: w, h: box.h }, path.concat("a"), out)
            dividers(t.b, { x: box.x + w, y: box.y, w: box.w - w, h: box.h }, path.concat("b"), out)
        } else {
            const hh = box.h * t.ratio
            out.push({ split: "v", box: box, path: path, at: box.y + hh })
            dividers(t.a, { x: box.x, y: box.y, w: box.w, h: hh }, path.concat("a"), out)
            dividers(t.b, { x: box.x, y: box.y + hh, w: box.w, h: box.h - hh }, path.concat("b"), out)
        }
        return out
    }
    function clone(x) { return JSON.parse(JSON.stringify(x)) }
    function nodeAt(t, path) {
        let n = t
        for (const p of path) n = n[p]
        return n
    }
    function replaced(t, path, node) { // a copy of t with the node at path replaced
        if (path.length === 0) return node
        const c = clone(t)
        let parent = c
        for (const p of path.slice(0, -1)) parent = parent[p]
        parent[path[path.length - 1]] = node
        return c
    }

    // A small picture of a blueprint.
    component Wire: Item {
        id: wire
        property var tree
        property bool lit: false
        implicitWidth: 64
        implicitHeight: 36
        Repeater {
            model: win.leaves(wire.tree)
            Rectangle {
                required property var modelData
                x: modelData.box.x * wire.width + 1
                y: modelData.box.y * wire.height + 1
                width: modelData.box.w * wire.width - 2
                height: modelData.box.h * wire.height - 2
                radius: win.theme.rad(2)
                color: wire.lit ? win.theme.goldSoft : win.theme.panel
                border.color: wire.lit ? win.theme.gold : win.theme.line
            }
        }
    }

    component Button: Rectangle {
        id: btn
        property string label
        property bool primary: false
        property bool usable: true
        signal clicked
        implicitWidth: Math.max(96, btnText.implicitWidth + 32)
        implicitHeight: 34
        radius: win.theme.rad(9)
        opacity: usable ? 1 : 0.4
        color: primary ? win.theme.gold : btnArea.containsMouse && usable ? win.theme.panel : win.theme.bg
        border.color: primary ? win.theme.goldEdge : win.theme.line
        Behavior on color { ColorAnimation { duration: 100 } }
        T {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? win.theme.onGold : win.theme.fg
            font.pixelSize: 13
            font.weight: btn.primary ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.usable) btn.clicked()
        }
    }

    // A section heading in the form's voice: a title and what to do there
    component Heading: ColumnLayout {
        property string title
        property string help: ""
        property color helpColor: win.theme.muted
        spacing: 3
        T { text: parent.title; font.pixelSize: 14; font.weight: Font.Medium }
        T {
            visible: parent.help !== ""
            Layout.fillWidth: true
            text: parent.help
            color: parent.helpColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    component T: Text {
        color: win.theme.fg
        font.family: win.theme.sans
    }

    // A choice of a few: equal-width segments in one track, so every control has the same shape
    component Segmented: Rectangle {
        id: seg
        property var options: []        // [{ v, l }]
        property string value
        property real segmentWidth: 140
        signal picked(string v)
        implicitWidth: options.length * segmentWidth + 4
        implicitHeight: 34
        radius: win.theme.rad(9)
        color: win.theme.bg
        border.color: win.theme.line
        Row {
            anchors.fill: parent
            anchors.margins: 2
            Repeater {
                model: seg.options
                Rectangle {
                    id: segment
                    required property var modelData
                    readonly property bool on: seg.value === modelData.v
                    width: seg.segmentWidth
                    height: parent.height
                    radius: win.theme.rad(7)
                    color: on ? win.theme.goldSoft : segArea.containsMouse ? win.theme.panel : "transparent"
                    border.color: on ? win.theme.gold : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    T {
                        anchors.centerIn: parent
                        width: parent.width - 14
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: segment.modelData.l
                        color: segment.on ? win.theme.gold : win.theme.fg
                        font.pixelSize: 13
                        font.weight: segment.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: segArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(segment.modelData.v)
                    }
                }
            }
        }
    }

    // A palette or a starting point: a fixed-size tile with a strip of its colors
    component Tile: Rectangle {
        id: tile
        property string label
        property string detail: ""
        property var swatch: null
        property bool on: false
        signal clicked
        implicitWidth: 132
        implicitHeight: detail !== "" ? 76 : 58
        radius: win.theme.rad(9)
        color: on ? win.theme.goldSoft : tileArea.containsMouse ? win.theme.panel : win.theme.bg
        border.color: on ? win.theme.gold : win.theme.line
        border.width: on ? 2 : 1
        Behavior on color { ColorAnimation { duration: 100 } }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            T {
                Layout.fillWidth: true
                text: tile.label
                color: tile.on ? win.theme.gold : win.theme.fg
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            T {
                visible: tile.detail !== ""
                Layout.fillWidth: true
                text: tile.detail
                color: win.theme.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
            Row { // the palette, as a strip
                Layout.fillWidth: true
                visible: tile.swatch !== null
                Repeater {
                    model: tile.swatch ? ["card", "surface", "fg", "accent", "teal", "danger"] : []
                    Rectangle {
                        required property string modelData
                        width: (tile.width - 20) / 6
                        height: 6
                        color: tile.swatch[modelData]
                    }
                }
            }
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    // A vector mark (shtl, sbtl or GitHub) at any size. Parts: { d, dx, fill }; fill "fg" takes the theme's text
    // color (or `color`), anything else is used as is (the shuttle's flames).
    component Mark: Item {
        id: mark
        property var parts: Marks.shtl
        property var box: Marks.shtlBox
        property color color: win.theme.fg
        implicitHeight: 40
        implicitWidth: implicitHeight * box.w / box.h
        Repeater {
            model: mark.parts
            Shape {
                required property var modelData
                width: mark.box.w
                height: mark.box.h
                preferredRendererType: Shape.CurveRenderer
                transform: [
                    Translate { x: -mark.box.x + (modelData.dx ?? 0); y: -mark.box.y },
                    Scale { xScale: mark.width / mark.box.w; yScale: mark.height / mark.box.h }
                ]
                ShapePath {
                    fillColor: modelData.fill === "fg" ? mark.color : modelData.fill
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    PathSvg { path: modelData.d }
                }
            }
        }
    }

    // A mark that opens a link
    component LinkMark: Mark {
        id: link
        property string url
        color: linkArea.containsMouse ? win.theme.fg : win.theme.muted
        Behavior on color { ColorAnimation { duration: 120 } }
        MouseArea {
            id: linkArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["xdg-open", link.url])
        }
    }

    // A number with - and + (and typed), e.g. the panel's distance from its edge in pixels
    component Stepper: Row {
        id: stepper
        property int value: 0
        property int from: 0
        property int to: 600
        property string unit: "px"
        signal changed(int v)
        spacing: 6
        function set(v) { stepper.changed(Math.max(stepper.from, Math.min(stepper.to, v))) }
        Button { label: "−"; implicitWidth: 40; onClicked: stepper.set(stepper.value - 1) }
        Rectangle {
            width: 76
            height: 34
            radius: win.theme.rad(9)
            color: win.theme.bg
            border.color: numberInput.activeFocus ? win.theme.gold : win.theme.line
            TextInput {
                id: numberInput
                anchors.fill: parent
                anchors.rightMargin: 26
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                text: stepper.value
                color: win.theme.fg
                font.family: win.theme.sans
                font.pixelSize: 13
                validator: IntValidator { bottom: stepper.from; top: stepper.to }
                selectByMouse: true
                onEditingFinished: { stepper.set(parseInt(text) || 0); card.forceActiveFocus() }
            }
            T {
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: stepper.unit
                color: win.theme.muted
                font.pixelSize: 12
            }
        }
        Button { label: "+"; implicitWidth: 40; onClicked: stepper.set(stepper.value + 1) }
    }

    // One setting: name and what the current choice means on the left; the control on the right
    component OptionRow: RowLayout {
        id: row
        required property var modelData
        readonly property string value: win.cfg ? (win.cfg[modelData.key] ?? "") : ""
        readonly property var current: (modelData.options ?? []).find(o => o.v === value) ?? null
        Layout.fillWidth: true
        spacing: 24
        ColumnLayout {
            Layout.preferredWidth: 250
            Layout.maximumWidth: 250
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 6
            spacing: 3
            T {
                Layout.fillWidth: true
                text: row.modelData.title
                font.pixelSize: 14
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            T {
                Layout.fillWidth: true
                text: row.modelData.help ? row.modelData.help : row.current && row.current.d ? row.current.d : ""
                color: win.theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
        Stepper {
            visible: !!row.modelData.stepper
            Layout.alignment: Qt.AlignTop
            value: row.modelData.stepper && win.cfg ? (win.cfg[row.modelData.key] ?? 0) : 0
            onChanged: v => { const key = row.modelData.key; win.edit(c => c[key] = v) }
        }
        Segmented {
            visible: !row.modelData.tiles && !row.modelData.stepper
            Layout.alignment: Qt.AlignTop
            options: row.modelData.options ?? []
            value: row.value
            onPicked: v => { const key = row.modelData.key; win.edit(c => c[key] = v) }
        }
        Grid {
            visible: !!row.modelData.tiles
            Layout.alignment: Qt.AlignTop
            columns: 5
            spacing: 8
            Repeater {
                model: row.modelData.tiles ? row.modelData.options : []
                Tile {
                    required property var modelData
                    label: modelData.l
                    swatch: modelData.swatch ?? null
                    on: row.value === modelData.v
                    onClicked: { const key = row.modelData.key, v = modelData.v; win.edit(c => c[key] = v) }
                }
            }
        }
        Item { Layout.fillWidth: true }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: win.theme.rad(14)
        color: win.theme.card
        border.color: win.theme.line
        focus: true
        Keys.onEscapePressed: editor.active ? editor.active = false : win.close()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // Header: title, tabs, close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                T {
                    text: "shtl settings"
                    color: win.theme.fg
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    Layout.rightMargin: 12
                }
                Segmented {
                    segmentWidth: 116
                    options: [{ v: "look", l: "Look" }, { v: "behavior", l: "Behavior" },
                              { v: "starred", l: "Stars" }, { v: "blueprints", l: "Blueprints" },
                              { v: "about", l: "About" }]
                    value: win.tab
                    onPicked: v => { win.tab = v; editor.active = false }
                }
                Item { Layout.fillWidth: true }
                T {
                    text: "saved as you go · Esc closes"
                    color: win.theme.muted
                    font.pixelSize: 11
                }
                T {
                    text: "✕"
                    color: closeArea.containsMouse ? win.theme.gold : win.theme.muted
                    font.pixelSize: 15
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.close()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.theme.line }

            // Look -----------------------------------------------------------------------------------
            ColumnLayout {
                visible: win.tab === "look"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // starting points: several settings at once
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 24
                    ColumnLayout {
                        Layout.preferredWidth: 250
                        Layout.maximumWidth: 250
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 6
                        spacing: 3
                        T { text: "Start from"; font.pixelSize: 14; font.weight: Font.Medium }
                        T {
                            Layout.fillWidth: true
                            text: "Sets everything below at once; adjust from there."
                            color: win.theme.muted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                    Row {
                        spacing: 8
                        Repeater {
                            model: [
                                { l: "Frosted Catppuccin", d: "frosted, round, gradient edge", swatch: win.theme.palettes.catppuccin,
                                  set: { theme: "catppuccin", material: "frosted", shape: "round", edge: "gradient", typeface: "fira", density: "comfortable" } },
                                { l: "Gruvbox solid", d: "solid, soft, thin line", swatch: win.theme.palettes.gruvbox,
                                  set: { theme: "gruvbox", material: "solid", shape: "soft", edge: "line", typeface: "fira", density: "comfortable" } },
                                { l: "Terminal", d: "Tokyo Night, sharp, all mono, compact", swatch: win.theme.palettes.tokyonight,
                                  set: { theme: "tokyonight", material: "solid", shape: "sharp", edge: "line", typeface: "mono", density: "compact" } },
                                { l: "Match my desktop", d: "shell colors and font, Hyprland corners", swatch: null,
                                  set: { theme: "shell", material: "frosted", shape: "hyprland", edge: "gradient", typeface: "shell", density: "comfortable" } },
                            ]
                            Tile {
                                required property var modelData
                                implicitWidth: 168
                                label: modelData.l
                                detail: modelData.d
                                swatch: modelData.swatch
                                on: !!win.cfg && Object.keys(modelData.set).every(k => win.cfg[k] === modelData.set[k])
                                onClicked: { const set = modelData.set; win.edit(c => Object.assign(c, set)) }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.theme.line }

                Repeater {
                    model: [
                        { key: "theme", title: "Colors", tiles: true,
                          options: ["catppuccin", "tokyonight", "kanagawa", "rosepine", "gruvbox", "everforest", "nord", "dracula"]
                              .map(k => ({ v: k, l: win.theme.palettes[k].label, d: win.theme.palettes[k].label + ", built in", swatch: win.theme.palettes[k] }))
                              .concat([{ v: "shell", l: "Follow the shell", d: "Your desktop's palette (Caelestia); falls back where it'd be hard to read" }]) },
                        { key: "material", title: "Material",
                          options: [{ v: "solid", l: "Solid", d: "Opaque" },
                                    { v: "frosted", l: "Frosted", d: "The blurred desktop shows through" },
                                    { v: "glass", l: "Glass", d: "More see-through; best on calm wallpapers" }] },
                        { key: "shape", title: "Corners",
                          options: [{ v: "sharp", l: "Sharp", d: "Barely rounded" }, { v: "soft", l: "Soft", d: "Gently rounded" },
                                    { v: "round", l: "Round", d: "Very rounded" },
                                    { v: "hyprland", l: "Match Hyprland", d: "The same rounding as your windows" }] },
                        { key: "edge", title: "Edge",
                          options: [{ v: "line", l: "Thin line", d: "A quiet outline" },
                                    { v: "gradient", l: "Gradient", d: "The palette's two tones around the edge" },
                                    { v: "none", l: "None", d: "Just the surface" }] },
                        { key: "typeface", title: "Type",
                          options: [{ v: "fira", l: "Fira Sans", d: "shtl's own" },
                                    { v: "shell", l: "Shell font", d: "Whatever your shell uses (Rubik for Caelestia)" },
                                    { v: "mono", l: "All mono", d: "Monospace everywhere, like a terminal" }] },
                        { key: "panel_position", title: "Position",
                          options: [{ v: "top", l: "Top", d: "Drops down from the top of the screen" },
                                    { v: "center", l: "Center", d: "In the middle of the screen" },
                                    { v: "bottom", l: "Bottom", d: "Rises from the bottom of the screen" }] },
                        { key: "panel_offset", title: "Distance from the edge", stepper: true,
                          help: "Make room for a bar or dock, to the pixel" },
                        { key: "density", title: "Density",
                          options: [{ v: "comfortable", l: "Comfortable", d: "Room to breathe" }, { v: "compact", l: "Compact", d: "Tighter spacing, a shorter panel" }] },
                    ]
                    OptionRow { visible: !(modelData.key === "panel_offset" && win.cfg && win.cfg.panel_position === "center") }
                }
                Item { Layout.fillHeight: true }
            }

            // About ----------------------------------------------------------------------------------
            ColumnLayout {
                visible: win.tab === "about"
                Layout.fillWidth: true
                Layout.preferredWidth: card.width - 36
                Layout.fillHeight: true
                spacing: 10

                Item { Layout.fillHeight: true }
                Mark {
                    Layout.alignment: Qt.AlignHCenter
                    implicitHeight: 96
                }
                T {
                    Layout.alignment: Qt.AlignHCenter
                    text: "v" + (win.cfg ? win.cfg.version : "")
                    color: win.theme.muted
                    font.pixelSize: 13
                }
                T {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    text: "Keyboard-first window placement for Hyprland."
                    color: win.theme.fg
                    font.pixelSize: 14
                }
                Item { Layout.fillHeight: true }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 22
                    LinkMark {
                        implicitHeight: 24
                        parts: [{ d: Marks.github, dx: 0, fill: "fg" }]
                        box: ({ x: 0, y: 0, w: 24, h: 24 })
                        url: "https://github.com/thesubtleties/shtl"
                    }
                    LinkMark {
                        implicitHeight: 22
                        parts: Marks.sbtl
                        box: Marks.box
                        url: "https://sbtl.dev?utm_source=shtl&utm_medium=about"
                    }
                }
                T {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 6
                    text: "shtl is free and open source software, licensed under the "
                        + "<a href=\"" + win.licenseUrl + "\">" + win.licenseName + "</a>."
                    textFormat: Text.StyledText
                    linkColor: win.theme.gold
                    color: win.theme.muted
                    font.pixelSize: 12
                    onLinkActivated: link => Quickshell.execDetached(["xdg-open", link])
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }

            // Behavior ------------------------------------------------------------------------------
            ColumnLayout {
                visible: win.tab === "behavior"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                Repeater {
                    model: [
                        { key: "trigger", title: "Open shtl with",
                          options: [{ v: "combo", l: "Key combo", d: (win.cfg ? win.cfg.trigger_combo : "SUPER + space") + " opens and closes the panel. Nothing else to install." },
                                    { v: "hold", l: "Hold Space", d: "Hold Space for the panel, tap it for a space. Needs keyd (runs as root); see the README." },
                                    { v: "firmware", l: "Keyboard key", d: "Your keyboard sends " + (win.cfg ? win.cfg.trigger_firmware : "F13") + " while you hold a key (Wooting, QMK, ZMK)." }] },
                        { key: "hints", title: "Key hints in the panel",
                          options: [{ v: "show", l: "Show", d: "While you learn the keys" },
                                    { v: "hide", l: "Hide", d: "Once you know them" }] },
                        { key: "labels", title: "Section labels",
                          options: [{ v: "show", l: "Show", d: "Workspaces, Constellations, Apps, On this workspace" },
                                    { v: "hide", l: "Hide", d: "The layout speaks for itself" }] },
                        { key: "panel_mode", title: "Letting go of Space",
                          options: [{ v: "sticky", l: "Sticky", d: "The panel stays open; Space or Esc closes it" },
                                    { v: "auto", l: "Auto", d: "Stays open only if you pressed nothing" },
                                    { v: "hold", l: "Hold", d: "The panel closes" }] },
                        { key: "tap_takes", title: "Tap on an app key or picker label",
                          options: [{ v: "steal", l: "Steals", d: "Double-tap borrows instead" },
                                    { v: "borrow", l: "Borrows", d: "Double-tap steals instead" }] },
                        { key: "steal_mode", title: "Stealing a window that's lent out",
                          options: [{ v: "full", l: "Full", d: "Here becomes its only place" },
                                    { v: "copy", l: "Copy", d: "Take just the copy you took it from" }] },
                        { key: "yield_return", title: "Getting a lent window back",
                          options: [{ v: "top", l: "Back on top", d: "Unless you changed that slot's top meanwhile" },
                                    { v: "stay", l: "Stays put", d: "Wherever it was in the stack" }] },
                        { key: "constellation_windows", title: "Windows a recalled constellation uses",
                          options: [{ v: "share", l: "Share", d: "Reuse open windows; launch only if there are none" },
                                    { v: "own", l: "Own", d: "Only its own windows; otherwise launch new ones" }] },
                    ]
                    OptionRow {}
                }
                Item { Layout.fillHeight: true }
            }

            // Stars (pinned apps) -------------------------------------------------------------------
            ColumnLayout {
                id: starredTab
                visible: win.tab === "starred"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                property string picking: "" // key waiting for an app from the list below

                function starOn(key) {
                    for (const f of (win.cfg ? win.cfg.starred : [])) if (f.key === key) return f
                    return null
                }

                Heading {
                    Layout.fillWidth: true
                    title: "Pool keys"
                    help: "A star is an app pinned to its key (run or raise). Free keys fill with your most recent apps. Click a key to choose its app."
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    rowSpacing: 8
                    columnSpacing: 8
                    Repeater {
                        model: win.cfg ? win.cfg.keys : []
                        Rectangle {
                            id: keyCard
                            required property var modelData
                            readonly property var fav: starredTab.starOn(modelData.key)
                            readonly property bool picking: starredTab.picking === modelData.key
                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: win.theme.rad(9)
                            color: picking ? win.theme.goldSoft : win.theme.panel
                            border.color: picking ? win.theme.gold : win.theme.line

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: starredTab.picking = keyCard.picking ? "" : keyCard.modelData.key
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 4
                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: win.theme.rad(5)
                                        color: keyCard.fav ? win.theme.gold : win.theme.bg
                                        border.color: win.theme.line
                                        T {
                                            anchors.centerIn: parent
                                            text: keyCard.modelData.label
                                            color: keyCard.fav ? win.theme.onGold : win.theme.fg
                                            font.family: win.theme.mono
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    T {
                                        Layout.fillWidth: true
                                        text: keyCard.fav ? "★ " + keyCard.fav.class.split(".").pop()
                                            : keyCard.picking ? "pick an app below" : "free"
                                        color: keyCard.fav ? win.theme.fg : win.theme.muted
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    T {
                                        visible: !!keyCard.fav
                                        text: "✕"
                                        color: unstarArea.containsMouse ? win.theme.red : win.theme.muted
                                        font.pixelSize: 12
                                        MouseArea {
                                            id: unstarArea
                                            anchors.fill: parent
                                            anchors.margins: -5
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const key = keyCard.modelData.key
                                                win.edit(c => c.starred = c.starred.filter(f => f.key !== key))
                                            }
                                        }
                                    }
                                }
                                // launch command, editable
                                Rectangle {
                                    visible: !!keyCard.fav
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: win.theme.rad(5)
                                    color: win.theme.bg
                                    border.color: cmdInput.activeFocus ? win.theme.gold : win.theme.line
                                    TextInput {
                                        id: cmdInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: keyCard.fav ? (keyCard.fav.cmd ?? "") : ""
                                        color: win.theme.fg
                                        font.family: win.theme.mono
                                        font.pixelSize: 11
                                        clip: true
                                        selectByMouse: true
                                        // show the start of a long command unless you're editing it
                                        onTextChanged: if (!activeFocus) cursorPosition = 0
                                        onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                        Component.onCompleted: cursorPosition = 0
                                        onEditingFinished: {
                                            const key = keyCard.modelData.key, cmd = text
                                            if (keyCard.fav && cmd !== (keyCard.fav.cmd ?? ""))
                                                win.edit(c => { for (const f of c.starred) if (f.key === key) f.cmd = cmd })
                                            card.forceActiveFocus()
                                        }
                                    }
                                    T {
                                        visible: cmdInput.text === "" && !cmdInput.activeFocus
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 6
                                        text: "launch command"
                                        color: win.theme.muted
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }

                Heading {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    title: "Open apps"
                    help: starredTab.picking !== "" ? "Click one to star it on " + starredTab.picking + "." : "Pick a key above first."
                    helpColor: starredTab.picking !== "" ? win.theme.gold : win.theme.muted
                }
                Grid {
                    columns: 5
                    spacing: 8
                    Repeater {
                        model: win.cfg ? win.cfg.apps : []
                        Tile {
                            required property var modelData
                            implicitWidth: (starredTab.width - 32) / 5
                            label: modelData.name
                            detail: modelData.cmd
                            opacity: starredTab.picking !== "" ? 1 : 0.45
                            onClicked: if (starredTab.picking !== "") {
                                const key = starredTab.picking, app = modelData
                                win.edit(c => {
                                    c.starred = c.starred.filter(f => f.key !== key && f.class !== app.class)
                                    c.starred.push({ key: key, class: app.class, cmd: app.cmd })
                                })
                                starredTab.picking = ""
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // Blueprints -----------------------------------------------------------------------------
            RowLayout {
                visible: win.tab === "blueprints"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // The G cycle, in order: drag to reorder
                ColumnLayout {
                    Layout.preferredWidth: 380
                    Layout.fillHeight: true
                    spacing: 6

                    Heading {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        title: "G cycles through"
                        help: "In this order. Drag to reorder."
                    }
                    QtObject { id: bpDrag; property int from: -1; property int to: -1 }
                    Repeater {
                        id: cycleRep
                        model: win.cfg ? win.cfg.blueprints : []
                        Rectangle {
                            id: bpRow
                            required property var modelData
                            required property int index
                            readonly property bool target: bpDrag.from >= 0 && bpDrag.to === index && bpDrag.from !== index
                            Layout.fillWidth: true
                            implicitHeight: 50
                            radius: win.theme.rad(8)
                            opacity: bpDrag.from === index ? 0.4 : 1
                            color: target || (editor.active && editor.index === index) ? win.theme.goldSoft : win.theme.panel
                            border.color: target || (editor.active && editor.index === index) ? win.theme.gold : win.theme.line

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: bpDrag.from >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                onPressed: { bpDrag.from = bpRow.index; bpDrag.to = bpRow.index }
                                onPositionChanged: function(mouse) {
                                    const y = mapToItem(bpRow.parent, 0, mouse.y).y
                                    for (let i = 0; i < cycleRep.count; i++) {
                                        const it = cycleRep.itemAt(i)
                                        if (y >= it.y && y < it.y + it.height) bpDrag.to = i
                                    }
                                }
                                onReleased: {
                                    const from = bpDrag.from, to = bpDrag.to
                                    bpDrag.from = -1
                                    bpDrag.to = -1
                                    if (from >= 0 && to !== from)
                                        win.edit(c => c.blueprints.splice(to, 0, c.blueprints.splice(from, 1)[0]))
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                T {
                                    text: bpRow.index + 1
                                    color: win.theme.muted
                                    font.family: win.theme.mono
                                    font.pixelSize: 12
                                }
                                Wire { tree: bpRow.modelData.tree }
                                T {
                                    Layout.fillWidth: true
                                    text: bpRow.modelData.name
                                    color: win.theme.fg
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                T {
                                    text: "edit"
                                    color: editArea.containsMouse ? win.theme.gold : win.theme.muted
                                    font.pixelSize: 12
                                    MouseArea {
                                        id: editArea
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: editor.open(bpRow.index, bpRow.modelData.name, bpRow.modelData.tree)
                                    }
                                }
                                T {
                                    visible: win.cfg && win.cfg.blueprints.length > 1
                                    text: "✕"
                                    color: removeArea.containsMouse ? win.theme.red : win.theme.muted
                                    font.pixelSize: 12
                                    MouseArea {
                                        id: removeArea
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const i = bpRow.index
                                            if (editor.active && editor.index === i) editor.active = false
                                            win.edit(c => c.blueprints.splice(i, 1))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: win.theme.line }

                // Library (or the editor)
                ColumnLayout {
                    visible: !editor.active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        Heading {
                            Layout.fillWidth: true
                            title: "Library"
                            help: "Click a shape to add it to G, or draw your own."
                        }
                        Button {
                            label: "New blueprint"
                            onClicked: editor.open(-1, "my blueprint", {})
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8
                        Repeater {
                            model: win.cfg ? win.cfg.presets : []
                            Rectangle {
                                id: preset
                                required property var modelData
                                readonly property bool added: !!win.cfg && win.cfg.blueprints.some(b => b.name === modelData.name)
                                Layout.fillWidth: true
                                implicitHeight: 92
                                radius: win.theme.rad(9)
                                color: presetArea.containsMouse && !added ? win.theme.goldSoft : win.theme.panel
                                border.color: presetArea.containsMouse && !added ? win.theme.gold : win.theme.line
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Wire {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 96
                                        implicitHeight: 48
                                        tree: preset.modelData.tree
                                        lit: preset.added
                                    }
                                    T {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: preset.modelData.name + (preset.added ? "  ✓" : "")
                                        color: preset.added ? win.theme.gold : win.theme.fg
                                        font.pixelSize: 12
                                    }
                                }
                                MouseArea {
                                    id: presetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: preset.added ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: if (!preset.added) {
                                        const b = { name: preset.modelData.name, tree: preset.modelData.tree }
                                        win.edit(c => c.blueprints.push(b))
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // Editor: click a slot to select it; split it, remove it, drag the dividers.
                ColumnLayout {
                    id: editor
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    property bool active: false
                    property int index: -1      // position in the G list, -1 = new
                    property var tree: ({})
                    property var selected: []   // path of the selected slot
                    property string error: ""
                    readonly property var slots: win.leaves(tree)
                    readonly property var lines: win.dividers(tree)

                    function open(i, name, t) {
                        index = i
                        tree = win.clone(t)
                        selected = []
                        error = ""
                        nameInput.text = name
                        active = true
                    }
                    function isSelected(path) { return JSON.stringify(path) === JSON.stringify(selected) }
                    function split(dir) {
                        if (slots.length >= 4) return
                        tree = win.replaced(tree, selected, { split: dir, ratio: 0.5, a: {}, b: {} })
                        selected = selected.concat("a")
                    }
                    function removeSelected() {
                        if (selected.length === 0) return
                        const parent = selected.slice(0, -1)
                        const other = selected[selected.length - 1] === "a" ? "b" : "a"
                        tree = win.replaced(tree, parent, win.clone(win.nodeAt(tree, parent)[other]))
                        selected = []
                    }
                    function save() {
                        const name = nameInput.text.trim()
                        if (name === "") { error = "give it a name"; return }
                        const clash = win.cfg.blueprints.findIndex(b => b.name === name)
                        if (clash >= 0 && clash !== index) { error = "a blueprint called " + name + " already exists"; return }
                        const b = { name: name, tree: tree }, i = index
                        win.edit(c => { if (i >= 0) c.blueprints[i] = b; else c.blueprints.push(b) })
                        active = false
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        T {
                            text: editor.index >= 0 ? "Edit blueprint" : "New blueprint"
                            color: win.theme.muted
                            font.pixelSize: 12
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: win.theme.rad(6)
                            color: win.theme.bg
                            border.color: nameInput.activeFocus ? win.theme.gold : win.theme.line
                            TextInput {
                                id: nameInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: win.theme.fg
                                font.pixelSize: 13
                                selectByMouse: true
                                clip: true
                                onAccepted: card.forceActiveFocus()
                            }
                        }
                    }

                    // the canvas, in the screen's shape
                    Item {
                        id: canvas
                        Layout.fillWidth: true
                        Layout.preferredHeight: width / (win.theme.st.aspect || 16 / 9)

                        Repeater {
                            model: editor.slots
                            Rectangle {
                                id: slotRect
                                required property var modelData
                                required property int index
                                readonly property bool sel: editor.isSelected(modelData.path)
                                x: modelData.box.x * canvas.width + 3
                                y: modelData.box.y * canvas.height + 3
                                width: modelData.box.w * canvas.width - 6
                                height: modelData.box.h * canvas.height - 6
                                radius: win.theme.rad(8)
                                color: sel ? win.theme.goldSoft : win.theme.panel
                                border.color: sel ? win.theme.gold : win.theme.line
                                border.width: sel ? 2 : 1
                                T {
                                    anchors.centerIn: parent
                                    text: (win.cfg && win.cfg.slot_keys[slotRect.index]) || ""
                                    color: slotRect.sel ? win.theme.gold : win.theme.muted
                                    font.family: win.theme.mono
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        Repeater { // dividers (drawn here; the canvas MouseArea below drags them)
                            model: editor.lines
                            Rectangle {
                                id: divider
                                required property var modelData
                                readonly property bool across: modelData.split === "h" // a vertical line
                                x: across ? modelData.at * canvas.width - 4 : modelData.box.x * canvas.width
                                y: across ? modelData.box.y * canvas.height : modelData.at * canvas.height - 4
                                width: across ? 8 : modelData.box.w * canvas.width
                                height: across ? modelData.box.h * canvas.height : 8
                                color: canvasMouse.hovered === modelData.path.join("") + modelData.split ? win.theme.gold : "transparent"
                                opacity: 0.8
                                radius: win.theme.rad(3)
                            }
                        }

                        // One handler for the whole canvas: every change redraws the slots and dividers, so a
                        // handler living on a divider would be destroyed mid-drag.
                        MouseArea {
                            id: canvasMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            property var dragging: null // { path, box, split } of the divider being dragged
                            property string hovered: ""  // the divider under the pointer (path + split)
                            cursorShape: dragging || hovered !== ""
                                ? ((dragging ? dragging.split : hovered.slice(-1)) === "h" ? Qt.SplitHCursor : Qt.SplitVCursor)
                                : Qt.PointingHandCursor

                            function dividerAt(mx, my) {
                                const W = canvas.width, H = canvas.height
                                for (const d of editor.lines) {
                                    const b = d.box
                                    if (d.split === "h" && Math.abs(mx - d.at * W) < 7 && my >= b.y * H && my <= (b.y + b.h) * H) return d
                                    if (d.split === "v" && Math.abs(my - d.at * H) < 7 && mx >= b.x * W && mx <= (b.x + b.w) * W) return d
                                }
                                return null
                            }
                            onPressed: function(mouse) {
                                const d = dividerAt(mouse.x, mouse.y)
                                if (d) {
                                    dragging = { path: d.path, box: d.box, split: d.split }
                                    return
                                }
                                for (const sl of editor.slots) {
                                    const b = sl.box
                                    if (mouse.x >= b.x * canvas.width && mouse.x < (b.x + b.w) * canvas.width
                                        && mouse.y >= b.y * canvas.height && mouse.y < (b.y + b.h) * canvas.height)
                                        editor.selected = sl.path
                                }
                            }
                            onReleased: dragging = null
                            onPositionChanged: function(mouse) {
                                if (!dragging) {
                                    const d = dividerAt(mouse.x, mouse.y)
                                    hovered = d ? d.path.join("") + d.split : ""
                                    return
                                }
                                const b = dragging.box
                                let r = dragging.split === "h" ? (mouse.x / canvas.width - b.x) / b.w : (mouse.y / canvas.height - b.y) / b.h
                                r = Math.max(0.1, Math.min(0.9, r))
                                for (const snap of [1 / 4, 1 / 3, 1 / 2, 2 / 3, 3 / 4])
                                    if (Math.abs(r - snap) < 0.02) r = snap
                                const node = win.clone(win.nodeAt(editor.tree, dragging.path))
                                node.ratio = r
                                editor.tree = win.replaced(editor.tree, dragging.path, node)
                                hovered = dragging.path.join("") + dragging.split
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            label: "Split side by side"
                            usable: editor.slots.length < 4
                            onClicked: editor.split("h")
                        }
                        Button {
                            label: "Split stacked"
                            usable: editor.slots.length < 4
                            onClicked: editor.split("v")
                        }
                        Button {
                            label: "Remove slot"
                            usable: editor.selected.length > 0
                            onClicked: editor.removeSelected()
                        }
                        T {
                            text: editor.error !== "" ? editor.error
                                : editor.slots.length >= 4 ? "Four slots is the most (A S D F)."
                                : "Click a slot, then split it. Drag a divider to resize."
                            color: editor.error !== "" ? win.theme.red : win.theme.muted
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Button {
                            label: "Cancel"
                            onClicked: editor.active = false
                        }
                        Button {
                            label: editor.index >= 0 ? "Save" : "Add to G"
                            primary: true
                            onClicked: editor.save()
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
