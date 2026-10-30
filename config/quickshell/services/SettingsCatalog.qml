pragma Singleton
// Single source of truth for the settings app: SettingsWindow renders
// these entries AND the launcher indexes this very list (omasettings'
// lesson — the search index is built from the section sources, so the
// two can never drift into maintaining separate lists).
// Layers: this file = meaning only. The window draws; commands do system
// work; nothing here touches files or spawns processes.
// Entry fields:
//   type:  switch    -> bool key in services/Settings; pill + On/Off text
//          choice    -> options[]; source "settings" (default) or "themes"
//          action    -> command[] argv, run via qs ipc (same paths the
//                        hypr binds use — one transport, no second path)
//          info      -> read-only value; source may be dynamic
//          slider    -> hyprKey + min/max/step[/scale/suffix]; live read
//                        via hyprctl getoption, commit via hyprEval.
//                        hyprKeys[] commits the same value to several
//                        options at once (scroll speed covers mouse AND
//                        touchpad); persistKey records it in settings.json
//                        for SettingsApp's start-of-session reapply
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
//                        optional persistKey names the settings.json slot
//                        the start-of-session reapply restores into
//          cmdswitch -> bool pill + On/Off text backed by shell state:
//                        readCommand stdout scanned for readTrue, flip
//                        runs command[] then re-reads
//          dropdown  -> expanding searchable list; source "fonts"
//                        (fc-list scan + set-font.sh), "hypr" (options[],
//                        hyprctl read/eval), "apps" (role — default-apps.sh
//                        claims scan, applied through xdg-mime), "sinks" /
//                        "sources" (pactl -f json list + get-default-*, a
//                        pick runs set-default and @DEFAULT_*@ follows)
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
//          cmdslider-> command-backed frost slider (audio volumes):
//                        readCommand stdout scanned for the first
//                        /(\d+)%/, writeCommand gets the value appended;
//                        live + throttled like cmdswitch, no Apply/Revert
//          textsize  -> slider UI over scripts/set-text-size.sh: live
//                        px from gsettings font-name, one write patches
//                        gsettings/GTK/kitty/foot together (9–20)
//          lockstyle -> material card: the REAL lock component of the
//                        chosen style rendered into a scaled preview,
//                        plus the chips that pick it (settingsKey —
//                        lock.style drives lock/Classic|Card|Minimal|
//                        Magazine.qml through services/Settings)
//          section   -> heading row, no control, carries only a label;
//                        splits merged pages and is dropped from the
//                        search indexes (`searchable`)
//          animcard  -> motion controls card: global / quickshell /
//                        hyprland groups, each a pill (enable) + speed
//                        chips; carries hyprKey + persistKey so the
//                        compositor toggle re-applies like a hyprswitch
//   value: static text for info rows ("Super + Space")
//   source for info: theme | wallpaper | battery | net | pkgupdates |
//                    repoupdate (live reads — anything else shows the
//                    static `value`; info rows have NO readCommand and
//                    NO hyprKey, so anything not in this list must say
//                    so in its description)
//   default: the value the row SHIPS with (compositor/config fallback,
//            never a guess) — the per-row reset target, read
//            defensively: switch/choice fall back to their key
//            fallback (false / options[0]), hypr rows fall back to the
//            Lua config's own number (appearance.lua / input.lua), and
//            live-state rows (knobs, radio switches) carry none when
//            no default exists
//   persistKey: settings.json slot the start-of-session reapply
//            restores (needs a value stored under it — slider /
//            hyprswitch rows record it on change)
// Grouping: type "section" is a heading, not a setting — it splits a
// merged page (Lock screen holds the session lock AND the SDDM greeter)
// and is filtered out of `searchable`, the list both search indexes read.

import QtQuick
import Quickshell

