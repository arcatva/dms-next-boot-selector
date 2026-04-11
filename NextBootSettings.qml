import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "nextBootSelector"

    StyledText {
        width: parent.width
        text: "Privilege & filtering"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "privCmd"
        label: "Privilege command"
        description: "Prepended to efibootmgr writes. Default 'sudo -n' fails fast if NOPASSWD rule is missing."
        placeholder: "sudo -n"
        defaultValue: "sudo -n"
    }

    StringSetting {
        settingKey: "hideRegex"
        label: "Hide entries matching regex"
        description: "Case-insensitive RegExp tested against each entry label. Empty = show all."
        placeholder: "pxe|cd/dvd|removable device|network device"
        defaultValue: "pxe|cd/dvd|removable device|network device"
    }

    ToggleSetting {
        settingKey: "rebootAfterSet"
        label: "Reboot after selecting"
        description: "Immediately run 'systemctl reboot' once BootNext is set."
        defaultValue: false
    }
}
