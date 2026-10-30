# Selah — credits & provenance

**Selah** is this machine's custom desktop shell: a Quickshell (Qt/QML) +
Hyprland composition, rebranded on 2026-10-20 from the tooling it grew out
of. Upstream names survive only in this file and in one-line attribution
comments inside genuinely ported files.

## Nebula shell — GPL-3.0

The widget layer (`widgets/`), several services, shaders, and parts of the
bar/keybinding parser are ports or adaptations of the **Nebula** shell,
released under the GPL-3.0. Files derived from it carry a one-line
`Ported from Nebula's … (GPL-3.0)` / `Adapted from Nebula … (GPL-3.0)`
header; those notices must stay if this config is ever distributed.

Major ports: the whole `widgets/` kit (M3Slider, CustomToogle, CustomText,
M3WavyProgressBar, clock/date/monitor widgets, …), `services/Keybinds.qml`,
`services/Tuck.qml`, `services/Ripple.qml`, `ThemeFlip.qml`, `EdgeLight.qml`,
`Background.qml` (ripples), `shaders/{ripple,edgelight,themeflip}.frag`,
`TuckTabs.qml`.

## Omarchy

Scripts under `scripts/` (webapp install/launch/remove, install-app,
global-theme hooks) and the screensaver launcher pair in `~/.local/bin`
were adapted from **omarchy**; each keeps a single `Adapted from omarchy's …`
provenance line. The idle-timeout store (`~/.config/selah/shell.json`) and
the `org.selah.screensaver` window class continue omarchy's conventions,
renamed.

## OmaSettings

The settings app (`SettingsWindow.qml`, `services/SettingsCatalog.qml`,
`Settings*.qml` row components) is a port of the **OmaSettings** Hyprland
settings plugin. Its design rules (one-source catalog, entries indexed by
the launcher, write-on-release for sliders) are kept and documented in the
catalog header; the name "omasettings" survives in comments describing that
heritage.

## This machine's own

Everything else — bar, control center, lock screen, launcher, theme
pipeline (`aether-*` scripts, AetherPicker), tuck, polkit agent, settings
app chrome — was written for this setup.
