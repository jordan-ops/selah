// Ported from Nebula's modules/utils/IconUtil.qml (GPL-3.0) — qs.modules imports
// dropped (sibling resolution in widgets/). ../../assets/ became ../assets/:
// Nebula resolves assets/ from modules/utils/, ours sits one level above widgets/.
pragma Singleton
import QtQuick
import Quickshell

Item {
    function getIconName(windowClass) {
        const iconMap = {
            "firefox": "firefox",
            "google-chrome": "google-chrome",
            "chromium": "chromium",
            "code": "visual-studio-code",
            "discord": "discord",
            "spotify": "spotify",
            "kitty": "kitty",
            "alacritty": "Alacritty",
            "thunar": "thunar",
            "vlc": "vlc",
            "steam": "steam",
            "obsidian": "obsidian",
            "telegram": "telegram",
            "brave-browser": "brave-browser",
            "zen": "zen-browser",
            "emblem-mail": "telegram",
            "quickshell": "Quickshell"

        }

        if (!windowClass) return ""
        var lowerClass = windowClass.toLowerCase()
        return iconMap[lowerClass] || lowerClass || ""
    }

    function getIconPath(windowClass, fallback = "application-x-executable") {
        return Quickshell.iconPath(getIconName(windowClass), fallback)
    }

    function getSystemIcon(iconName) {
        return Qt.resolvedUrl("../assets/" + iconName + ".svg")
    }

    function getSystemIconPng(iconName){
        return Qt.resolvedUrl("../assets/" + iconName + ".png")
    }

    function getImage(name){
        return Qt.resolvedUrl("../assets/" + name)
    }
}