// Ported omasettings entries stay inside these types:
//   - Hyprland value that applies now  -> hyprEval
//     'hl.config({...})' (Lua key shape mirrors the keyword, e.g.
//     decoration:blur:enabled -> { decoration = { blur = { enabled }}}),
//     or hyprswitch / buttons reading hyprctl getoption
//   - documented external command                          -> action argv
//     kept as-is; missing binaries fail silently (see
//     omasettings-needs-user.md "Ported with missing backend")
//   - setting whose row needs a slider, text field, or live
//     list this window cannot draw yet                      -> info row
//     carrying the default + what it needs
Singleton {
    // one page for BOTH halves of locking up — the style and timeouts
    // the session lock uses, and the SDDM greeter shown before login.
    // Was two pages ("Idle & Lock" + "Login screen"); the section rows
    // keep the groups apart inside the single page.
    // ————————————————— Bar —————————————————
    // ————————————————— Bar (omasettings §2, appended) —————————————————
    // ————————————————— Quick toggles —————————————————
    // flips a tint, opens no panel — "Open" would lie
    // ————————————————— Appearance (omasettings §1) —————————————————
    // carousels only — one apply path: clicking the hero runs
    // Themes.apply / Wallpapers.apply straight through (no popups, no
    // separate "all" grids, no per-arrow theme work) — then live controls.
    // NUMBERS on purpose: Settings.set() JSON-parses whatever it
    // gets, so "30" would land as the number 30 and the chips'
    // strict === against a string model value never matched
    // ————————————————— Blur (shell + window frosting) —————————————————
    // appearance.lua ships the glass recipe — size 4, passes 1,
    // vibrancy 0.1696, popups off, master switch OFF (the 2026-10 heat
    // retune; the old 8/3/popups-on recipe is kept in its git history) —
    // so these rows OPEN on those numbers until one is moved. Each is
    // a live Hyprland option: read with hyprctl getoption, committed
    // with hyprctl eval, recorded under persistKey so the start-of-
    // session reapply keeps it across restarts; Apply additionally
    // mirrors it into user-settings.lua.
    // One split to know about (probe-verified): eval reaches WINDOWS
    // immediately, but the shell's frost — the qs-glass layer rule —
    // reads the config files, so it catches up on a reload, never on
    // eval alone. Hence the reload row at the end: Apply, then click
    // it once and the bar, panels and popups frost at the new values.
    // ————————————————— Desktop clock (giant time widget) ————————————————
    // Off until turned on. The widget is drag/resize-able on the
    // desktop (double-click it) and the same geometry is what the
    // Clock lock style draws — one Settings.clockBox() for both.
    // Qt date tokens — AP is the AM/PM marker ("ap" for am/pm).
    // Values are plain strings: set() JSON-parses what it gets and
    // none of these is valid JSON, so they land as strings.
    // ————————————————— Keybinding editor (omasettings §9) —————————————————
    // ————————————————— Compose keys (omasettings §10) —————————————————
    // ————————————————— Animations (quickshell · Hyprland · global) ————————————————
    // ————————————————— shell decoration effects (motion-gated) ————————————————
    // ————————————————— Mouse & Touchpad (omasettings §11) —————————————————
    // ————————————————— Displays (omasettings §12) —————————————————
    // keep this one line clear of the chips group — long copy clips silently
    // ————————————————— Audio (omasettings §13, live) —————————————————
    // ————————————————— Network (omasettings §14, live) —————————————————
    // ————————————————— Bluetooth (omasettings §15, live) —————————————————
    // ————————————————— Power (omasettings §16, live) —————————————————
    // ————————————————— Lock screen (session + login) —————————————————
    // One page for both halves of locking up, split by the section
    // rows: what the lock looks like while the session runs, then the
    // SDDM greeter that shows before login. This order IS the order
    // on the page (pageEntries filters, it never re-sorts).
    // the preview renders the real component of the chosen style —
    // lock/Classic.qml and friends, at screen size, scaled down.
    // The Clock one locks the widget you placed on the desktop.
    // ————————————————— Login screen (SDDM greeter) —————————————————
    // ————————————————— Date & Time (omasettings §18) —————————————————
    // ————————————————— Default apps —————————————————
    // One dropdown per role; candidates come from
    // scripts/default-apps.sh — apps whose .desktop file CLAIMS the
    // role's document types — and every pick applies through xdg-mime,
    // so the file manager, the browser and chat apps all honour it.
    // The terminal is the exception (no mime type): its choice lives
    // in settings.json and hypr's binds launch through the same
    // script, so Super+Return follows this row too.
    // ————————————————— Updates —————————————————
    // Two layers: the selah repo itself (the popup — git remote vs
    // this clone) and system packages (pacman/AUR — the bar chip).
    // Info rows live-read services/Updates; actions ride the same qs
    // ipc path every other command here uses.
    // ————————————————— Neovim (omasettings §23) —————————————————
    // ————————————————— Widgets —————————————————
    // The widget layer port: every switch writes a flat widgets.*
    // key that widgets/SettingsConfig.qml folds into its blob, so the
    // studio, quick-add and this page can never disagree — one store,
    // three views. Choices list options DEFAULT FIRST (choiceValue()
    // falls back to options[0] when the key is unset).
    // the `widgets` IPC target lives inside WidgetScreen, which only
    // exists while the master switch is on — so arm the layer first,
    // give the Loader its instantiation beat, then open arrange mode

    id: root

    readonly property var pages: [{
        // merged page: the bar's own rows, the panel's display settings
        // and the clock card share one "Display" pane (was three thin
        // pages: Bar, Displays, Date & Time). Quick toggles is gone —
        // every row it had is a control-center / power-menu action.
        "id": "display",
        "name": "Display"
    }, {
        "id": "appearance",
        "name": "Appearance"
    }, {
        "id": "widgets",
        "name": "Widgets"
    }, {
        "id": "animations",
        "name": "Animations"
    }, {
        "id": "bindings",
        "name": "Keybinding editor"
    }, {
        "id": "compose",
        "name": "Compose keys"
    }, {
        "id": "pointer",
        "name": "Mouse & Touchpad"
    }, {
        "id": "audio",
        "name": "Audio"
    }, {
        "id": "network",
        "name": "Network"
    }, {
        "id": "bluetooth",
        "name": "Bluetooth"
    }, {
        "id": "power",
        "name": "Power"
    }, {
        "id": "lock",
        "name": "Lock screen"
    }, {
        "id": "defaults",
        "name": "Default apps"
    }, {
        "id": "nvim",
        "name": "Neovim"
    }, {
        "id": "updates",
        "name": "Updates"
    }, {
        "id": "about",
        "name": "About"
    }]
    // What a search index offers: `entries` minus the section headings,
    // which are page chrome rather than settings. The settings window's
    // sidebar search AND the launcher's ">" catalog both read this, so a
    // heading can never surface as a result — one list, no drift.
    readonly property var searchable: entries.filter((e) => {
        return e.type !== "section";
    })
    readonly property var entries: [{
        "id": "secDisplayBar",
        "page": "display",
        "type": "section",
        "label": "Bar"
    }, {
        "id": "restStyle",
        "page": "display",
        "type": "choice",
        "default": "compact",
        "source": "settings",
        "key": "bar.restStyle",
        "label": "Rest style",
        "description": "What the bar collapses to when idle",
        "options": [{
            "value": "compact",
            "label": "Compact capsule"
        }, {
            "value": "wide",
            "label": "Full row"
        }],
        "keywords": "bar pill rest compact wide capsule idle hover expand"
    }, {
        "id": "batteryText",
        "page": "display",
        "type": "switch",
        "default": false,
        "key": "bar.batteryText",
        "label": "Battery percentage",
        "description": "Show the % number in the battery ring's top gap",
        "keywords": "battery percent ring number text status wifi charge"
    }, {
        "id": "barFloating",
        "page": "display",
        "type": "switch",
        "default": false,
        "key": "bar.floating",
        "label": "Floating pill",
        "description": "Suspend the pill below the top edge instead of flush on it",
        "keywords": "bar pill float floating suspended gap island top margin edge"
    }, {
        "id": "apTheme",
        "page": "appearance",
        "type": "carousel",
        "source": "themes",
        "label": "Theme",
        "description": "Big preview with a thumbnail strip — click the preview to apply, a thumb jumps",
        "keywords": "theme color dark light appearance carousel preview set"
    }, {
        "id": "apWall",
        "page": "appearance",
        "type": "carousel",
        "source": "wallpapers",
        "label": "Wallpaper",
        "description": "Big preview with a thumbnail strip — click the preview to apply, a thumb jumps",
        "keywords": "wallpaper background image carousel preview"
    }, {
        "id": "apFont",
        "page": "appearance",
        "type": "dropdown",
        "source": "fonts",
        "label": "Font",
        "description": "Global font for shell, GTK apps and terminals — click to expand the list",
        "keywords": "font typeface family text appearance list set global"
    }, {
        "id": "apLayout",
        "page": "appearance",
        "type": "buttons",
        "default": "scrolling",
        "hyprKey": "general:layout",
        "persistKey": "hypr.layout",
        "options": [{
            "label": "Dwindle",
            "value": "dwindle"
        }, {
            "label": "Master",
            "value": "master"
        }, {
            "label": "Scrolling",
            "value": "scrolling"
        }],
        "label": "Window layout",
        "description": "How tiled windows share the screen (general:layout)",
        "keywords": "layout dwindle master scrolling tile arrange window"
    }, {
        "id": "apTextScale",
        "page": "appearance",
        "type": "textsize",
        "label": "Text size",
        "description": "GTK apps and terminals · 9–20 px · one write hits gsettings, GTK, kitty and foot",
        "keywords": "text size scale dpi gtk shell terminal appearance"
    }, {
        "id": "apGapIn",
        "page": "appearance",
        "type": "slider",
        "default": 5,
        "hyprKey": "general:gaps_in",
        "persistKey": "hypr.gapsIn",
        "min": 0,
        "max": 40,
        "step": 1,
        "suffix": "px",
        "label": "Inner gaps",
        "description": "Space between tiled windows (general:gaps_in)",
        "keywords": "gap inner spacing tiling window margin"
    }, {
        "id": "apGapOut",
        "page": "appearance",
        "type": "slider",
        "default": 20,
        "hyprKey": "general:gaps_out",
        "persistKey": "hypr.gapsOut",
        "min": 0,
        "max": 60,
        "step": 1,
        "suffix": "px",
        "label": "Outer gaps",
        "description": "Space around the window grid (general:gaps_out)",
        "keywords": "gap outer spacing tiling window margin"
    }, {
        "id": "apGapFloat",
        "page": "appearance",
        "type": "slider",
        "default": 0,
        "hyprKey": "general:float_gaps",
        "persistKey": "hypr.floatGaps",
        "min": 0,
        "max": 40,
        "step": 1,
        "suffix": "px",
        "label": "Floating gaps",
        "description": "Gap around floating windows (general:float_gaps)",
        "keywords": "gap float floating window spacing"
    }, {
        "id": "apRounding",
        "page": "appearance",
        "type": "slider",
        "default": 10,
        "hyprKey": "decoration:rounding",
        "persistKey": "hypr.rounding",
        "min": 0,
        "max": 30,
        "step": 1,
        "suffix": "px",
        "label": "Border rounding",
        "description": "Corner radius of every window (decoration:rounding)",
        "keywords": "border corner rounding radius window decoration"
    }, {
        "id": "apOpacityActive",
        "page": "appearance",
        "type": "slider",
        "default": 100,
        "hyprKey": "decoration:active_opacity",
        "persistKey": "hypr.activeOpacity",
        "min": 50,
        "max": 100,
        "step": 1,
        "scale": 0.01,
        "suffix": "%",
        "label": "Active window opacity",
        "description": "Focused windows (decoration:active_opacity)",
        "keywords": "opacity transparency active focused window see through"
    }, {
        "id": "apOpacityInactive",
        "page": "appearance",
        "type": "slider",
        "default": 100,
        "hyprKey": "decoration:inactive_opacity",
        "persistKey": "hypr.inactiveOpacity",
        "min": 50,
        "max": 100,
        "step": 1,
        "scale": 0.01,
        "suffix": "%",
        "label": "Inactive window opacity",
        "description": "Background windows (decoration:inactive_opacity)",
        "keywords": "opacity transparency inactive unfocused background window"
    }, {
        "id": "apOpacityFullscreen",
        "page": "appearance",
        "type": "slider",
        "default": 100,
        "hyprKey": "decoration:fullscreen_opacity",
        "persistKey": "hypr.fullscreenOpacity",
        "min": 50,
        "max": 100,
        "step": 1,
        "scale": 0.01,
        "suffix": "%",
        "label": "Fullscreen opacity",
        "description": "Fullscreen windows (decoration:fullscreen_opacity)",
        "keywords": "opacity transparency fullscreen window games video"
    }, {
        "id": "apPanelAlpha",
        "page": "appearance",
        "type": "choice",
        "default": 0,
        "source": "settings",
        "key": "appearance.transparency",
        "label": "Panel transparency",
        "description": "How much wallpaper shows through the bar pill, control center, settings window and aether picker",
        "options": [{
            "value": 0,
            "label": "Opaque"
        }, {
            "value": 15,
            "label": "15%"
        }, {
            "value": 30,
            "label": "30%"
        }, {
            "value": 45,
            "label": "45%"
        }],
        "keywords": "transparency transparent alpha panel pill bar control center settings glass see through"
    }, {
        "id": "apSectionBlur",
        "page": "appearance",
        "type": "section",
        "label": "Blur"
    }, {
        "id": "apBlurOn",
        "page": "appearance",
        "type": "hyprswitch",
        "default": false,
        "hyprKey": "decoration:blur:enabled",
        "persistKey": "hypr.blurEnabled",
        "label": "Blur effects",
        "description": "Master switch · windows change at once, the shell's glass on the next reload (decoration:blur:enabled)",
        "keywords": "blur frosted glass effect enable disable on off gaming performance fps"
    }, {
        "id": "apBlurSize",
        "page": "appearance",
        "type": "slider",
        "default": 4,
        "hyprKey": "decoration:blur:size",
        "persistKey": "hypr.blurSize",
        "min": 1,
        "max": 16,
        "step": 1,
        "suffix": "px",
        "label": "Blur size",
        "description": "Radius of the frost — ships 4 since the heat retune; 8 is the heavy frosted recipe (decoration:blur:size)",
        "keywords": "blur size radius strength soft hard heavy frosted lockscreen glass"
    }, {
        "id": "apBlurPasses",
        "page": "appearance",
        "type": "slider",
        "default": 1,
        "hyprKey": "decoration:blur:passes",
        "persistKey": "hypr.blurPasses",
        "min": 1,
        "max": 5,
        "step": 1,
        "label": "Blur passes",
        "description": "Blurs the blur again — ships 1; raise it with the size, 3 smears far past 1 and costs GPU (decoration:blur:passes)",
        "keywords": "blur passes pass smear smear quality gpu performance heavy soft"
    }, {
        "id": "apBlurPopups",
        "page": "appearance",
        "type": "hyprswitch",
        "default": false,
        "hyprKey": "decoration:blur:popups",
        "persistKey": "hypr.blurPopups",
        "label": "Blur popups",
        "description": "Frost xdg popups too — tray menu, control center panels, this window (decoration:blur:popups)",
        "keywords": "popup popups menu tray dropdown panel frost blur glass"
    }, {
        "id": "apBlurVibrancy",
        "page": "appearance",
        "type": "slider",
        "default": 0.1696,
        "hyprKey": "decoration:blur:vibrancy",
        "persistKey": "hypr.blurVibrancy",
        "min": 0,
        "max": 1,
        "step": 0.01,
        "label": "Blur vibrancy",
        "description": "How much colour bleeds back into the frosted area (decoration:blur:vibrancy)",
        "keywords": "vibrancy vibrance colour color tint saturation vivid bright blur"
    }, {
        "id": "apBlurReload",
        "page": "appearance",
        "type": "action",
        "command": ["qs", "ipc", "call", "settingsapp", "reload"],
        "verb": "Reload",
        "label": "Reload Hyprland",
        "description": "After Apply — re-reads the config so the shell's glass frosts at the new values (windows already changed live)",
        "keywords": "reload refresh restart config shell glass apply blur catch up"
    }, {
        "id": "bndEditor",
        "page": "bindings",
        "type": "keybinds",
        "label": "Keybinding editor",
        "description": "Search, add, remove, disable · writes ~/.config/hypr/binds.lua + reload",
        "keywords": "binding add keys shortcut chord command clash search remove disable turn off unbind binds lua"
    }, {
        "id": "cmpEditor",
        "page": "compose",
        "type": "xcompose",
        "label": "Compose sequences",
        "description": "Add or remove ~/.XCompose entries · applies to newly opened apps",
        "keywords": "compose sequence add remove xcompose multi_key dead key list"
    }, {
        "id": "animCard",
        "page": "animations",
        "type": "animcard",
        "hyprKey": "animations:enabled",
        "persistKey": "hypr.animationsEnabled",
        "label": "Motion controls",
        "description": "Global drives shell + compositor · each side also alone",
        "keywords": "animation motion speed spring bounce tween quickshell shell hyprland compositor window workspace global enable disable slow fast reduce"
    }, {
        "id": "fxRipple",
        "page": "animations",
        "type": "switch",
        "default": false,
        "key": "effects.ripple",
        "label": "Desktop ripples",
        "description": "Ripple rings where the desktop is clicked · motion + game mode gates still apply",
        "keywords": "ripple click ring effect decoration desktop water pulse shell"
    }, {
        "id": "fxEdgeLight",
        "page": "animations",
        "type": "switch",
        "default": false,
        "key": "effects.edgelight",
        "label": "Notification edge glow",
        "description": "Accent light sweeping around the bar pill when a notification lands",
        "keywords": "notification glow edge light bar pill alert effect decoration shell"
    }, {
        "id": "fxTone",
        "page": "animations",
        "type": "switch",
        "default": false,
        "key": "effects.tone",
        "label": "Alert tone",
        "description": "Short sound when the capsule flashes a high-priority event (plugging in the charger)",
        "keywords": "sound tone chime alert beep capsule plug charge notification audio effect shell"
    }, {
        "id": "ptrNumlock",
        "page": "pointer",
        "type": "hyprswitch",
        "default": false,
        "hyprKey": "input:numlock_by_default",
        "persistKey": "hypr.numlock",
        "label": "Num lock on at login",
        "description": "Start sessions with numlock lit · survives restarts",
        "keywords": "numlock keyboard login startup toggle"
    }, {
        "id": "ptrSensitivity",
        "page": "pointer",
        "type": "slider",
        "hyprKey": "input:sensitivity",
        "persistKey": "hypr.sensitivity",
        "default": 0,
        "min": -1,
        "max": 1,
        "step": 0.05,
        "label": "Sensitivity",
        "description": "How far the pointer travels · −1…1, 0 = no change · live via hyprctl getoption (input:sensitivity)",
        "keywords": "pointer sensitivity mouse speed acceleration number"
    }, {
        "id": "ptrAccel",
        "page": "pointer",
        "type": "buttons",
        "default": "",
        "hyprKey": "input:accel_profile",
        "persistKey": "hypr.accelProfile",
        "options": [{
            "label": "Default",
            "value": ""
        }, {
            "label": "Flat",
            "value": "flat"
        }, {
            "label": "Adaptive",
            "value": "adaptive"
        }],
        "label": "Acceleration",
        "description": "How the pointer picks up speed (input:accel_profile)",
        "keywords": "pointer accel profile default flat adaptive mouse acceleration"
    }, {
        "id": "ptrFollow",
        "page": "pointer",
        "type": "buttons",
        "default": 1,
        "hyprKey": "input:follow_mouse",
        "persistKey": "hypr.followMouse",
        "options": [{
            "label": "Off",
            "value": 0
        }, {
            "label": "On",
            "value": 1
        }, {
            "label": "Keyboard keeps focus",
            "value": 2
        }, {
            "label": "Without raising",
            "value": 3
        }],
        "label": "Focus follows mouse",
        "description": "Where keyboard focus goes as the pointer moves (input:follow_mouse)",
        "keywords": "focus follows mouse off on keyboard stays without raising click hover window"
    }, {
        "id": "ptrNaturalScroll",
        "page": "pointer",
        "type": "hyprswitch",
        "default": false,
        "hyprKey": "input:touchpad:natural_scroll",
        "persistKey": "hypr.naturalScroll",
        "label": "Natural scrolling",
        "description": "Scroll up moves content up (macOS style) · survives restarts",
        "keywords": "touchpad natural scroll direction inverted toggle"
    }, {
        "id": "ptrTapToClick",
        "page": "pointer",
        "type": "hyprswitch",
        "default": true,
        "hyprKey": "input:touchpad:tap_to_click",
        "persistKey": "hypr.tapToClick",
        "label": "Tap to click",
        "description": "A tap counts as a click · survives restarts",
        "keywords": "touchpad tap click gesture toggle"
    }, {
        "id": "ptrClickfinger",
        "page": "pointer",
        "type": "hyprswitch",
        "default": false,
        "hyprKey": "input:touchpad:clickfinger_behavior",
        "persistKey": "hypr.clickfinger",
        "label": "Two-finger right click",
        "description": "Off uses the lower-right corner instead · survives restarts",
        "keywords": "touchpad clickfinger right click two finger toggle"
    }, {
        "id": "ptrDisableTyping",
        "page": "pointer",
        "type": "hyprswitch",
        "default": true,
        "hyprKey": "input:touchpad:disable_while_typing",
        "persistKey": "hypr.disableWhileTyping",
        "label": "Disable while typing",
        "description": "Touchpad sleeps while keys are pressed · survives restarts",
        "keywords": "touchpad disable while typing palm toggle"
    }, {
        "id": "ptrScrollFactor",
        "page": "pointer",
        "type": "slider",
        "default": 1,
        "hyprKey": "input:scroll_factor",
        "hyprKeys": ["input:scroll_factor", "input:touchpad:scroll_factor"],
        "persistKey": "hypr.scrollFactor",
        "min": 0.1,
        "max": 3,
        "step": 0.1,
        "label": "Scroll speed",
        "description": "Wheel and two-finger steps land faster or slower · survives restarts",
        "keywords": "scroll speed factor wheel touchpad mouse scrolling fast slow"
    }, {
        "id": "secDisplays",
        "page": "display",
        "type": "section",
        "label": "Displays"
    }, {
        "id": "dspConnector",
        "page": "display",
        "type": "info",
        "value": "eDP-1 (this panel)",
        "label": "Connector",
        "description": "The laptop's internal panel connector — as reported at boot (static snapshot, not live)",
        "keywords": "display connector edp monitor laptop output edid"
    }, {
        "id": "dspMode",
        "page": "display",
        "type": "buttons",
        "default": "preferred",
        "readCommand": ["bash", "-c", "grep -m1 -oE 'mode *= *\"[^\"]*\"' $HOME/.config/hypr/monitors.lua | cut -d'\"' -f2"],
        "options": [{
            "label": "Preferred",
            "value": "preferred",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "mode", "preferred"]
        }, {
            "label": "1920×1080 · 60 Hz",
            "value": "1920x1080@60.06Hz",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "mode", "1920x1080@60.06Hz"]
        }],
        "label": "Resolution (built-in panel)",
        "description": "Writes monitors.lua (backup + luac check), then applies live",
        "keywords": "display resolution mode preferred refresh rate eDP persist"
    }, {
        "id": "dspScale",
        "page": "display",
        "type": "buttons",
        "default": "1",
        "readCommand": ["bash", "-c", "grep -m1 -oE 'scale *= *\"[^\"]*\"' $HOME/.config/hypr/monitors.lua | cut -d'\"' -f2"],
        "options": [{
            "label": "×1",
            "value": "1",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1"]
        }, {
            "label": "×1.2",
            "value": "1.2",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.2"]
        }, {
            "label": "×1.25",
            "value": "1.25",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.25"]
        }, {
            "label": "×1.5",
            "value": "1.5",
            "command": [Quickshell.shellDir + "/scripts/set-display.sh", "scale", "1.5"]
        }],
        "label": "Scale (built-in panel)",
        "description": "Steps persist into monitors.lua and apply live",
        "keywords": "display scale eDP laptop hidpi factor"
    }, {
        "id": "audOutVolume",
        "page": "audio",
        "type": "cmdslider",
        "readCommand": ["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
        "writeCommand": ["pactl", "set-sink-volume", "@DEFAULT_SINK@"],
        "min": 0,
        "max": 150,
        "step": 1,
        "suffix": "%",
        "label": "Output volume",
        "description": "0–150%, writes land live (pactl) — no Apply needed",
        "keywords": "audio volume output sound loud percent pactl"
    }, {
        "id": "audOutMute",
        "page": "audio",
        "type": "cmdswitch",
        "default": false,
        "readCommand": ["pactl", "get-sink-mute", "@DEFAULT_SINK@"],
        "readTrue": "Mute: yes",
        "command": ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"],
        "label": "Output muted",
        "description": "Mute or unmute everything you hear — pill shows live state",
        "keywords": "audio mute output sound silence pactl toggle"
    }, {
        "id": "audOutDevices",
        "page": "audio",
        "type": "dropdown",
        "source": "sinks",
        "label": "Output devices",
        "description": "Every sink PipeWire exposes — a pick makes it the default (pactl)",
        "keywords": "audio output device sink default headphones hdmi speakers"
    }, {
        "id": "audApps",
        "page": "audio",
        "type": "appmixer",
        "label": "App outputs",
        "description": "Every playing app as its own row — pick where each one sounds (live, per-app)",
        "keywords": "app application per app route output sink mixer move discord firefox browser music video sound"
    }, {
        "id": "audInVolume",
        "page": "audio",
        "type": "cmdslider",
        "readCommand": ["pactl", "get-source-volume", "@DEFAULT_SOURCE@"],
        "writeCommand": ["pactl", "set-source-volume", "@DEFAULT_SOURCE@"],
        "min": 0,
        "max": 150,
        "step": 1,
        "suffix": "%",
        "label": "Input volume",
        "description": "0–150%, writes land live (pactl) — no Apply needed",
        "keywords": "audio volume input microphone percent pactl"
    }, {
        "id": "audInMute",
        "page": "audio",
        "type": "cmdswitch",
        "default": false,
        "readCommand": ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"],
        "readTrue": "Mute: yes",
        "command": ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"],
        "label": "Input muted",
        "description": "Mute or unmute the microphone — pill shows live state",
        "keywords": "audio mute input microphone silence pactl toggle"
    }, {
        "id": "audInDevices",
        "page": "audio",
        "type": "dropdown",
        "source": "sources",
        "label": "Input devices",
        "description": "Every source PipeWire exposes — a pick makes it the default (pactl)",
        "keywords": "audio input device source default microphone headset"
    },
    {
        "id": "audVoice",
        "page": "audio",
        "type": "voicecard",
        "label": "Voice assistant",
        "description": "Dictate into the session and hear replies — SUPER+D, off until you set it up",
        "keywords": "voice assistant dictation speech whisper piper tts stt talk talkback super d reply spoken"
    }, {
        "id": "netWifi",
        "page": "network",
        "type": "cmdswitch",
        "readCommand": ["nmcli", "radio", "wifi"],
        "readTrue": "enabled",
        "command": ["bash", "-c", "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"],
        "label": "Wi-Fi",
        "description": "Radio on or off — pill shows live state (nmcli)",
        "keywords": "wifi wireless radio network toggle nmcli"
    }, {
        "id": "netConn",
        "page": "network",
        "type": "netcard",
        "label": "Wi-Fi connection",
        "description": "Live IP and gateway · band and DNS re-join the network to apply",
        "keywords": "ip address gateway band dns provider resolver wifi connection nmcli cloudflare google quad9"
    }, {
        "id": "netNetworks",
        "page": "network",
        "type": "netlist",
        "label": "Networks",
        "description": "Live scan list — signal, lock, connect / disconnect / forget, password prompt inline",
        "keywords": "wifi network list scan ssid connect password forget secured signal nearby"
    }, {
        "id": "netQr",
        "page": "network",
        "type": "action",
        "command": ["foot", "-e", "bash", "-c", Quickshell.shellDir + "/scripts/wifi-qr.sh; echo; read -p 'Press Enter to close' "],
        "verb": "Show…",
        "label": "Wi-Fi QR code",
        "description": "Scan to join — the active network as a terminal code · shows the password on screen",
        "keywords": "wifi qr code share join network scan"
    }, {
        "id": "btPower",
        "page": "bluetooth",
        "type": "cmdswitch",
        "readCommand": ["bash", "-c", "bluetoothctl show 2>/dev/null"],
        "readTrue": "Powered: yes",
        "command": ["bash", "-c", "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi"],
        "label": "Adapter power",
        "description": "BlueZ via bluetoothctl — pill shows live state",
        "keywords": "bluetooth adapter power on off bluez toggle"
    }, {
        "id": "btDevices",
        "page": "bluetooth",
        "type": "btlist",
        "label": "Devices (connected / paired / nearby)",
        "description": "Pair, connect, trust, forget with battery — live BlueZ discovery while shown",
        "keywords": "bluetooth device list pair connect forget headphones battery nearby discovery"
    }, {
        "id": "pwrCard",
        "page": "power",
        "type": "powercard",
        "label": "Battery",
        "description": "Charge, estimate, drawing and health — live from upower",
        "keywords": "battery charge percent time remaining full drawing watt health capacity upower"
    }, {
        "id": "pwrProfile",
        "page": "power",
        "type": "buttons",
        "default": "balanced",
        "readCommand": ["powerprofilesctl", "get"],
        "options": [{
            "label": "Power saver",
            "value": "power-saver",
            "command": ["powerprofilesctl", "set", "power-saver"]
        }, {
            "label": "Balanced",
            "value": "balanced",
            "command": ["powerprofilesctl", "set", "balanced"]
        }, {
            "label": "Performance",
            "value": "performance",
            "command": ["powerprofilesctl", "set", "performance"]
        }],
        "label": "Power profile",
        "description": "One global profile — same on battery or plugged in",
        "keywords": "power profile battery saver balanced performance plugged ac energy"
    }, {
        "id": "lkSectionSession",
        "page": "lock",
        "type": "section",
        "label": "Session lock"
    }, {
        "id": "lkStyle",
        "page": "lock",
        "type": "lockstyle",
        "settingsKey": "lock.style",
        "options": [{
            "label": "Classic",
            "value": "classic"
        }, {
            "label": "Card",
            "value": "card"
        }, {
            "label": "Minimal",
            "value": "minimal"
        }, {
            "label": "Magazine",
            "value": "magazine"
        }, {
            "label": "Clock",
            "value": "clock"
        }],
        "label": "Lock screen style",
        "description": "The layout shown while locked · the card previews the real one",
        "keywords": "lock screen style layout look design version classic card minimal magazine clock giant time widget quickshell"
    }, {
        "id": "lkNow",
        "page": "lock",
        "type": "action",
        "command": ["qs", "ipc", "call", "lock", "lock"],
        "verb": "Lock now",
        "label": "Lock this session",
        "description": "Lock immediately — the same call Super+L makes",
        "keywords": "lock now session away secure password super+l immediately"
    }, {
        "id": "lkScreensaver",
        "page": "lock",
        "type": "buttons",
        "default": 150,
        "readCommand": [Quickshell.shellDir + "/scripts/set-idle.sh", "get", "screensaver"],
        "options": [{
            "label": "1 min",
            "value": 60,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "screensaver", "60"]
        }, {
            "label": "2½ min",
            "value": 150,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "screensaver", "150"]
        }, {
            "label": "5 min",
            "value": 300,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "screensaver", "300"]
        }, {
            "label": "10 min",
            "value": 600,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "screensaver", "600"]
        }, {
            "label": "15 min",
            "value": 900,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "screensaver", "900"]
        }],
        "label": "Screensaver after",
        "description": "Idle time before the screensaver starts · writes shell.json, applies live",
        "keywords": "idle screensaver timeout dim seconds minutes shell.json"
    }, {
        "id": "ssStyle",
        "page": "lock",
        "type": "choice",
        "default": "flip",
        "source": "settings",
        "key": "screensaver.style",
        "label": "Screensaver style",
        "description": "Flip clock — this shell, static between flips, ~0 CPU · Pipes — the animated terminal",
        "options": [{
            "value": "flip",
            "label": "Flip clock"
        }, {
            "value": "pipes",
            "label": "Pipes terminal"
        }],
        "keywords": "screensaver style flip clock fliqlo fliplo split flap flipit pipes terminal animation cpu saver idle"
    }, {
        "id": "lkLockAfter",
        "page": "lock",
        "type": "buttons",
        "default": 300,
        "readCommand": [Quickshell.shellDir + "/scripts/set-idle.sh", "get", "lock"],
        "options": [{
            "label": "1 min",
            "value": 60,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "lock", "60"]
        }, {
            "label": "2 min",
            "value": 120,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "lock", "120"]
        }, {
            "label": "5 min",
            "value": 300,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "lock", "300"]
        }, {
            "label": "10 min",
            "value": 600,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "lock", "600"]
        }, {
            "label": "15 min",
            "value": 900,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "lock", "900"]
        }],
        "label": "Lock after",
        "description": "Idle time before the session locks (the Super+L path) · applies live",
        "keywords": "idle lock timeout seconds minutes shell.json session"
    }, {
        "id": "lkSleepAfter",
        "page": "lock",
        "type": "buttons",
        "default": 1800,
        "readCommand": [Quickshell.shellDir + "/scripts/set-idle.sh", "get", "sleep"],
        "options": [{
            "label": "Never",
            "value": 0,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "0"]
        }, {
            "label": "15 min",
            "value": 900,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "900"]
        }, {
            "label": "30 min",
            "value": 1800,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "1800"]
        }, {
            "label": "45 min",
            "value": 2700,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "2700"]
        }, {
            "label": "60 min",
            "value": 3600,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "3600"]
        }, {
            "label": "2 hours",
            "value": 7200,
            "command": [Quickshell.shellDir + "/scripts/set-idle.sh", "set", "sleep", "7200"]
        }],
        "label": "Sleep after",
        "description": "Idle time before the machine locks (if not already) and suspends to RAM · applies live",
        "keywords": "idle sleep suspend snooze hibernate power save timeout seconds minutes never ram"
    }, {
        "id": "lkSectionLogin",
        "page": "lock",
        "type": "section",
        "label": "Login screen (SDDM greeter — before the session)"
    }, {
        "id": "sddmTheme",
        "page": "lock",
        "type": "buttons",
        "default": "selah",
        "readCommand": [Quickshell.shellDir + "/scripts/selah-sddm.sh", "current"],
        "options": [{
            "label": "Selah",
            "value": "selah",
            "command": [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "selah"]
        }, {
            "label": "Elarun",
            "value": "elarun",
            "command": [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "elarun"]
        }, {
            "label": "Maldives",
            "value": "maldives",
            "command": [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "maldives"]
        }, {
            "label": "Maya",
            "value": "maya",
            "command": [Quickshell.shellDir + "/scripts/selah-sddm.sh", "set", "maya"]
        }],
        "label": "Login screen theme",
        "description": "SDDM greeter — Selah carries your theme · applies next login",
        "keywords": "sddm login greeter theme boot log screen selah elarun maldives maya"
    }, {
        "id": "sddmSetup",
        "page": "lock",
        "type": "action",
        "command": ["foot", "-e", "bash", "-c", Quickshell.shellDir + "/scripts/selah-sddm.sh setup-help; echo; read -p 'Press Enter to close' "],
        "verb": "Show setup",
        "label": "One-time root setup",
        "description": "Opens the two commands that let chips apply instantly — paste once, password once",
        "keywords": "sddm login root sudo setup helper install password once auth"
    }, {
        "id": "sddmSync",
        "page": "lock",
        "type": "info",
        "value": "Auto",
        "label": "Wallpaper & palette",
        "description": "Always on — not a setting · the greeter re-syncs to your theme on every switch (switch-theme.sh hook)",
        "keywords": "sddm wallpaper palette colors sync greeter background theme match"
    }, {
        "id": "secDateTime",
        "page": "display",
        "type": "section",
        "label": "Date & Time"
    }, {
        "id": "dtCard",
        "page": "display",
        "type": "timecard",
        "label": "Clock & date",
        "description": "Ticking time, NTP status and a searchable timezone picker (admin auth)",
        "keywords": "timezone clock time ntp sync resync date zone region"
    }, {
        "id": "defBrowser",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "browser",
        "label": "Browser",
        "description": "Links from apps and Super+B (http · https · .html)",
        "keywords": "default browser firefox chrome chromium web link html http url"
    }, {
        "id": "defTerminal",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "terminal",
        "label": "Terminal",
        "description": "Super+Return opens whatever you pick here",
        "keywords": "default terminal emulator foot kitty alacritty shell command console"
    }, {
        "id": "defFileman",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "filemanager",
        "label": "File manager",
        "description": "Super+E and every “open folder” action (inode/directory)",
        "keywords": "default files file manager folder nautilus thunar dolphin explorer"
    }, {
        "id": "defEditor",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "editor",
        "label": "Text editor",
        "description": "Double-clicked text, code and csv files",
        "keywords": "default editor text code vim gedit kate vscode notepad csv"
    }, {
        "id": "defImage",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "image",
        "label": "Image viewer",
        "description": "png · jpeg · gif · webp · svg · tiff",
        "keywords": "default image picture photo viewer png jpg sxiv imv eog loupe"
    }, {
        "id": "defVideo",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "video",
        "label": "Video player",
        "description": "mp4 · mkv · webm · avi · mpeg",
        "keywords": "default video movie player mpv vlc celluloid film"
    }, {
        "id": "defAudio",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "audio",
        "label": "Audio player",
        "description": "mp3 · flac · ogg · wav · m4a",
        "keywords": "default audio music player mp3 flac song sound"
    }, {
        "id": "defPdf",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "pdf",
        "label": "PDF reader",
        "description": "application/pdf documents",
        "keywords": "default pdf reader viewer evince zathura mupdf document"
    }, {
        "id": "defArchive",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "archive",
        "label": "Archive manager",
        "description": "zip · tar · gzip · 7z · rar",
        "keywords": "default archive zip extract tar 7z rar compression file-roller"
    }, {
        "id": "defOffice",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "office",
        "label": "Word documents",
        "description": "odt · doc · docx · rtf",
        "keywords": "default office word document writer libreoffice odt docx"
    }, {
        "id": "defSheet",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "sheet",
        "label": "Spreadsheets",
        "description": "ods · xls · xlsx",
        "keywords": "default spreadsheet excel sheet calc xlsx ods numbers"
    }, {
        "id": "defSlide",
        "page": "defaults",
        "type": "dropdown",
        "source": "apps",
        "role": "slide",
        "label": "Presentations",
        "description": "odp · ppt · pptx",
        "keywords": "default presentation powerpoint slides impress odp pptx keynote"
    }, {
        "id": "upDesktop",
        "page": "updates",
        "type": "info",
        "source": "repoupdate",
        "label": "Desktop (selah)",
        "description": "This clone vs the GitHub repo it came from",
        "keywords": "update desktop selah github repo deploy pull version sync"
    }, {
        "id": "upPackages",
        "page": "updates",
        "type": "info",
        "source": "pkgupdates",
        "label": "System packages",
        "description": "Pending pacman and AUR updates",
        "keywords": "update packages pacman aur yay system pending versions"
    }, {
        "id": "upCheck",
        "page": "updates",
        "type": "action",
        "command": ["qs", "ipc", "call", "updates", "check"],
        "verb": "Check now",
        "label": "Check for updates",
        "description": "Re-run both checks immediately",
        "keywords": "check refresh now search sync update lookup"
    }, {
        "id": "upApply",
        "page": "updates",
        "type": "action",
        "command": ["qs", "ipc", "call", "updates", "apply"],
        "verb": "Update",
        "label": "Update the desktop",
        "description": "git pull + re-run install.sh — no sudo, no packages",
        "keywords": "update desktop pull git apply upgrade selah fresh new"
    }, {
        "id": "upUpgrade",
        "page": "updates",
        "type": "action",
        "command": ["qs", "ipc", "call", "updates", "upgrade"],
        "verb": "Update all",
        "label": "Update system packages",
        "description": "yay -Syu in a terminal (asks for your password)",
        "keywords": "upgrade packages system yay syu terminal update all"
    }, {
        "id": "nvmNumber",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.number",
        "label": "Line numbers",
        "description": "Stored pref; applies via omasettings nvim set number (options.lua)",
        "keywords": "nvim vim line numbers gutter number"
    }, {
        "id": "nvmRelNumber",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.relativeNumber",
        "label": "Relative line numbers",
        "description": "Stored pref; applies via omasettings nvim set relativenumber",
        "keywords": "nvim vim relative line numbers gutter"
    }, {
        "id": "nvmSign",
        "page": "nvim",
        "type": "buttons",
        "default": "yes",
        "options": [{
            "label": "Always",
            "value": "yes",
            "command": ["omasettings", "nvim", "set", "signcolumn", "yes"]
        }, {
            "label": "When needed",
            "value": "auto",
            "command": ["omasettings", "nvim", "set", "signcolumn", "auto"]
        }, {
            "label": "Never",
            "value": "no",
            "command": ["omasettings", "nvim", "set", "signcolumn", "no"]
        }],
        "label": "Sign column",
        "description": "Where git marks and diagnostics appear · needs options.lua writer",
        "keywords": "nvim vim sign column always auto never git diagnostics"
    }, {
        "id": "nvmWrap",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.wrap",
        "label": "Wrap long lines",
        "description": "Stored pref; applies via omasettings nvim set wrap",
        "keywords": "nvim vim wrap long lines textwidth switch"
    }, {
        "id": "nvmCursorLine",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.cursorLine",
        "label": "Highlight the current line",
        "description": "Stored pref; applies via omasettings nvim set cursorline",
        "keywords": "nvim vim cursor line highlight current switch"
    }, {
        "id": "nvmColorColumn",
        "page": "nvim",
        "type": "info",
        "value": "—",
        "label": "Column guide (not wired)",
        "description": "Static snapshot — nothing reads your config · astrocore.lua sets no colorcolumn (current: none) · needs text row",
        "keywords": "nvim vim colorcolumn column guide ruler text"
    }, {
        "id": "nvmScrolloff",
        "page": "nvim",
        "type": "info",
        "value": "0",
        "label": "Keep visible above and below (not wired)",
        "description": "Static snapshot — astrocore.lua sets no scrolloff (current: 0) · needs number row",
        "keywords": "nvim vim scrolloff context lines number"
    }, {
        "id": "nvmSpell",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.spell",
        "label": "Spell checking",
        "description": "Stored pref; applies via omasettings nvim set spell",
        "keywords": "nvim vim spell spellcheck grammar switch"
    }, {
        "id": "nvmExpandTab",
        "page": "nvim",
        "type": "switch",
        "default": false,
        "key": "nvim.expandTab",
        "label": "Spaces instead of tabs",
        "description": "Stored pref; applies via omasettings nvim set expandtab",
        "keywords": "nvim vim expandtab spaces tabs indent switch"
    }, {
        "id": "nvmShiftwidth",
        "page": "nvim",
        "type": "info",
        "value": "2",
        "label": "Indent width (not wired)",
        "description": "Static snapshot — unset in astrocore.lua, follows the tab width (current: 2) · needs number row",
        "keywords": "nvim vim shiftwidth indent spaces number"
    }, {
        "id": "nvmTabstop",
        "page": "nvim",
        "type": "info",
        "value": "2",
        "label": "Tab width (not wired)",
        "description": "Static snapshot — unset in astrocore.lua, AstroNvim ships 2 (current: 2) · needs number row",
        "keywords": "nvim vim tab tab width spaces number"
    }, {
        "id": "wgMaster",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showWidgets",
        "label": "Desktop widgets",
        "description": "Master switch for everything below · double-click empty desktop or use Arrange to place them",
        "keywords": "widgets desktop arrange grid studio enable show wallpaper"
    }, {
        "id": "wgArrange",
        "page": "widgets",
        "type": "action",
        "command": ["bash", "-c", "qs ipc call settings set widgets.showWidgets true; sleep 0.3; qs ipc call widgets edit"],
        "verb": "Arrange…",
        "label": "Arrange mode",
        "description": "Grid overlay: drag, resize, lock, remove · + opens quick-add, Esc leaves",
        "keywords": "arrange edit move resize grid layout studio quick add position"
    }, {
        "id": "wgSectionClock",
        "page": "widgets",
        "type": "section",
        "label": "Clocks & time"
    }, {
        "id": "wgClock",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showClock",
        "label": "Digital clock",
        "description": "The big time over the wallpaper",
        "keywords": "clock digital time hours minutes big veil"
    }, {
        "id": "wgClockStyle",
        "page": "widgets",
        "type": "choice",
        "default": "veil",
        "source": "settings",
        "key": "widgets.digitalClockStyle",
        "label": "Clock style",
        "options": [{
            "value": "veil",
            "label": "Veil"
        }, {
            "value": "bloom",
            "label": "Bloom"
        }, {
            "value": "orbit",
            "label": "Orbit"
        }, {
            "value": "script",
            "label": "Script"
        }, {
            "value": "stack",
            "label": "Stack"
        }, {
            "value": "condensed",
            "label": "Condensed"
        }],
        "description": "Which digital clock variant shows",
        "keywords": "clock style variant veil bloom orbit script stack condensed"
    }, {
        "id": "wgAnalog",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showAnalogClock",
        "label": "Analog clock",
        "description": "Face with hands · style below",
        "keywords": "analog watch hands clock face classic minimal shape"
    }, {
        "id": "wgAnalogStyle",
        "page": "widgets",
        "type": "choice",
        "default": "classic",
        "source": "settings",
        "key": "widgets.analogClockStyle",
        "label": "Analog style",
        "options": [{
            "value": "classic",
            "label": "Classic"
        }, {
            "value": "minimal",
            "label": "Minimal"
        }, {
            "value": "shape",
            "label": "Shape"
        }],
        "description": "Classic ticks, stripped minimal, or a Material-shape face",
        "keywords": "analog style classic minimal shape face ticks"
    }, {
        "id": "wgDate",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showDateWidget",
        "label": "Date",
        "description": "Day and date card · style below",
        "keywords": "date day month weekday calendar card bold accent shape"
    }, {
        "id": "wgDateStyle",
        "page": "widgets",
        "type": "choice",
        "default": "bold",
        "source": "settings",
        "key": "widgets.dateWidgetStyle",
        "label": "Date style",
        "options": [{
            "value": "bold",
            "label": "Bold"
        }, {
            "value": "accent",
            "label": "Accent"
        }, {
            "value": "shape",
            "label": "Shape"
        }],
        "description": "Which date variant shows",
        "keywords": "date style bold accent shape variant"
    }, {
        "id": "wgSectionWeather",
        "page": "widgets",
        "type": "section",
        "label": "Weather"
    }, {
        "id": "wgWeatherForecast",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showWeatherForecast",
        "label": "Forecast",
        "description": "Three-day outlook from wttr.in",
        "keywords": "weather forecast days outlook rain temperature"
    }, {
        "id": "wgWeatherHourly",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showWeatherHourly",
        "label": "Hourly",
        "description": "Next hours strip with feels-like and UV",
        "keywords": "weather hourly hours strip uv feels like"
    }, {
        "id": "wgSunArc",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSunArc",
        "label": "Sun arc",
        "description": "Sunrise-to-sunset arc with the current position",
        "keywords": "sun arc sunrise sunset daylight solar"
    }, {
        "id": "wgMoonPhase",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMoonPhase",
        "label": "Moon phase",
        "description": "Current phase and illumination",
        "keywords": "moon phase lunar illumination crescent"
    }, {
        "id": "wgWeatherShape",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showWeatherShape",
        "label": "Weather shape",
        "description": "Condition glyph on a Material shape",
        "keywords": "weather shape glyph icon material"
    }, {
        "id": "wgSectionCalendar",
        "page": "widgets",
        "type": "section",
        "label": "Calendar"
    }, {
        "id": "wgCalMini",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarMini",
        "label": "Mini",
        "description": "Compact month grid",
        "keywords": "calendar mini month grid compact"
    }, {
        "id": "wgCalYarn",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarYarn",
        "label": "Yarn",
        "description": "Month strip with today marked",
        "keywords": "calendar yarn strip month today"
    }, {
        "id": "wgCalAlmanac",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarAlmanac",
        "label": "Almanac",
        "description": "Dates, week number and daylight in one card",
        "keywords": "calendar almanac week number daylight date"
    }, {
        "id": "wgCalTorn",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarTorn",
        "label": "Torn",
        "description": "Torn-paper day page",
        "keywords": "calendar torn paper page day"
    }, {
        "id": "wgCalWindows",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarWindows",
        "label": "Windows",
        "description": "Grid of upcoming day windows",
        "keywords": "calendar windows grid upcoming days"
    }, {
        "id": "wgCalDaylight",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarDaylight",
        "label": "Daylight",
        "description": "Today's light curve from sunrise to sunset",
        "keywords": "calendar daylight light curve sunrise sunset"
    }, {
        "id": "wgCalYear",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarYear",
        "label": "Year",
        "description": "Year progress with elapsed fraction",
        "keywords": "calendar year progress elapsed percent"
    }, {
        "id": "wgCalStamp",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarStamp",
        "label": "Stamp",
        "description": "Postage-stamp day tile",
        "keywords": "calendar stamp tile day date"
    }, {
        "id": "wgCalMoon",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showCalendarMoon",
        "label": "Moon calendar",
        "description": "Month with moon phases per day",
        "keywords": "calendar moon phases month lunar"
    }, {
        "id": "wgSectionProductivity",
        "page": "widgets",
        "type": "section",
        "label": "Productivity"
    }, {
        "id": "wgTasks",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showTaskList",
        "label": "Tasks",
        "description": "Checklist over the bar's task store",
        "keywords": "tasks todo checklist done productivity"
    }, {
        "id": "wgSticky",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showStickyNote",
        "label": "Sticky note",
        "description": "One pinned note on the desktop",
        "keywords": "sticky note memo pinned text"
    }, {
        "id": "wgPomodoro",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showPomodoro",
        "label": "Pomodoro",
        "description": "Focus timer with the shell's pomodoro state",
        "keywords": "pomodoro timer focus break productivity"
    }, {
        "id": "wgWorldClock",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showWorldClock",
        "label": "World clock",
        "description": "Other timezones in rows",
        "keywords": "world clock timezone time zones cities"
    }, {
        "id": "wgSectionMusic",
        "page": "widgets",
        "type": "section",
        "label": "Music (needs a player)"
    }, {
        "id": "wgMusicExpressive",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicExpressive",
        "label": "Expressive",
        "description": "Art, title and a wavy progress bar",
        "keywords": "music expressive art progress player mpris"
    }, {
        "id": "wgMusicTicket",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicTicket",
        "label": "Ticket",
        "description": "Concert-ticket strip of the current track",
        "keywords": "music ticket strip track concert"
    }, {
        "id": "wgMusicPoster",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicPoster",
        "label": "Poster",
        "description": "Album art as a poster with credits",
        "keywords": "music poster album art credits"
    }, {
        "id": "wgMusicTuner",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicTuner",
        "label": "Radio tuner",
        "description": "Dial-styled now-playing",
        "keywords": "music radio tuner dial now playing"
    }, {
        "id": "wgMusicWaveform",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicWaveform",
        "label": "Waveform",
        "description": "Track as a waveform line (no live audio needed)",
        "keywords": "music waveform line track"
    }, {
        "id": "wgMusicCapsule",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicCapsule",
        "label": "Capsule",
        "description": "Pill with art, title and transport",
        "keywords": "music capsule pill transport controls"
    }, {
        "id": "wgMusicGlance",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicGlance",
        "label": "Glance line",
        "description": "One-line now-playing",
        "keywords": "music glance line minimal now playing"
    }, {
        "id": "wgMusicFlap",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicFlap",
        "label": "Split-flap",
        "description": "Board that flips the title letter by letter",
        "keywords": "music split flap board letters flip"
    }, {
        "id": "wgMusicBento",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicBento",
        "label": "Bento",
        "description": "Grid of art, track and level cells",
        "keywords": "music bento grid cells art levels"
    }, {
        "id": "wgMusicRibbon",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicRibbon",
        "label": "Edge ribbon",
        "description": "Ribbon hugging the screen edge",
        "keywords": "music ribbon edge border marquee"
    }, {
        "id": "wgMusicNeon",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicNeon",
        "label": "Neon sign",
        "description": "Glowing sign of the current track",
        "keywords": "music neon glow sign glow"
    }, {
        "id": "wgMusicTerminal",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showMusicTerminal",
        "label": "Terminal",
        "description": "Now-playing as terminal output",
        "keywords": "music terminal console cli now playing"
    }, {
        "id": "wgSectionSystem",
        "page": "widgets",
        "type": "section",
        "label": "System"
    }, {
        "id": "wgSysMonitor",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSystemMonitor",
        "label": "System monitor",
        "description": "CPU, memory and GPU graphs",
        "keywords": "system monitor cpu memory gpu graphs sparkline usage"
    }, {
        "id": "wgSysMonitorStyle",
        "page": "widgets",
        "type": "choice",
        "default": "default",
        "source": "settings",
        "key": "widgets.systemMonitorStyle",
        "label": "Monitor style",
        "options": [{
            "value": "default",
            "label": "Monitor"
        }, {
            "value": "compact",
            "label": "Compact"
        }, {
            "value": "pulse",
            "label": "Pulse"
        }],
        "description": "Full graphs, slim rows, or the pulse layout",
        "keywords": "monitor style default compact pulse graphs"
    }, {
        "id": "wgBattery",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showBattery",
        "label": "Battery",
        "description": "Charge gauge for the laptop battery",
        "keywords": "battery charge gauge ring shape power"
    }, {
        "id": "wgBatteryStyle",
        "page": "widgets",
        "type": "choice",
        "source": "settings",
        "key": "widgets.batteryStyle",
        "label": "Battery style",
        "options": [{
            "value": "ring",
            "label": "Ring"
        }, {
            "value": "shape",
            "label": "Shape"
        }],
        "description": "Circular gauge or Material-shape face",
        "keywords": "battery style ring shape gauge"
    }, {
        "id": "wgNetGraph",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showNetworkGraph",
        "label": "Network",
        "description": "Throughput graph with totals",
        "keywords": "network graph throughput upload download speed totals"
    }, {
        "id": "wgSysCockpit",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysCockpit",
        "label": "Cockpit",
        "description": "Dials for CPU, memory, GPU and temps",
        "keywords": "system cockpit dials gauges cpu gpu temp"
    }, {
        "id": "wgSysBlueprint",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysBlueprint",
        "label": "Blueprint",
        "description": "Wireframe readout of every metric",
        "keywords": "system blueprint wireframe metrics technical"
    }, {
        "id": "wgSysVitals",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysVitals",
        "label": "Vitals",
        "description": "Live traces of CPU, memory and temperature",
        "keywords": "system vitals traces cpu memory temp sparkline"
    }, {
        "id": "wgSysForecast",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysForecast",
        "label": "Forecast",
        "description": "Metric bars with a prediction tail",
        "keywords": "system forecast bars prediction load"
    }, {
        "id": "wgSysFlask",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysFlask",
        "label": "Flask",
        "description": "Metrics as filling levels",
        "keywords": "system flask levels fill liquid"
    }, {
        "id": "wgSysThermo",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysThermo",
        "label": "Thermometer",
        "description": "CPU and GPU temperatures",
        "keywords": "system thermometer temperature cpu gpu thermal"
    }, {
        "id": "wgSysCreature",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysCreature",
        "label": "Creature",
        "description": "A creature fed by your load",
        "keywords": "system creature pet mascot load fun"
    }, {
        "id": "wgSysCells",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysCells",
        "label": "Cell stack",
        "description": "Per-core activity cells",
        "keywords": "system cells per core cpu threads activity"
    }, {
        "id": "wgSysShape",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysShape",
        "label": "Shape shifter",
        "description": "System health as a morphing mood shape",
        "keywords": "system shape shifter mood morph health"
    }, {
        "id": "wgSysHourglass",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysHourglass",
        "label": "Hourglass",
        "description": "Uptime and load as falling sand",
        "keywords": "system hourglass uptime load sand"
    }, {
        "id": "wgSysFillNumber",
        "page": "widgets",
        "type": "switch",
        "default": false,
        "key": "widgets.showSysFillNumber",
        "label": "Fill number",
        "description": "One big metric, pick which",
        "keywords": "system fill number big metric single"
    }]

    // ————————————— hyprland option helpers —————————————
    // one shape shared by the slider / hyprswitch / dropdown / buttons
    // rows: eval writes a nested hl.config table (keyword shape —
    // decoration:rounding becomes decoration = { rounding = … }),
    // getoption output comes back typed. Probed against the live
    // compositor: all shapes return ok.
    function hyprLuaValue(v) {
        if (typeof v === "boolean")
            return v ? "true" : "false";

        if (typeof v === "number")
            return String(v);

        return JSON.stringify(String(v));
    }

    function hyprEval(key, luaVal) {
        const parts = String(key).split(":");
        let s = "hl.config({ ";
        for (let i = 0; i < parts.length - 1; i++) s += parts[i] + " = { "
        s += parts[parts.length - 1] + " = " + luaVal;
        for (let i = 0; i < parts.length; i++) s += " }"
        s += " )";
        return s;
    }

    // hyprctl getoption first line: "int: 10" · "float: 1.000000" ·
    // "bool: true" · "str: dwindle" · "css gap data: 5 5 5 5"
    function hyprParse(text) {
        const line = String(text).split("\n")[0].trim();
        if (line.startsWith("bool:"))
            return line.slice(5).trim() === "true";

        if (line.startsWith("int:"))
            return parseInt(line.slice(4).trim(), 10);

        if (line.startsWith("float:"))
            return parseFloat(line.slice(6).trim());

        if (line.startsWith("str:")) {
            const s = line.slice(4).trim();
            // Lua-Hyprland prints [[EMPTY]] for an empty string option
            return s === "[[EMPTY]]" ? "" : s;
        }
        if (line.startsWith("css gap data:")) {
            const n = parseFloat(line.slice(13).trim().split(/\s+/)[0]);
            return isNaN(n) ? null : n;
        }
        const m = line.match(/^-?\d+(\.\d+)?/);
        return m ? parseFloat(m[0]) : null;
    }

}
