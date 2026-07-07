import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "next-boot-selector"

    readonly property string sharedPluginId: "nextBootSelector"

    readonly property string privCmd: SettingsData.getPluginSetting(root.sharedPluginId, "privCmd", "sudo -n")
    readonly property string hideRegex: SettingsData.getPluginSetting(root.sharedPluginId, "hideRegex", "pxe|cd/dvd|removable device|network device")
    readonly property bool rebootAfterSet: SettingsData.getPluginSetting(root.sharedPluginId, "rebootAfterSet", false) === true

    property var entries: []
    property string bootCurrent: ""
    property string bootNext: ""
    property bool loading: false

    function loadFromGlobal() {
        const cached = PluginService.getGlobalVar(root.sharedPluginId, "state", null)
        if (cached) {
            entries = cached.entries || []
            bootCurrent = cached.bootCurrent || ""
            bootNext = cached.bootNext || ""
        }
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId === root.sharedPluginId && varName === "state") {
                root.loadFromGlobal()
            }
        }
    }

    function refresh(debounceMs) {
        const wait = (typeof debounceMs === "number") ? debounceMs : 0
        loading = true
        Proc.runCommand("nextBootSelector.read", ["efibootmgr"], function(stdout, exit) {
            loading = false
            if (exit !== 0) {
                ToastService.showError("efibootmgr read failed", "exit " + exit)
                return
            }
            parseOutput(stdout)
        }, wait)
    }

    function parseOutput(output) {
        const lines = output.split("\n")
        const rx = /^Boot([0-9A-Fa-f]{4})(\*?)\s+(.*)$/
        const pathRx = /\s+(HD\(|PciRoot\(|BBS\(|CDROM\(|Pci\(|Fv\(|VenHw\(|Uri\()/
        let list = []
        let bc = ""
        let bn = ""
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.indexOf("BootCurrent:") === 0) {
                bc = line.substring(12).trim()
                continue
            }
            if (line.indexOf("BootNext:") === 0) {
                bn = line.substring(9).trim()
                continue
            }
            const m = line.match(rx)
            if (!m) continue
            const id = m[1].toUpperCase()
            const active = m[2] === "*"
            let rest = m[3]
            const tabIdx = rest.indexOf("\t")
            if (tabIdx >= 0) {
                rest = rest.substring(0, tabIdx)
            } else {
                const pm = rest.match(pathRx)
                if (pm)
                    rest = rest.substring(0, pm.index)
            }
            list.push({
                "id": id,
                "active": active,
                "label": rest.trim() || ("Boot" + id)
            })
        }
        entries = list
        bootCurrent = bc.toUpperCase()
        bootNext = bn.toUpperCase()
        PluginService.setGlobalVar(root.sharedPluginId, "state", {
            "entries": list,
            "bootCurrent": bc.toUpperCase(),
            "bootNext": bn.toUpperCase()
        })
    }

    readonly property string currentLabel: {
        const id = root.bootNext || root.bootCurrent
        for (let i = 0; i < root.entries.length; i++) {
            if (root.entries[i].id === id)
                return root.entries[i].label
        }
        return id || "?"
    }

    readonly property var filteredEntries: {
        if (!root.hideRegex)
            return root.entries
        let rx
        try {
            rx = new RegExp(root.hideRegex, "i")
        } catch (e) {
            return root.entries
        }
        return root.entries.filter(function(e) {
            return !rx.test(e.label)
        })
    }

    function runPriv(id, args, onDone) {
        const shellLine = privCmd + " efibootmgr " + args + " 2>&1"
        Proc.runCommand(id, ["sh", "-c", shellLine], function(stdout, exit) {
            if (onDone)
                onDone(stdout, exit)
        }, 50)
    }

    function setBootNext(id) {
        if (!/^[0-9A-Fa-f]{4}$/.test(id)) {
            ToastService.showError("Invalid Boot ID: " + id)
            return
        }
        runPriv("nextBootSelector.set", "--bootnext " + id, function(out, exit) {
            if (exit === 0) {
                ToastService.showInfo("Next boot → " + id)
                refresh()
                if (rebootAfterSet)
                    Quickshell.execDetached(["systemctl", "reboot"])
            } else {
                const trimmed = (out || "").trim().split("\n").pop() || ("exit " + exit)
                ToastService.showError("Set BootNext failed", trimmed)
            }
        })
    }

    function clearBootNext() {
        runPriv("nextBootSelector.clear", "--delete-bootnext", function(out, exit) {
            if (exit === 0) {
                ToastService.showInfo("BootNext cleared")
                refresh()
            } else {
                const trimmed = (out || "").trim().split("\n").pop() || ("exit " + exit)
                ToastService.showError("Clear BootNext failed", trimmed)
            }
        })
    }

    Component.onCompleted: {
        loadFromGlobal()
        if (!entries || entries.length === 0)
            refresh(0)
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: hIcon.width
            implicitHeight: hIcon.height

            DankIcon {
                id: hIcon
                anchors.centerIn: parent
                name: "restart_alt"
                size: root.iconSize
                color: root.bootNext !== "" ? Theme.primary : Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vIcon.width
            implicitHeight: vIcon.height

            DankIcon {
                id: vIcon
                anchors.centerIn: parent
                name: "restart_alt"
                size: root.iconSize
                color: root.bootNext !== "" ? Theme.primary : Theme.surfaceText
            }
        }
    }

    ccWidgetIcon: "restart_alt"
    ccWidgetPrimaryText: "Next Boot"
    ccWidgetSecondaryText: root.bootNext !== "" ? root.currentLabel : "Not set"
    ccWidgetIsActive: root.bootNext !== ""

    onCcWidgetToggled: {
        if (root.bootNext !== "")
            root.clearBootNext()
        else
            ToastService.showInfo("Next Boot", "Expand to pick an entry")
    }

    ccDetailContent: Component {
        Rectangle {
            id: ccDetail
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            border.width: 0

            StyledText {
                id: ccHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingL
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                text: "Select next boot entry"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                id: ccButtonRow
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: Theme.spacingL
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                height: 44
                spacing: Theme.spacingM

                Rectangle {
                    width: (parent.width - Theme.spacingM) / 2
                    height: parent.height
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(clearArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh, Theme.popupTransparency)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    opacity: root.bootNext !== "" ? 1.0 : 0.5

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "clear"
                            size: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: "Clear BootNext"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DankRipple {
                        id: ccClearRipple
                        cornerRadius: parent.radius
                    }

                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.bootNext !== ""
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: mouse => ccClearRipple.trigger(mouse.x, mouse.y)
                        onClicked: root.clearBootNext()
                    }
                }

                Rectangle {
                    width: (parent.width - Theme.spacingM) / 2
                    height: parent.height
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(ccRebootMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh, Theme.popupTransparency)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "restart_alt"
                            size: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: "Reboot now"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DankRipple {
                        id: ccRebootRipple
                        cornerRadius: parent.radius
                    }

                    MouseArea {
                        id: ccRebootMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ccRebootRipple.trigger(mouse.x, mouse.y)
                        onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                }
            }

            Rectangle {
                id: ccDivider
                anchors.bottom: ccButtonRow.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                anchors.bottomMargin: Theme.spacingM
                height: 1
                color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
            }

            DankFlickable {
                id: ccScroll
                anchors.top: ccHeader.bottom
                anchors.bottom: ccDivider.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingM
                anchors.bottomMargin: Theme.spacingM
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                contentHeight: ccEntries.implicitHeight
                clip: true

                Column {
                    id: ccEntries
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.filteredEntries

                        delegate: Rectangle {
                            required property var modelData
                            id: ccRow
                            readonly property bool isNext: modelData.id === root.bootNext
                            readonly property bool isCurrent: modelData.id === root.bootCurrent
                            width: ccEntries.width
                            height: 56
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                            border.color: isNext ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                            border.width: isNext ? 2 : 0

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingM
                                spacing: Theme.spacingM
                                width: parent.width - Theme.spacingM * 2

                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: ccRow.isNext ? "radio_button_checked" : "radio_button_unchecked"
                                    size: Theme.iconSize
                                    color: ccRow.isNext ? Theme.primary : Theme.surfaceVariantText
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Theme.iconSize - Theme.spacingM * 2
                                    spacing: 2

                                    StyledText {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: ccRow.modelData.label
                                        color: ccRow.isNext ? Theme.primary : Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: ccRow.isNext ? Font.Medium : Font.Normal
                                    }

                                    StyledText {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: "Boot" + ccRow.modelData.id
                                            + (ccRow.isCurrent ? "  ·  currently running" : "")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }
                            }

                            DankRipple {
                                id: ccRowRipple
                                cornerRadius: parent.radius
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => ccRowRipple.trigger(mouse.x, mouse.y)
                                onClicked: root.setBootNext(ccRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    ccDetailHeight: 420

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Next Boot"
            detailsText: root.bootNext !== ""
                ? ("Will boot: " + root.currentLabel)
                : "Select an entry to boot next"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingL

                Row {
                    id: popoutButtonRow
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 44
                    spacing: Theme.spacingM

                    Rectangle {
                        width: (parent.width - Theme.spacingM) / 2
                        height: parent.height
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(popoutClearArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                        border.width: 1
                        opacity: root.bootNext !== "" ? 1.0 : 0.5

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "clear"
                                size: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Clear BootNext"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        DankRipple {
                            id: popoutClearRipple
                            cornerRadius: parent.radius
                        }

                        MouseArea {
                            id: popoutClearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.bootNext !== ""
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => popoutClearRipple.trigger(mouse.x, mouse.y)
                            onClicked: {
                                root.clearBootNext()
                                popout.closePopout()
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - Theme.spacingM) / 2
                        height: parent.height
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(popoutRebootArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "restart_alt"
                                size: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Reboot now"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        DankRipple {
                            id: popoutRebootRipple
                            cornerRadius: parent.radius
                        }

                        MouseArea {
                            id: popoutRebootArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => popoutRebootRipple.trigger(mouse.x, mouse.y)
                            onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                        }
                    }
                }

                Rectangle {
                    id: popoutDivider
                    anchors.bottom: popoutButtonRow.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottomMargin: Theme.spacingM
                    height: 1
                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                }

                DankFlickable {
                    id: popoutScroll
                    anchors.top: parent.top
                    anchors.bottom: popoutDivider.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottomMargin: Theme.spacingM
                    contentHeight: popoutEntries.implicitHeight
                    clip: true

                    Column {
                        id: popoutEntries
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.filteredEntries

                            delegate: Rectangle {
                                required property var modelData
                                id: entryRect
                                readonly property bool isNext: modelData.id === root.bootNext
                                readonly property bool isCurrent: modelData.id === root.bootCurrent
                                width: popoutEntries.width
                                height: 56
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                border.color: isNext ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                                border.width: isNext ? 2 : 0

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingM
                                    spacing: Theme.spacingM
                                    width: parent.width - Theme.spacingM * 2

                                    DankIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: entryRect.isNext ? "radio_button_checked" : "radio_button_unchecked"
                                        size: Theme.iconSize
                                        color: entryRect.isNext ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Theme.iconSize - Theme.spacingM * 2
                                        spacing: 2

                                        StyledText {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: entryRect.modelData.label
                                            color: entryRect.isNext ? Theme.primary : Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: entryRect.isNext ? Font.Medium : Font.Normal
                                        }

                                        StyledText {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: "Boot" + entryRect.modelData.id
                                                + (entryRect.isCurrent ? "  ·  currently running" : "")
                                                + (entryRect.modelData.active ? "" : "  ·  inactive")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }
                                }

                                DankRipple {
                                    id: popoutRowRipple
                                    cornerRadius: parent.radius
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => popoutRowRipple.trigger(mouse.x, mouse.y)
                                    onClicked: {
                                        root.setBootNext(entryRect.modelData.id)
                                        popout.closePopout()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 440
    popoutHeight: 520
}
