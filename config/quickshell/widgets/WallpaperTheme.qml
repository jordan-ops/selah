pragma Singleton
import Quickshell
import QtQuick
import "../services" as Services

// WallpaperTheme stand-in for the ported widgets (Nebula shell, GPL-3.0).
// WidgetScreen paints this file into the frosted backdrop every widget
// crops itself out of — our current wallpaper, live, so a wallpaper
// switch re-frosts every card without a reload.
Singleton {
    id: root
    readonly property string wallpaperScreen: Services.Wallpapers.current || ""
}
