// Copyright (C) 2026 sbtl.dev. shtl is free software under the GNU GPL v3 or later; see LICENSE.
// shtl panel (display only): drops from the top while Space is held or the panel is sticky.
// Hyprland still handles the keys (hypr/shtl.lua); this draws the state it publishes.
// Run: qs -n -p <shtl>/panel (shtl-start does this)

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var st: ({ mode: "closed" })
    readonly property bool open: st.mode === "held" || st.mode === "sticky"

    // Colors come from Theme.qml (shtl's own, or the shell's palette; setting `theme`)
    Theme { id: theme; mode: root.st.theme ?? "catppuccin"; look: root.st.look ?? ({}) }
    function rad(n) { return Math.max(1, Math.round(n * theme.radiusScale)) } // corners follow the shape setting
    readonly property bool compact: theme.compact
    readonly property var palettes: theme.palettes
    readonly property color bg: theme.bg
    readonly property color card: theme.card
    readonly property color panel: theme.surface
    readonly property color line: theme.line
    readonly property color edge: theme.edge
    readonly property color fg: theme.fg
    readonly property color muted: theme.muted
    readonly property color gold: theme.accent         // "gold" = the accent, whatever color it is
    readonly property color goldSoft: theme.accentSoft
    readonly property color goldEdge: theme.accentEdge
    readonly property color onGold: theme.onAccent
    readonly property color teal: theme.teal
    readonly property color red: theme.danger
    readonly property color redSoft: theme.dangerSoft
    readonly property color slotIdle: theme.slotIdle
    readonly property color placeholderBg: theme.placeholderBg
    readonly property color placeholderEdge: theme.placeholderEdge
    readonly property color capFace: theme.capFace
    readonly property color capLip: theme.capLip

    function lua(code) { Quickshell.execDetached(["hyprctl", "eval", code]) }
    // Any text as a Lua long string, with a bracket level that doesn't occur in it.
    function luaString(text) {
        let eq = "="
        while (text.indexOf("]" + eq + "]") >= 0) eq += "="
        return "[" + eq + "[" + text + "]" + eq + "]"
    }
    // The carried window's border wears the accent; Lua doesn't know the palette, so tell it (again
    // after a config reload, which forgets it).
    function sendAccent() { lua("shtl.set_accent(\"" + gold.toString() + "\")") }
    onGoldChanged: sendAccent()
    readonly property bool accentNeeded: st.accent_needed ?? false
    onAccentNeededChanged: if (accentNeeded) sendAccent()
    readonly property string mono: "JetBrainsMono NF"      // keycap legends only
    readonly property string sans: theme.sans
    readonly property string condensed: theme.condensed

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shtl-state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.st = JSON.parse(text());
            } catch (e) {
                // half-written file; the next change rewrites it
            }
        }
    }

    component Keycap: Item {
        id: cap
        property string label
        property bool lit: false
        implicitWidth: Math.max(24, capText.implicitWidth + 12)
        implicitHeight: 24
        Rectangle { // the lip under the face
            anchors.fill: parent
            radius: root.rad(6)
            color: cap.lit ? root.goldEdge : root.capLip
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle { // the face; pressed down when lit
            width: parent.width
            height: parent.height - (cap.lit ? 1 : 3)
            y: cap.lit ? 1 : 0
            radius: root.rad(6)
            color: cap.lit ? root.gold : root.capFace
            border.color: cap.lit ? root.goldEdge : root.line
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on y { NumberAnimation { duration: 90 } }
            T {
                id: capText
                anchors.centerIn: parent
                text: cap.label
                color: cap.lit ? root.onGold : root.fg
                font.family: root.mono
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }

    component T: Text {
        color: root.fg
        font.family: root.sans
    }

    component Muted: T {
        color: root.muted
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    component SectionLabel: T { // hidden with the `labels` setting (pickers set visible themselves)
        visible: root.st.labels !== false
        color: root.muted
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    // Placeholders: a quiet card in each slot whose window a constellation has borrowed. One click-through layer
    // per screen, under the windows (above the wallpaper), so it only shows where the slot is empty.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: holder
            required property var modelData
            readonly property var mine: (root.st.placeholders ?? []).filter(p => p.monitor === modelData.name)

            screen: modelData
            visible: mine.length > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "shtl-placeholder"
            WlrLayershell.keyboardFocus: root.st.renaming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}

            Repeater {
                model: holder.mine

                Rectangle {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    radius: root.rad(12)
                    color: root.placeholderBg
                    border.color: root.placeholderEdge
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        T {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.class
                            color: root.fg
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                        }
                        T {
                            Layout.alignment: Qt.AlignHCenter
                            text: "→ in " + modelData.at
                            color: root.gold
                            font.family: root.condensed
                            font.pixelSize: 14
                        }
                        T {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Enter brings it here"
                            color: root.muted
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // Where a carried window would land: an outline over that slot, on whichever screen it's on.
    // Above the windows but click-through, so the click that puts it down still reaches shtl.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dropping
            required property var modelData
            readonly property var target: root.st.carry_target && root.st.carry_target.monitor === modelData.name
                                          ? root.st.carry_target : null

            screen: modelData
            visible: target !== null
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shtl-drop"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}

            Rectangle {
                visible: dropping.target !== null
                x: dropping.target ? dropping.target.x : 0
                y: dropping.target ? dropping.target.y : 0
                width: dropping.target ? dropping.target.w : 0
                height: dropping.target ? dropping.target.h : 0
                radius: root.rad(12)
                color: Qt.rgba(root.gold.r, root.gold.g, root.gold.b, 0.12)
                border.color: root.gold
                border.width: 3

                Rectangle {
                    anchors.centerIn: parent
                    width: dropLabel.implicitWidth + 28
                    height: dropLabel.implicitHeight + 14
                    radius: root.rad(9)
                    color: root.card
                    border.color: root.gold
                    T {
                        id: dropLabel
                        anchors.centerIn: parent
                        text: dropping.target ? dropping.target.class + " → " + dropping.target.slot
                                                + (dropping.target.at !== "" ? " on " + dropping.target.at : "") : ""
                        color: root.fg
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    Settings { theme: root }

    PanelWindow {
        id: win

        screen: Quickshell.screens.find(s => s.name === root.st.monitor) ?? Quickshell.screens[0]
        visible: root.open || content.opacity > 0
        // Settings → Look → Position: the top or bottom edge (with an offset for bars and docks), or centered
        readonly property string edge: root.st.position ? root.st.position.edge : "top"
        readonly property int offset: root.st.position ? root.st.position.offset : 10
        anchors.top: edge === "top"
        anchors.bottom: edge === "bottom"
        margins.top: edge === "top" ? offset : 0
        margins.bottom: edge === "bottom" ? offset : 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shtl"
        WlrLayershell.keyboardFocus: root.st.renaming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: 1000
        implicitHeight: content.implicitHeight + 40 // room for the slide

        Rectangle {
            id: content

            x: 0
            // slides in from its edge (down from the top, up from the bottom); fades in the center
            y: win.edge === "bottom" ? win.height - height + (root.open ? 0 : 14)
             : win.edge === "center" ? (win.height - height) / 2
             : (root.open ? 0 : -14)
            width: parent.width
            implicitHeight: column.implicitHeight + (root.compact ? 20 : 28)
            height: implicitHeight
            clip: true
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            opacity: root.open ? 1 : 0
            radius: root.rad(12)
            color: root.card
            border.color: theme.edgeStyle === "line" ? root.line : "transparent"

            Shape { // edge "gradient": the palette's two tones around the card
                visible: theme.edgeStyle === "gradient"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: 0; x2: content.width; y2: content.height
                        GradientStop { position: 0; color: root.gold }
                        GradientStop { position: 1; color: root.teal }
                    }
                    PathRectangle {
                        x: 0.75; y: 0.75
                        width: content.width - 1.5; height: content.height - 1.5
                        radius: root.rad(12)
                    }
                }
            }

            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: column
                anchors.fill: parent
                anchors.margins: root.compact ? 10 : 14
                spacing: root.compact ? 8 : 12

                // Header: this screen's workspaces (Z X C V B) on the left, screens (Q) and settings on the right
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Workspaces: Z X C V jump, Tab kicks back
                    RowLayout {
                        Layout.fillWidth: false
                        spacing: 6

                        QtObject { id: wsDrag; property int from: -1; property int to: -1 }
                        Repeater {
                            id: wsRep
                            model: root.st.workspaces ?? []
                            Rectangle {
                                id: wsChip
                                required property var modelData
                                required property int index
                                readonly property bool target: wsDrag.from >= 0 && wsDrag.to === index && wsDrag.from !== index
                                Layout.fillWidth: false
                                implicitWidth: 68 // the same for every chip, so nothing shifts as windows come and go
                                implicitHeight: 32
                                radius: root.rad(7)
                                opacity: wsDrag.from === index ? 0.4 : 1
                                color: modelData.active || target ? root.goldSoft : root.panel
                                border.color: modelData.active || target ? root.gold : root.line
                                Behavior on color { ColorAnimation { duration: 120 } }

                                // Drag onto another workspace to swap their windows.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: wsDrag.from >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    onPressed: {
                                        wsDrag.from = wsChip.index
                                        wsDrag.to = wsChip.index
                                    }
                                    onPositionChanged: function(mouse) {
                                        const x = mapToItem(wsChip.parent, mouse.x, 0).x
                                        for (let i = 0; i < wsRep.count; i++) {
                                            const it = wsRep.itemAt(i)
                                            if (x >= it.x && x < it.x + it.width) wsDrag.to = i
                                        }
                                    }
                                    onReleased: {
                                        if (wsDrag.to !== wsDrag.from) {
                                            const ws = root.st.workspaces
                                            Quickshell.execDetached(["hyprctl", "eval",
                                                "shtl.drag_workspace('" + ws[wsDrag.from].name + "','" + ws[wsDrag.to].name + "')"])
                                        }
                                        wsDrag.from = -1
                                        wsDrag.to = -1
                                    }
                                }
                                RowLayout {
                                    id: wsRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 5
                                    spacing: 5
                                    Keycap { label: modelData.key; lit: modelData.active }
                                    ColumnLayout {
                                        spacing: 2
                                        T {
                                            text: modelData.name
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                        }
                                        Row { // one dot per window; lent-away ones in the second tone
                                            spacing: 2
                                            Repeater {
                                                model: Math.min(wsChip.modelData.windows, 4)
                                                Rectangle {
                                                    required property int index
                                                    width: 4
                                                    height: 4
                                                    radius: root.rad(2)
                                                    color: index >= wsChip.modelData.windows - wsChip.modelData.away ? root.teal : root.muted
                                                }
                                            }
                                        T {
                                            visible: wsChip.modelData.windows > 4
                                            text: "+"
                                            color: root.muted
                                            font.pixelSize: 8
                                            height: 4
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        }
                                    }
                                }
                                Rectangle { // where Tab goes: a little tab on the chip's top edge
                                    visible: root.st.kick === wsChip.modelData.name
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: -6
                                    width: tabText.implicitWidth + 8
                                    height: 12
                                    radius: root.rad(3)
                                    color: root.gold
                                    Text {
                                        id: tabText
                                        anchors.centerIn: parent
                                        text: "Tab"
                                        color: root.onGold
                                        font.family: root.mono
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                    // The aimed screen (Q goes there, Shift+Q aims at the next): its name and five
                    // workspaces, the one it shows lit. E / R flip it, W swaps with it.
                    Keycap {
                        visible: !!root.st.aim
                        label: "Q"
                    }
                    Muted {
                        visible: !!root.st.aim
                        text: "→ " + (root.st.aim ? root.st.aim.name : "")
                        font.pixelSize: 11
                    }
                    Keycap {
                        visible: !!root.st.aim
                        label: "E"
                    }
                    Row {
                        visible: !!root.st.aim
                        spacing: 3
                        Repeater {
                            model: root.st.aim ? root.st.aim.workspaces : []
                            Rectangle {
                                required property var modelData
                                width: 22
                                height: 22
                                radius: root.rad(5)
                                color: modelData.showing ? root.goldSoft : root.panel
                                border.color: modelData.showing ? root.gold : root.line
                                T {
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: modelData.showing || modelData.used ? root.fg : root.muted
                                    font.pixelSize: 11
                                    font.weight: modelData.showing ? Font.DemiBold : Font.Normal
                                }
                            }
                        }
                    }
                    Keycap {
                        visible: !!root.st.aim
                        label: "R"
                    }
                    T { // settings (also Super+,)
                        text: "⚙"
                        color: gearArea.containsMouse ? root.gold : root.muted
                        font.pixelSize: 15
                        MouseArea {
                            id: gearArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.lua("shtl.open_settings()")
                        }
                    }
                }

                // Not a shtl workspace yet
                T {
                    visible: !root.st.managed
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    text: "This is a special workspace (like a scratchpad); shtl arranges your normal workspaces."
                    color: root.muted
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }

                // Body, two rows. Top: the slots | windows here (or a picker). Bottom: constellations | apps.
                ColumnLayout {
                    visible: !!root.st.managed
                    Layout.fillWidth: true
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                    // Left hand, top: the slots (A S D F) and their blueprint (G)
                    ColumnLayout {
                        Layout.preferredWidth: 430
                        Layout.minimumWidth: 430
                        Layout.maximumWidth: 430
                        Layout.alignment: Qt.AlignTop
                        spacing: 10

                    Rectangle {
                        id: wire
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(150, Math.min(260, 430 / (root.st.aspect || 1.78)))
                        radius: root.rad(8)
                        color: root.bg
                        border.color: root.line

                        Repeater {
                            model: root.st.slots ?? []

                            Rectangle {
                                id: slot
                                required property var modelData
                                required property int index
                                readonly property bool selected: index + 1 === root.st.sel

                                x: 6 + modelData.x * (wire.width - 12) + 3
                                y: 6 + modelData.y * (wire.height - 12) + 3
                                width: modelData.w * (wire.width - 12) - 6
                                height: modelData.h * (wire.height - 12) - 6
                                radius: root.rad(6)
                                color: selected ? root.goldSoft : root.slotIdle
                                border.color: selected ? root.gold : root.edge
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                border.width: selected ? 2 : 1

                                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 12
                                    spacing: 4

                                    Keycap {
                                        Layout.alignment: Qt.AlignHCenter
                                        label: slot.modelData.key
                                        lit: slot.selected
                                    }
                                    T {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: slot.modelData.window ? slot.modelData.window.class : "empty"
                                        color: slot.modelData.window ? root.fg : root.muted
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Muted {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        visible: !!slot.modelData.window
                                        text: !slot.modelData.window ? ""
                                            : slot.modelData.window.away ? "on " + slot.modelData.window.away + ", Enter brings it here"
                                            : slot.modelData.window.title
                                        color: slot.modelData.window && slot.modelData.window.away ? root.teal : root.muted
                                        font.pixelSize: 10
                                    }
                                    Muted {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        visible: slot.modelData.behind > 0
                                        text: "+" + slot.modelData.behind + " under" + (slot.selected ? "\n" + slot.modelData.key + " again flips" : "")
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        font.family: root.condensed
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                        // The blueprint under its picture: G cycles it
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Keycap { label: "G" }
                            T {
                                text: root.st.blueprint ? root.st.blueprint.name : "—"
                                color: root.fg
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.maximumWidth: 220
                            }
                            Muted {
                                text: root.st.blueprint ? root.st.blueprint.index + " / " + root.st.blueprint.count : ""
                                font.family: root.condensed
                            }
                            Muted {
                                visible: !!(root.st.blueprint && root.st.blueprint.auto)
                                Layout.fillWidth: true
                                text: "auto · G or an assign makes it yours"
                                font.pixelSize: 11
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // Picker: an app's windows or a slot's layers, labeled with the keys that choose them
                    ColumnLayout {
                        visible: !!root.st.picker
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            SectionLabel { text: root.st.picker ? root.st.picker.title : ""; color: root.gold; visible: true }
                            Item { Layout.fillWidth: true }
                            Muted { text: "Esc cancels"; font.family: root.condensed; font.pixelSize: 10 }
                        }
                        Repeater {
                            model: root.st.picker ? root.st.picker.items : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: root.rad(7)
                                color: root.panel
                                border.color: root.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Keycap { label: modelData.key; lit: true }
                                    T {
                                        text: modelData.class
                                        color: root.fg
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Muted {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                    }
                                    Muted {
                                        text: modelData.where
                                        font.family: root.condensed
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                        // fixed extras (N = a new window of this app)
                        Repeater {
                            model: root.st.picker ? (root.st.picker.extras ?? []) : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: root.rad(7)
                                color: root.panel
                                border.color: root.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Keycap { label: modelData.key; lit: true }
                                    T {
                                        text: modelData.text
                                        color: root.fg
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Item { Layout.fillWidth: true }
                                    Muted {
                                        text: "into the selected slot"
                                        font.family: root.condensed
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }

                        // Windows here (right hand)
                        ColumnLayout {
                            visible: !root.st.picker
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                        SectionLabel { text: "On this workspace" }
                        Muted {
                            visible: (root.st.windows ?? []).length === 0
                            text: "No windows here yet. Pick an app below."
                        }
                        Repeater {
                            model: root.st.windows ?? []
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                Keycap { label: modelData.key }
                                T {
                                    text: modelData.class
                                    color: root.fg
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Muted {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    font.family: root.condensed
                                    font.pixelSize: 13
                                }
                                Muted {
                                    visible: !!modelData.slot
                                    text: (modelData.behind ? "under " : "in ") + modelData.slot
                                    font.family: root.condensed
                                    font.pixelSize: 11
                                }
                            }
                        }

                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // Constellations (left hand: number row)
                        ColumnLayout {
                            Layout.preferredWidth: 430
                            Layout.minimumWidth: 430
                            Layout.maximumWidth: 430
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                    // Constellations: 1-9 recall; Super+S saves (then a number)
                    SectionLabel { text: "Constellations"; Layout.topMargin: 2 }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: constellationCol.implicitHeight + (root.st.saving ? 14 : 0)
                        radius: root.rad(8)
                        color: root.st.saving ? root.goldSoft : "transparent"
                        border.color: root.st.saving ? root.gold : "transparent"

                        ColumnLayout {
                            id: constellationCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.st.saving ? 7 : 0
                            spacing: 6
                        Muted {
                            visible: (root.st.constellations ?? []).length === 0
                            text: "No constellations yet. Super+S saves this workspace as one."
                        }
                        Flow {
                            id: constellationRow
                            Layout.fillWidth: true
                            spacing: 6

                            QtObject { id: constellationDrag; property int from: -1; property int to: -1 }
                            Repeater {
                                id: constellationRep
                                model: root.st.constellations ?? []
                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    required property int index
                                    readonly property int number: index + 1
                                    readonly property bool renaming: root.st.renaming === number
                                    property bool confirmDelete: false
                                    readonly property bool target: root.st.saving === number
                                        || (constellationDrag.from >= 0 && constellationDrag.to === index && constellationDrag.from !== index)
                                    implicitWidth: constellationChip.implicitWidth + 12
                                    implicitHeight: 32
                                    radius: root.rad(7)
                                    opacity: constellationDrag.from === index ? 0.4 : 1
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    color: confirmDelete ? root.redSoft : modelData.active || target || renaming ? root.goldSoft : root.panel
                                    border.color: confirmDelete ? root.red : modelData.active || target || renaming ? root.gold : root.line

                                    HoverHandler { id: chipHover }
                                    Timer { // a delete needs its second click within a moment
                                        running: chip.confirmDelete
                                        interval: 2500
                                        onTriggered: chip.confirmDelete = false
                                    }

                                    // Drag onto another chip to reorder (position = number key);
                                    // double-click or right-click renames.
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: constellationDrag.from >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        onPressed: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                root.lua("shtl.start_rename(" + chip.number + ")")
                                                return
                                            }
                                            constellationDrag.from = chip.index
                                            constellationDrag.to = chip.index
                                        }
                                        onDoubleClicked: root.lua("shtl.start_rename(" + chip.number + ")")
                                        onPositionChanged: function(mouse) {
                                            const q = mapToItem(constellationRow, mouse.x, mouse.y)
                                            for (let i = 0; i < constellationRep.count; i++) {
                                                const it = constellationRep.itemAt(i)
                                                if (q.x >= it.x && q.x < it.x + it.width && q.y >= it.y && q.y < it.y + it.height) constellationDrag.to = i
                                            }
                                        }
                                        onReleased: {
                                            if (constellationDrag.from >= 0 && constellationDrag.to !== constellationDrag.from)
                                                root.lua("shtl.move_constellation(" + (constellationDrag.from + 1) + "," + (constellationDrag.to + 1) + ")")
                                            constellationDrag.from = -1
                                            constellationDrag.to = -1
                                        }
                                    }
                                    RowLayout {
                                        id: constellationChip
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 4
                                        spacing: 6
                                        Keycap { label: modelData.key; lit: modelData.active }
                                        T {
                                            visible: !chip.renaming
                                            text: chip.confirmDelete ? "Delete " + modelData.name + "?"
                                                : modelData.name + (modelData.changed ? "  •" : "")
                                            color: chip.confirmDelete ? root.red : root.fg
                                            font.pixelSize: 12
                                        }
                                        TextInput {
                                            id: nameInput
                                            visible: chip.renaming
                                            Layout.preferredWidth: Math.max(90, contentWidth + 4)
                                            color: root.fg
                                            selectionColor: root.gold
                                            selectedTextColor: root.bg
                                            font.pixelSize: 12
                                            onVisibleChanged: if (visible) {
                                                text = modelData.name
                                                selectAll()
                                                forceActiveFocus()
                                            }
                                            Keys.onReturnPressed: root.lua("shtl.rename_constellation(" + chip.number + "," + root.luaString(text) + ")")
                                            Keys.onEnterPressed: root.lua("shtl.rename_constellation(" + chip.number + "," + root.luaString(text) + ")")
                                            Keys.onEscapePressed: root.lua("shtl.rename_constellation(" + chip.number + ")")
                                        }
                                        T { // delete: click, then click again to confirm
                                            visible: !chip.renaming && (chipHover.hovered || chip.confirmDelete)
                                            text: "✕"
                                            color: chip.confirmDelete || deleteArea.containsMouse ? root.red : root.muted
                                            font.pixelSize: 12
                                            MouseArea {
                                                id: deleteArea
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (chip.confirmDelete) root.lua("shtl.delete_constellation(" + chip.number + ")")
                                                    chip.confirmDelete = !chip.confirmDelete
                                                }
                                            }
                                        }
                                    }
                                    Rectangle { // where Tab goes: a little tab on the chip's top edge
                                        visible: root.st.kick === "★" + modelData.name
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: -6
                                        width: constellationTabText.implicitWidth + 8
                                        height: 12
                                        radius: root.rad(3)
                                        color: root.gold
                                        Text {
                                            id: constellationTabText
                                            anchors.centerIn: parent
                                            text: "Tab"
                                            color: root.onGold
                                            font.family: root.mono
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            visible: root.st.saving || root.st.renaming || root.st.hints !== false
                            spacing: 6
                            Keycap { label: "Super+S" }
                            Muted {
                                Layout.maximumWidth: 330
                                text: root.st.saving ? "press 1–9 · Esc cancels"
                                    : root.st.renaming ? "Enter keeps it · Esc cancels"
                                    : "save · drag to reorder · double-click renames"
                                color: root.st.saving ? root.gold : root.muted
                                font.pixelSize: 11
                            }
                        }
                        }
                    }

                        }

                        // The app pool (right hand)
                        ColumnLayout {
                            visible: !root.st.picker
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                        SectionLabel { text: "Apps" }
                        Repeater {
                            model: root.st.apps ?? []
                            RowLayout {
                                id: appRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: appRow.modelData
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: 46
                                        radius: root.rad(7)
                                        id: appChip
                                        readonly property bool recent: !modelData.empty && !modelData.starred
                                        color: modelData.empty ? "transparent" : root.panel
                                        border.color: recent ? "transparent" : root.line
                                        opacity: modelData.empty ? 0.45 : 1
                                        Shape { // recent apps only borrow the key: dashed outline
                                            visible: appChip.recent
                                            anchors.fill: parent
                                            preferredRendererType: Shape.CurveRenderer
                                            ShapePath {
                                                strokeColor: root.muted
                                                strokeWidth: 1
                                                fillColor: "transparent"
                                                strokeStyle: ShapePath.DashLine
                                                dashPattern: [3, 3]
                                                PathRectangle {
                                                    x: 0.5
                                                    y: 0.5
                                                    width: appChip.width - 1
                                                    height: appChip.height - 1
                                                    radius: root.rad(7)
                                                }
                                            }
                                        }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 5
                                            anchors.rightMargin: 6
                                            spacing: 6
                                            Keycap { label: modelData.key }
                                            ColumnLayout {
                                                visible: !modelData.empty
                                                Layout.fillWidth: true
                                                spacing: 0
                                                T {
                                                    Layout.fillWidth: true
                                                    text: modelData.name ?? ""
                                                    color: modelData.count > 0 ? root.fg : root.muted
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                T {
                                                    Layout.fillWidth: true
                                                    text: (modelData.count === 0 ? "closed"
                                                           : modelData.here ? "here"
                                                           : "on " + modelData.where + (modelData.count > 1 ? " +" + (modelData.count - 1) : ""))
                                                    color: root.muted
                                                    font.family: root.condensed
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        T { // a star: keeps this key
                                            visible: !!modelData.starred
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.topMargin: 2
                                            anchors.rightMargin: 4
                                            text: "★"
                                            color: root.gold
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }
                        }
                    }
                }

                // Footer: what just happened, then the keys (wrapped: a long line would widen the whole panel)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (root.st.message ?? "") !== "" || root.st.hints !== false
                    spacing: 4
                    T {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.st.message ?? ""
                        color: root.gold
                        font.family: root.condensed
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Muted {
                        visible: root.st.hints !== false
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        text: "A S D F slot (again = next layer, hold = layers) · H J K L ; window · Y–P / N–/ apps (hold = which) · G blueprint · ⌫ shelf (hold = close) · Super+, settings · Space / Esc closes"
                        font.family: root.condensed
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}
