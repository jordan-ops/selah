pragma Singleton
import Quickshell
import QtQuick

// Single source of truth for the settings app: SettingsWindow renders
// these entries AND the launcher indexes this very list (omasettings'
// lesson — the search index is built from the section sources, so the
// two can never drift into maintaining separate lists).
//
// Layers: this file = meaning only. The window draws; commands do system
// work; nothing here touches files or spawns processes.
//
// Entry fields:
//   type:  switch    -> bool key in services/Settings; pill + On/Off text
//          choice    -> options[]; source "settings" (default) or "themes"
//          action    -> command[] argv, run via qs ipc (same paths the
//                        hypr binds use — one transport, no second path)
//          info      -> read-only value; source may be dynamic
//          slider    -> hyprKey + min/max/step[/scale/suffix]; live read
//                        via hyprctl getoption, commit via hyprEval
//          knob      -> readCommand + writeCommand percent row on a
//                        rotary dial (volumes): first /(\d+)%/ of the
//                        read stdout, writes coalesce through a 75 ms
//                        throttle plus the final on release; min/max/
//                        step/suffix; immediate like cmdswitch (pactl
//                        has no Apply/Revert baseline)
//          hyprswitch-> bool hyprKey pill + On/Off text; optional
//                        persistKey recorded in settings.json, re-applied
//                        at shell start
//          buttons   -> horizontal chip group for every multi-choice
//                        option: option.command[] argv, or entry-level
//                        hyprKey/settingsKey + option.value. The current
//                        value live-reads from hyprKey / settingsKey /
//                        entry.readCommand so the matching chip starts lit.
//          cmdswitch -> bool pill + On/Off text backed by shell state:
//                        readCommand stdout scanned for readTrue, flip
//                        runs command[] then re-reads
//          dropdown  -> expanding searchable list; source "fonts"
//                        (fc-list scan + set-font.sh), "hypr" (options[],
//                        hyprctl read/eval), "apps" (role — default-apps.sh
//                        claims scan, applied through xdg-mime)
//          swatches  -> inline grid; source "themes" | "wallpapers",
//                        applies via Themes.apply / Wallpapers.apply
//          wallpapers-> swatches alias for wallpaper grids
//          carousel  -> hero strip; source "themes" | "wallpapers"
//          powercard -> material battery card; one upower -i read gives
//                        %, state, estimate, watts and health
//          netcard   -> material network card; nmcli live IP/gateway +
//                        band and DNS chip groups (re-join to apply)
//          timecard  -> material clock card; ticking time, NTP status,
//                        searchable timezone picker (pkexec)
//          knobcard  -> material card of rotary knobs; knobs: [{label,
//                        hyprKey, min/max/step/scale/suffix}] — each
//                        cell reads hyprctl getoption and commits with
//                        the slider's hyprChanged + hyprEval rule
//          textsize  -> slider UI over scripts/set-text-size.sh: live
//                        px from gsettings font-name, one write patches
//                        gsettings/GTK/kitty/foot together (9–20)
//          animcard  -> motion controls card: global / quickshell /
//                        hyprland groups, each a pill (enable) + speed
//                        chips; carries hyprKey + persistKey so the
//                        compositor toggle re-applies like a hyprswitch
//   value: static text for info rows ("Super + Space")
//   source for info: theme | wallpaper | battery | net (live reads)
//
// Ported omasettings entries stay inside these types:
//   - Hyprland value that applies now  -> hyprEval
//     'hl.config({...})' (Lua key shape mirrors the keyword, e.g.
//     decoration:blur:enabled -> { decoration = { blur = { enabled }}}),
//     or hyprswitch / buttons reading hyprctl getoption
//   - documented omarchy/omasettings command                 -> action argv
//     kept as-is; missing binaries fail silently (see
//     omasettings-needs-user.md "Ported with missing backend")
//   - setting whose row needs a slider, text field, or live
//     list this window cannot draw yet                      -> info row
//     carrying the default + what it needs
Singleton {
    id: root

    readonly property var pages: [
        { id: "bar",      name: "Bar",                icon: "preferences-system" },
        { id: "toggles",  name: "Quick toggles",      icon: "preferences-other" },
        { id: "appearance", name: "Appearance",       icon: "preferences-desktop-color" },
        { id: "animations", name: "Animations",        icon: "media-playlist-repeat" },
        { id: "bindings",  name: "Keybinding editor", icon: "preferences-desktop-keyboard-shortcuts" },
        { id: "compose",   name: "Compose keys",      icon: "insert-text" },
        { id: "pointer",   name: "Mouse & Touchpad",  icon: "input-mouse" },
        { id: "displays",  name: "Displays",          icon: "video-display" },
        { id: "audio",     name: "Audio",             icon: "audio-volume-high" },
        { id: "network",   name: "Network",           icon: "network-wireless" },
        { id: "bluetooth", name: "Bluetooth",         icon: "bluetooth-active" },
        { id: "power",     name: "Power",             icon: "battery-good" },
        { id: "idle",      name: "Idle & Lock",       icon: "preferences-desktop-screensaver" },
        { id: "datetime",  name: "Date & Time",       icon: "preferences-system-time" },
        { id: "sddm",      name: "Login screen",      icon: "system-users" },
        { id: "defaults",  name: "Default apps",      icon: "web-browser" },
        { id: "nvim",      name: "Neovim",            icon: "text-x-generic" },
        { id: "updates",   name: "Updates",           icon: "software-update-available" },
        { id: "about",    name: "About",              icon: "help-about" }
    ]

    readonly property var entries: [
        // ————————————————— Bar —————————————————
        { id: "restStyle", page: "bar", type: "choice", source: "settings",
          key: "bar.restStyle",
          label: "Rest style",
          description: "What the bar collapses to when idle",
          options: [ { value: "compact", label: "Compact capsule" },
                     { value: "wide",    label: "Full row" } ],
          keywords: "bar pill rest compact wide capsule idle hover expand" },

        { id: "batteryText", page: "bar", type: "switch",
          key: "bar.batteryText",
          label: "Battery percentage",
          description: "Show the % number in the battery ring's top gap",
          keywords: "battery percent ring number text status wifi charge" },

        // ————————————————— Bar (omasettings §2, appended) —————————————————
        { id: "barTransparent", page: "bar", type: "action",
          command: ["omarchy", "bar", "transparent", "toggle"],
          verb: "Toggle",
          label: "Transparent bar",
          description: "Drops the bar's own background so the wallpaper shows through · needs omarchy bar",
          keywords: "bar transparent background wallpaper omarchy" },

        // ————————————————— Quick toggles —————————————————
        { id: "nightlight", page: "toggles", type: "action",
          command: ["qs", "ipc", "call", "nightlight", "toggle"],
          verb: "Toggle",   // flips a tint, opens no panel — "Open" would lie
          label: "Night light",
          description: "Warm screen tint for evening use",
          keywords: "night light warm tint blue gamma evening filter" },

        { id: "updates", page: "toggles", type: "action",
          command: ["qs", "ipc", "call", "updates", "toggle"],
          label: "Updates",
          description: "Check pending system updates",
          keywords: "update upgrade pacman packages system refresh" },

        { id: "controlcenter", page: "toggles", type: "action",
          command: ["qs", "ipc", "call", "controlcenter", "toggle"],
          label: "Control center",
          description: "Audio, network, bluetooth and quick switches",
          keywords: "control center wifi bluetooth volume audio network quick" },

        { id: "powermenu", page: "toggles", type: "action",
          command: ["qs", "ipc", "call", "powermenu", "toggle"],
          label: "Power menu",
          description: "Shutdown, reboot and log out",
          keywords: "power shutdown reboot logout sleep restart off" },

        { id: "lock", page: "toggles", type: "action",
          command: ["qs", "ipc", "call", "lock", "lock"],
          verb: "Lock now",
          label: "Lock screen",
          description: "Lock this session immediately",
          keywords: "lock screen secure password session away" },

        // ————————————————— Appearance (omasettings §1) —————————————————
        // carousels only — one apply path: clicking the hero runs
        // Themes.apply / Wallpapers.apply straight through (no popups, no
        // separate "all" grids, no per-arrow theme work) — then live controls.
        { id: "apTheme", page: "appearance", type: "carousel",
          source: "themes",
          label: "Theme",
          description: "‹ previous · hero · next › — click the hero to apply",
          keywords: "theme color dark light appearance carousel preview set" },

        { id: "apWall", page: "appearance", type: "carousel",
          source: "wallpapers",
          label: "Wallpaper",
          description: "‹ previous · hero · next › — click the hero to apply",
          keywords: "wallpaper background image carousel preview" },

        { id: "apFont", page: "appearance", type: "dropdown",
          source: "fonts",
          label: "Font",
          description: "Global font for shell, GTK apps and terminals — click to expand the list",
          keywords: "font typeface family text appearance list set global" },

        { id: "apLayout", page: "appearance", type: "buttons",
          hyprKey: "general:layout",
          options: [ { label: "Dwindle", value: "dwindle" },
                     { label: "Master", value: "master" },
                     { label: "Scrolling", value: "scrolling" } ],
          label: "Window layout",
          description: "How tiled windows share the screen (general:layout)",
          keywords: "layout dwindle master scrolling tile arrange window" },

        { id: "apTextScale", page: "appearance", type: "textsize",
          label: "Text size",
          description: "GTK apps and terminals · 9–20 px · one write hits gsettings, GTK, kitty and foot",
          keywords: "text size scale dpi gtk shell terminal appearance" },

        { id: "apNightlight", page: "appearance", type: "action",
          command: ["omarchy-toggle-nightlight"],
          verb: "Toggle",
          label: "Night light",
          description: "Warms the screen to 4000K · needs omarchy-toggle-nightlight",
          keywords: "night light warm tint blue gamma evening filter" },

        { id: "apGapIn", page: "appearance", type: "slider",
          hyprKey: "general:gaps_in", min: 0, max: 40, step: 1, suffix: "px",
          label: "Inner gaps",
          description: "Space between tiled windows (general:gaps_in)",
          keywords: "gap inner spacing tiling window margin" },

        { id: "apGapOut", page: "appearance", type: "slider",
          hyprKey: "general:gaps_out", min: 0, max: 60, step: 1, suffix: "px",
          label: "Outer gaps",
          description: "Space around the window grid (general:gaps_out)",
          keywords: "gap outer spacing tiling window margin" },

        { id: "apGapFloat", page: "appearance", type: "slider",
          hyprKey: "general:float_gaps", min: 0, max: 40, step: 1, suffix: "px",
          label: "Floating gaps",
          description: "Gap around floating windows (general:float_gaps)",
          keywords: "gap float floating window spacing" },

        { id: "apRounding", page: "appearance", type: "slider",
          hyprKey: "decoration:rounding", min: 0, max: 30, step: 1, suffix: "px",
          label: "Border rounding",
          description: "Corner radius of every window (decoration:rounding)",
          keywords: "border corner rounding radius window decoration" },

        { id: "apOpacity", page: "appearance", type: "knobcard",
          label: "Window opacity",
          description: "Turn each dial — focused, background and fullscreen (decoration:*_opacity)",
          knobs: [
            { label: "Active",     hyprKey: "decoration:active_opacity",     min: 50, max: 100, step: 1, scale: 0.01, suffix: "%" },
            { label: "Inactive",   hyprKey: "decoration:inactive_opacity",   min: 50, max: 100, step: 1, scale: 0.01, suffix: "%" },
            { label: "Fullscreen", hyprKey: "decoration:fullscreen_opacity", min: 50, max: 100, step: 1, scale: 0.01, suffix: "%" } ],
          keywords: "opacity transparency active inactive focused unfocused fullscreen window" },

        { id: "apPanelAlpha", page: "appearance", type: "choice", source: "settings",
          key: "appearance.transparency",
          label: "Panel transparency",
          description: "How much wallpaper shows through the bar pill, control center, settings window and aether picker",
          // NUMBERS on purpose: Settings.set() JSON-parses whatever it
          // gets, so "30" would land as the number 30 and the chips'
          // strict === against a string model value never matched
          options: [ { value: 0,  label: "Opaque" },
                     { value: 15, label: "15%" },
                     { value: 30, label: "30%" },
                     { value: 45, label: "45%" } ],
          keywords: "transparency transparent alpha panel pill bar control center settings glass see through" },

        { id: "apScreensaver", page: "appearance", type: "info", value: "—",
          label: "Screensaver",
          description: "Text/Image/Reset branding · needs omasettings menu run style.screensaver.*",
          keywords: "screensaver branding text image idle style" },

        { id: "apAboutScreen", page: "appearance", type: "info", value: "—",
          label: "About screen",
          description: "Text/Image/Reset branding · needs omasettings menu run style.about.*",
          keywords: "about screen branding text image style" },

        // ————————————————— Keybinding editor (omasettings §9) —————————————————
        { id: "bndEditor", page: "bindings", type: "keybinds",
          label: "Keybinding editor",
          description: "Search, add, remove, disable · writes ~/.config/hypr/binds.lua + reload",
          keywords: "binding add keys shortcut chord command clash search remove disable turn off unbind binds lua" },

        // ————————————————— Compose keys (omasettings §10) —————————————————
        { id: "cmpEditor", page: "compose", type: "xcompose",
          label: "Compose sequences",
          description: "Add or remove ~/.XCompose entries · applies to newly opened apps",
          keywords: "compose sequence add remove xcompose multi_key dead key list" },

        // ————————————————— Animations (quickshell · Hyprland · global) ————————————————
        { id: "animCard", page: "animations", type: "animcard",
          hyprKey: "animations:enabled", persistKey: "hypr.animationsEnabled",
          label: "Motion controls",
          description: "Global drives shell + compositor · each side also alone",
          keywords: "animation motion speed spring bounce tween quickshell shell hyprland compositor window workspace global enable disable slow fast reduce" },

        // ————————————————— shell decoration effects (motion-gated) ————————————————
        { id: "fxRipple", page: "animations", type: "switch",
          key: "effects.ripple",
          label: "Desktop ripples",
          description: "Ripple rings where the desktop is clicked · motion + game mode gates still apply",
          keywords: "ripple click ring effect decoration desktop water pulse shell" },
        { id: "fxEdgeLight", page: "animations", type: "switch",
          key: "effects.edgelight",
          label: "Notification edge glow",
          description: "Accent light sweeping around the bar pill when a notification lands",
          keywords: "notification glow edge light bar pill alert effect decoration shell" },

        // ————————————————— Mouse & Touchpad (omasettings §11) —————————————————

        { id: "ptrNumlock", page: "pointer", type: "hyprswitch",
          hyprKey: "input:numlock_by_default", persistKey: "hypr.numlock",
          label: "Num lock on at login",
          description: "Start sessions with numlock lit · survives restarts",
          keywords: "numlock keyboard login startup toggle" },

        { id: "ptrSensitivity", page: "pointer", type: "info", value: "0.0",
          label: "Sensitivity",
          description: "How far the pointer travels · −1..1 shown 0–100% · needs percent row",
          keywords: "pointer sensitivity mouse speed acceleration number" },

        { id: "ptrAccel", page: "pointer", type: "buttons",
          hyprKey: "input:accel_profile",
          options: [ { label: "Default", value: "" },
                     { label: "Flat", value: "flat" },
                     { label: "Adaptive", value: "adaptive" } ],
          label: "Acceleration",
          description: "How the pointer picks up speed (input:accel_profile)",
          keywords: "pointer accel profile default flat adaptive mouse acceleration" },

        { id: "ptrFollow", page: "pointer", type: "buttons",
          hyprKey: "input:follow_mouse",
          options: [ { label: "Off", value: 0 },
                     { label: "On", value: 1 },
                     { label: "Keyboard keeps focus", value: 2 },
                     { label: "Without raising", value: 3 } ],
          label: "Focus follows mouse",
          description: "Where keyboard focus goes as the pointer moves (input:follow_mouse)",
          keywords: "focus follows mouse off on keyboard stays without raising click hover window" },

        { id: "ptrNaturalScroll", page: "pointer", type: "hyprswitch",
          hyprKey: "input:touchpad:natural_scroll", persistKey: "hypr.naturalScroll",
          label: "Natural scrolling",
          description: "Scroll up moves content up (macOS style) · survives restarts",
          keywords: "touchpad natural scroll direction inverted toggle" },
        { id: "ptrTapToClick", page: "pointer", type: "hyprswitch",
          hyprKey: "input:touchpad:tap_to_click", persistKey: "hypr.tapToClick",
          label: "Tap to click",
          description: "A tap counts as a click · survives restarts",
          keywords: "touchpad tap click gesture toggle" },
        { id: "ptrClickfinger", page: "pointer", type: "hyprswitch",
          hyprKey: "input:touchpad:clickfinger_behavior", persistKey: "hypr.clickfinger",
          label: "Two-finger right click",
          description: "Off uses the lower-right corner instead · survives restarts",
          keywords: "touchpad clickfinger right click two finger toggle" },
        { id: "ptrDisableTyping", page: "pointer", type: "hyprswitch",
          hyprKey: "input:touchpad:disable_while_typing", persistKey: "hypr.disableWhileTyping",
          label: "Disable while typing",
          description: "Touchpad sleeps while keys are pressed · survives restarts",
          keywords: "touchpad disable while typing palm toggle" },
        { id: "ptrScrollFactor", page: "pointer", type: "info", value: "1.00",
          label: "Scroll speed",
          description: "0.1–3 · needs factor row (hl.config touchpad scroll_factor)",
          keywords: "touchpad scroll speed factor number" },

        { id: "ptrDevSensitivity", page: "pointer", type: "info", value: "—",
          label: "Sensitivity (per device)",
          description: "Own sensitivity for one mouse/touchpad · needs hl.device (dynamic row)",
          keywords: "pointer device sensitivity per hl.device mouse" },
        { id: "ptrDevAccel", page: "pointer", type: "info", value: "—",
          label: "Acceleration (per device)",
          description: "Own accel_profile for one device · needs hl.device (dynamic row)",
          keywords: "pointer device accel profile per hl.device" },
        { id: "ptrDevNatural", page: "pointer", type: "info", value: "—",
          label: "Natural scrolling (per device)",
          description: "Own natural_scroll for one device · needs hl.device (dynamic row)",
          keywords: "pointer device natural scroll per hl.device" },
        { id: "ptrDevLeftHanded", page: "pointer", type: "info", value: "—",
          label: "Left handed (per device)",
          description: "Device-only left_handed option · needs hl.device (dynamic row)",
          keywords: "pointer device left handed mouse buttons hl.device" },
        { id: "ptrDevScroll", page: "pointer", type: "info", value: "—",
          label: "Scroll speed (per device)",
          description: "Own scroll_factor for one device · needs hl.device (dynamic row)",
          keywords: "pointer device scroll factor per hl.device" },
        { id: "ptrDevRemove", page: "pointer", type: "info", value: "—",
          label: "Remove device override",
          description: "Clears or comments out the device block · needs omasettings devices remove",
          keywords: "pointer device remove override reset hl.device" },
        { id: "ptrPickDevice", page: "pointer", type: "info", value: "—",
          label: "Settings for one device",
          description: "Pick a mouse or touchpad to open its group · needs device list (dynamic row)",
          keywords: "pointer pick device choose one mouse touchpad" },

        // ————————————————— Displays (omasettings §12) —————————————————
        { id: "dspConnector", page: "displays", type: "info", value: "eDP-1",
          label: "Connector",
          description: "AU Optronics 0x34ED, read from hyprctl monitors (snapshot)",
          keywords: "display connector edp monitor laptop output edid" },
        { id: "dspMode", page: "displays", type: "buttons",
          readCommand: ["bash", "-c",
            "grep -m1 -oE 'mode *= *\"[^\"]*\"' $HOME/.config/hypr/monitors.lua | cut -d'\"' -f2"],
          options: [
            { label: "Preferred", value: "preferred",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "mode", "preferred"] },
            { label: "1920×1080 · 60 Hz", value: "1920x1080@60.06Hz",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "mode", "1920x1080@60.06Hz"] } ],
          label: "Resolution (eDP-1)",
          // keep this one line clear of the chips group — long copy clips silently
          description: "Writes monitors.lua (backup + luac check), then applies live",
          keywords: "display resolution mode preferred refresh rate eDP persist" },
        { id: "dspScale", page: "displays", type: "buttons",
          readCommand: ["bash", "-c",
            "grep -m1 -oE 'scale *= *\"[^\"]*\"' $HOME/.config/hypr/monitors.lua | cut -d'\"' -f2"],
          options: [
            { label: "×1", value: "1",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1"] },
            { label: "×1.2", value: "1.2",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.2"] },
            { label: "×1.25", value: "1.25",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.25"] },
            { label: "×1.5", value: "1.5",
              command: [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.5"] } ],
          label: "Scale (eDP-1)",
          description: "Steps persist into monitors.lua and apply live",
          keywords: "display scale eDP laptop hidpi factor" },
        { id: "dspForget", page: "displays", type: "info", value: "—",
          label: "Forget display",
          description: "Drops stored overrides and the monitors.lua block · needs omasettings monitor-forget",
          keywords: "display forget remove override reset monitor" },
        { id: "dspAdd", page: "displays", type: "info", value: "—",
          label: "Set up a display that is not connected",
          description: "Model or connector box + Add · needs omasettings monitor-remember",
          keywords: "display add remember disconnected model connector dp hdmi" },

        // ————————————————— Audio (omasettings §13, live) —————————————————
        { id: "audOutVolume", page: "audio", type: "knob",
          readCommand: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
          writeCommand: ["pactl", "set-sink-volume", "@DEFAULT_SINK@"],
          min: 0, max: 150, step: 1, suffix: "%",
          label: "Output volume",
          description: "Turn the dial — 0–150%, writes land live (pactl)",
          keywords: "audio volume output sound loud percent pactl" },
        { id: "audOutMute", page: "audio", type: "cmdswitch",
          readCommand: ["pactl", "get-sink-mute", "@DEFAULT_SINK@"],
          readTrue: "Mute: yes",
          command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"],
          label: "Output muted",
          description: "Mute or unmute everything you hear — pill shows live state",
          keywords: "audio mute output sound silence pactl toggle" },
        { id: "audOutDevices", page: "audio", type: "info", value: "—",
          label: "Output devices",
          description: "Pickable list of sinks, pick sets default · needs pactl list sinks (dynamic row)",
          keywords: "audio output device sink default headphones hdmi speakers" },
        { id: "audInVolume", page: "audio", type: "knob",
          readCommand: ["pactl", "get-source-volume", "@DEFAULT_SOURCE@"],
          writeCommand: ["pactl", "set-source-volume", "@DEFAULT_SOURCE@"],
          min: 0, max: 150, step: 1, suffix: "%",
          label: "Input volume",
          description: "Turn the dial — 0–150%, writes land live (pactl)",
          keywords: "audio volume input microphone percent pactl" },
        { id: "audInMute", page: "audio", type: "cmdswitch",
          readCommand: ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"],
          readTrue: "Mute: yes",
          command: ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"],
          label: "Input muted",
          description: "Mute or unmute the microphone — pill shows live state",
          keywords: "audio mute input microphone silence pactl toggle" },
        { id: "audInDevices", page: "audio", type: "info", value: "—",
          label: "Input devices",
          description: "Pickable list of sources, pick sets default · needs pactl list sources (dynamic row)",
          keywords: "audio input device source default microphone headset" },

        // ————————————————— Network (omasettings §14, live) —————————————————
        { id: "netWifi", page: "network", type: "cmdswitch",
          readCommand: ["nmcli", "radio", "wifi"],
          readTrue: "enabled",
          command: ["bash", "-c",
            "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"],
          label: "Wi-Fi",
          description: "Radio on or off — pill shows live state (nmcli)",
          keywords: "wifi wireless radio network toggle nmcli" },
        { id: "netConn", page: "network", type: "netcard",
          label: "Wi-Fi connection",
          description: "Live IP and gateway · band and DNS re-join the network to apply",
          keywords: "ip address gateway band dns provider resolver wifi connection nmcli cloudflare google quad9" },
        { id: "netNetworks", page: "network", type: "netlist",
          label: "Networks",
          description: "Live scan list — signal, lock, connect / disconnect / forget, password prompt inline",
          keywords: "wifi network list scan ssid connect password forget secured signal nearby" },
        { id: "netQr", page: "network", type: "action",
          command: ["omasettings", "menu", "run", "setup.network.qr"],
          verb: "Show…",
          label: "Wi-Fi QR code",
          description: "Show a code others can scan to join · needs omasettings menu",
          keywords: "wifi qr code share join network scan" },

        // ————————————————— Bluetooth (omasettings §15, live) —————————————————
        { id: "btPower", page: "bluetooth", type: "cmdswitch",
          readCommand: ["bash", "-c", "bluetoothctl show 2>/dev/null"],
          readTrue: "Powered: yes",
          command: ["bash", "-c",
            "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi"],
          label: "Adapter power",
          description: "BlueZ via bluetoothctl — pill shows live state",
          keywords: "bluetooth adapter power on off bluez toggle" },
        { id: "btDevices", page: "bluetooth", type: "btlist",
          label: "Devices (connected / paired / nearby)",
          description: "Pair, connect, trust, forget with battery — live BlueZ discovery while shown",
          keywords: "bluetooth device list pair connect forget headphones battery nearby discovery" },

        // ————————————————— Power (omasettings §16, live) —————————————————
        { id: "pwrCard", page: "power", type: "powercard",
          label: "Battery",
          description: "Charge, estimate, drawing and health — live from upower",
          keywords: "battery charge percent time remaining full drawing watt health capacity upower" },

        { id: "pwrProfile", page: "power", type: "buttons",
          readCommand: ["powerprofilesctl", "get"],
          options: [
            { label: "Power saver", value: "power-saver",
              command: ["powerprofilesctl", "set", "power-saver"] },
            { label: "Balanced", value: "balanced",
              command: ["powerprofilesctl", "set", "balanced"] },
            { label: "Performance", value: "performance",
              command: ["powerprofilesctl", "set", "performance"] } ],
          label: "Power profile",
          description: "One global profile — same on battery or plugged in",
          keywords: "power profile battery saver balanced performance plugged ac energy" },

        // ————————————————— Idle & Lock (omasettings §17) —————————————————
        { id: "idlScreensaver", page: "idle", type: "info", value: "150 s",
          label: "Screensaver after",
          description: "1–60 min slider, stored as seconds · needs minutes row + jq in shell.json",
          keywords: "idle screensaver timeout dim seconds minutes shell.json" },
        { id: "idlLock", page: "idle", type: "info", value: "300 s",
          label: "Lock after",
          description: "Fallback 300 s · needs minutes row + jq in shell.json",
          keywords: "idle lock timeout seconds minutes shell.json" },

        // ————————————————— Date & Time (omasettings §18) —————————————————
        { id: "dtCard", page: "datetime", type: "timecard",
          label: "Clock & date",
          description: "Ticking time, NTP status and a searchable timezone picker (admin auth)",
          keywords: "timezone clock time ntp sync resync date zone region" },

        // ————————————————— Default apps —————————————————
        // One dropdown per role; candidates come from
        // scripts/default-apps.sh — apps whose .desktop file CLAIMS the
        // role's document types — and every pick applies through xdg-mime,
        // so the file manager, the browser and chat apps all honour it.
        // The terminal is the exception (no mime type): its choice lives
        // in settings.json and hypr's binds launch through the same
        // script, so Super+Return follows this row too.
        { id: "defBrowser", page: "defaults", type: "dropdown",
          source: "apps", role: "browser",
          label: "Browser",
          description: "Links from apps and Super+B (http · https · .html)",
          keywords: "default browser firefox chrome chromium web link html http url" },
        { id: "defTerminal", page: "defaults", type: "dropdown",
          source: "apps", role: "terminal",
          label: "Terminal",
          description: "Super+Return opens whatever you pick here",
          keywords: "default terminal emulator foot kitty alacritty shell command console" },
        { id: "defFileman", page: "defaults", type: "dropdown",
          source: "apps", role: "filemanager",
          label: "File manager",
          description: "Super+E and every “open folder” action (inode/directory)",
          keywords: "default files file manager folder nautilus thunar dolphin explorer" },
        { id: "defEditor", page: "defaults", type: "dropdown",
          source: "apps", role: "editor",
          label: "Text editor",
          description: "Double-clicked text, code and csv files",
          keywords: "default editor text code vim gedit kate vscode notepad csv" },
        { id: "defImage", page: "defaults", type: "dropdown",
          source: "apps", role: "image",
          label: "Image viewer",
          description: "png · jpeg · gif · webp · svg · tiff",
          keywords: "default image picture photo viewer png jpg sxiv imv eog loupe" },
        { id: "defVideo", page: "defaults", type: "dropdown",
          source: "apps", role: "video",
          label: "Video player",
          description: "mp4 · mkv · webm · avi · mpeg",
          keywords: "default video movie player mpv vlc celluloid film" },
        { id: "defAudio", page: "defaults", type: "dropdown",
          source: "apps", role: "audio",
          label: "Audio player",
          description: "mp3 · flac · ogg · wav · m4a",
          keywords: "default audio music player mp3 flac song sound" },
        { id: "defPdf", page: "defaults", type: "dropdown",
          source: "apps", role: "pdf",
          label: "PDF reader",
          description: "application/pdf documents",
          keywords: "default pdf reader viewer evince zathura mupdf document" },
        { id: "defArchive", page: "defaults", type: "dropdown",
          source: "apps", role: "archive",
          label: "Archive manager",
          description: "zip · tar · gzip · 7z · rar",
          keywords: "default archive zip extract tar 7z rar compression file-roller" },
        { id: "defOffice", page: "defaults", type: "dropdown",
          source: "apps", role: "office",
          label: "Word documents",
          description: "odt · doc · docx · rtf",
          keywords: "default office word document writer libreoffice odt docx" },
        { id: "defSheet", page: "defaults", type: "dropdown",
          source: "apps", role: "sheet",
          label: "Spreadsheets",
          description: "ods · xls · xlsx",
          keywords: "default spreadsheet excel sheet calc xlsx ods numbers" },
        { id: "defSlide", page: "defaults", type: "dropdown",
          source: "apps", role: "slide",
          label: "Presentations",
          description: "odp · ppt · pptx",
          keywords: "default presentation powerpoint slides impress odp pptx keynote" },

        // ————————————————— Updates —————————————————
        // Two layers: the selah repo itself (the popup — git remote vs
        // this clone) and system packages (pacman/AUR — the bar chip).
        // Info rows live-read services/Updates; actions ride the same qs
        // ipc path every other command here uses.
        { id: "upDesktop", page: "updates", type: "info", source: "repoupdate",
          label: "Desktop (selah)",
          description: "This clone vs the GitHub repo it came from",
          keywords: "update desktop selah github repo deploy pull version sync" },
        { id: "upPackages", page: "updates", type: "info", source: "pkgupdates",
          label: "System packages",
          description: "Pending pacman and AUR updates",
          keywords: "update packages pacman aur yay system pending versions" },
        { id: "upCheck", page: "updates", type: "action",
          command: ["qs", "ipc", "call", "updates", "check"],
          verb: "Check now",
          label: "Check for updates",
          description: "Re-run both checks immediately",
          keywords: "check refresh now search sync update lookup" },
        { id: "upApply", page: "updates", type: "action",
          command: ["qs", "ipc", "call", "updates", "apply"],
          verb: "Update",
          label: "Update the desktop",
          description: "git pull + re-run install.sh — no sudo, no packages",
          keywords: "update desktop pull git apply upgrade selah fresh new" },
        { id: "upUpgrade", page: "updates", type: "action",
          command: ["qs", "ipc", "call", "updates", "upgrade"],
          verb: "Update all",
          label: "Update system packages",
          description: "yay -Syu in a terminal (asks for your password)",
          keywords: "upgrade packages system yay syu terminal update all" },

        // ————————————————— Neovim (omasettings §23) —————————————————
        { id: "nvmNumber", page: "nvim", type: "switch",
          key: "nvim.number",
          label: "Line numbers",
          description: "Stored pref; applies via omasettings nvim set number (options.lua)",
          keywords: "nvim vim line numbers gutter number" },
        { id: "nvmRelNumber", page: "nvim", type: "switch",
          key: "nvim.relativeNumber",
          label: "Relative line numbers",
          description: "Stored pref; applies via omasettings nvim set relativenumber",
          keywords: "nvim vim relative line numbers gutter" },
        { id: "nvmSign", page: "nvim", type: "buttons",
          options: [
            { label: "Always", value: "yes",
              command: ["omasettings", "nvim", "set", "signcolumn", "yes"] },
            { label: "When needed", value: "auto",
              command: ["omasettings", "nvim", "set", "signcolumn", "auto"] },
            { label: "Never", value: "no",
              command: ["omasettings", "nvim", "set", "signcolumn", "no"] } ],
          label: "Sign column",
          description: "Where git marks and diagnostics appear · needs options.lua writer",
          keywords: "nvim vim sign column always auto never git diagnostics" },
        { id: "nvmWrap", page: "nvim", type: "switch",
          key: "nvim.wrap",
          label: "Wrap long lines",
          description: "Stored pref; applies via omasettings nvim set wrap",
          keywords: "nvim vim wrap long lines textwidth switch" },
        { id: "nvmCursorLine", page: "nvim", type: "switch",
          key: "nvim.cursorLine",
          label: "Highlight the current line",
          description: "Stored pref; applies via omasettings nvim set cursorline",
          keywords: "nvim vim cursor line highlight current switch" },
        { id: "nvmColorColumn", page: "nvim", type: "info", value: "—",
          label: "Column guide",
          description: "A column number, or empty for none · needs text row + omasettings nvim set colorcolumn",
          keywords: "nvim vim colorcolumn column guide ruler text" },
        { id: "nvmScrolloff", page: "nvim", type: "info", value: "4",
          label: "Keep visible above and below",
          description: "0–20 lines · needs number row + omasettings nvim set scrolloff",
          keywords: "nvim vim scrolloff context lines number" },
        { id: "nvmSpell", page: "nvim", type: "switch",
          key: "nvim.spell",
          label: "Spell checking",
          description: "Stored pref; applies via omasettings nvim set spell",
          keywords: "nvim vim spell spellcheck grammar switch" },
        { id: "nvmExpandTab", page: "nvim", type: "switch",
          key: "nvim.expandTab",
          label: "Spaces instead of tabs",
          description: "Stored pref; applies via omasettings nvim set expandtab",
          keywords: "nvim vim expandtab spaces tabs indent switch" },
        { id: "nvmShiftwidth", page: "nvim", type: "info", value: "2",
          label: "Indent width",
          description: "1–8 spaces · needs number row + omasettings nvim set shiftwidth",
          keywords: "nvim vim shiftwidth indent spaces number" },
        { id: "nvmTabstop", page: "nvim", type: "info", value: "2",
          label: "Tab width",
          description: "1–8 spaces · needs number row + omasettings nvim set tabstop",
          keywords: "nvim vim tab tab width spaces number" },
        { id: "nvmEdit", page: "nvim", type: "action",
          command: ["bash", "-c", "omarchy-launch-config-editor \"$HOME/.config/nvim/lua/config/options.lua\""],
          verb: "Edit…",
          label: "The rest of the config",
          description: "Opens options.lua; changes apply next Neovim start · needs omarchy-launch-config-editor",
          keywords: "nvim vim options.lua edit config beyond" },

        // ————————————————— Login screen (SDDM greeter) —————————————————
        { id: "sddmTheme", page: "sddm", type: "buttons",
          readCommand: [Quickshell.shellDir + "/scripts/selah-sddm.sh", "current"],
          options: [
            { label: "Selah", value: "selah",
              command: [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "selah"] },
            { label: "Elarun", value: "elarun",
              command: [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "elarun"] },
            { label: "Maldives", value: "maldives",
              command: [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "maldives"] },
            { label: "Maya", value: "maya",
              command: [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "maya"] } ],
          label: "Login screen theme",
          description: "SDDM greeter — Selah carries your theme · applies next login",
          keywords: "sddm login greeter theme boot log screen selah elarun maldives maya" },
        { id: "sddmSetup", page: "sddm", type: "action",
          command: ["foot", "-e", "bash", "-c",
            Quickshell.shellDir + "/scripts/selah-sddm.sh setup-help; echo; read -p 'Press Enter to close' "],
          verb: "Show setup",
          label: "One-time root setup",
          description: "Opens the two commands that let chips apply instantly — paste once, password once",
          keywords: "sddm login root sudo setup helper install password once auth" },
        { id: "sddmSync", page: "sddm", type: "info", value: "Auto",
          label: "Wallpaper & palette",
          description: "The greeter re-syncs to your theme on every switch (switch-theme.sh hook)",
          keywords: "sddm wallpaper palette colors sync greeter background theme match" }
    ]

    // ————————————— hyprland option helpers —————————————
    // one shape shared by the slider / hyprswitch / dropdown / buttons
    // rows: eval writes a nested hl.config table (keyword shape —
    // decoration:rounding becomes decoration = { rounding = … }),
    // getoption output comes back typed. Probed against the live
    // compositor: all shapes return ok.
    function hyprLuaValue(v) {
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "number") return String(v)
        return JSON.stringify(String(v))
    }

    function hyprEval(key, luaVal) {
        const parts = String(key).split(":")
        let s = "hl.config({ "
        for (let i = 0; i < parts.length - 1; i++)
            s += parts[i] + " = { "
        s += parts[parts.length - 1] + " = " + luaVal
        for (let i = 0; i < parts.length; i++) s += " }"
        s += " )"
        return s
    }

    // hyprctl getoption first line: "int: 10" · "float: 1.000000" ·
    // "bool: true" · "str: dwindle" · "css gap data: 5 5 5 5"
    function hyprParse(text) {
        const line = String(text).split("\n")[0].trim()
        if (line.startsWith("bool:")) return line.slice(5).trim() === "true"
        if (line.startsWith("int:")) return parseInt(line.slice(4).trim(), 10)
        if (line.startsWith("float:")) return parseFloat(line.slice(6).trim())
        if (line.startsWith("str:")) {
            const s = line.slice(4).trim()
            // Lua-Hyprland prints [[EMPTY]] for an empty string option
            return s === "[[EMPTY]]" ? "" : s
        }
        if (line.startsWith("css gap data:")) {
            const n = parseFloat(line.slice(13).trim().split(/\s+/)[0])
            return isNaN(n) ? null : n
        }
        const m = line.match(/^-?\d+(\.\d+)?/)
        return m ? parseFloat(m[0]) : null
    }
}
