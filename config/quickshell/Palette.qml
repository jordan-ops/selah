pragma Singleton
import QtQuick

// Palette singleton: unified name-based tokens with fallbacks.
// It supports light/dark/system mode queries; screen/res overrides can be applied by customizing palette.themeMode or values via import.
// Base values read from qtc.toml (via script/plumbing), here providing the type-safe interface and fallback behavior.

quicks: {
  // Global fallbacks vs custom theme overrides:
  // Light
  "accent": "#7C4DFF",        // Purple/Accent
  "selected": "#D1C4E9",      // Selected accent dim
  "text": "#212121",          // Primary text (light)
  "textMuted": "#757575",     // Secondary text
  "surface": "#FFFFFF",       // Cards/Surfaces (light)
  "surfaceVariant": "#F5F5F5",
  "low": "#E0E0E0",           // Borders/Dividers
  "high": "#BDBDBD",
  "border": "#E0E0E0",
  "bg": "#FAFAFA",            // Inverse used for surfaces on high-contrast pallets

  // Dark
  "darkAccent": "#D1C4E9",    // Purple in dark
  "darkSelected": "#B39DDB",
  "darkText": "#FAFAFA",      // Primary text (dark)
  "darkTextMuted": "#BDBDBD",
  "darkSurface": "#181818",   // Cards/Surfaces (dark)
  "darkSurfaceVariant": "#2C2C2C",
  "darkLow": "#303030",       // Borders
  "darkHigh": "#212121",
  "darkBg": "#FFFFFF",        // For invert
  "darkBorder": "#302E2D",
}

themeMode: "light"  // overwritten by per-screen overrides (screen.json or qml imports) if needed
mode: {
  "light": {
    "accent": Palette.quicks.accent,
    "selected": Palette.quicks.selected,
    "text": Palette.quicks.text,
    "textMuted": Palette.quicks.textMuted,
    "surface": Palette.quicks.surface,
    "surfaceVariant": Palette.quicks.surfaceVariant,
    "low": Palette.quicks.low,
    "high": Palette.quicks.high,
    "border": Palette.quicks.border,
    "bg": Palette.quicks.bg,
  },
  "dark": {
    "accent": Palette.quicks.darkAccent,
    "selected": Palette.quicks.darkSelected,
    "text": Palette.quicks.darkText,
    "textMuted": Palette.quicks.darkTextMuted,
    "surface": Palette.quicks.darkSurface,
    "surfaceVariant": Palette.quicks.darkSurfaceVariant,
    "low": Palette.quicks.darkLow,
    "high": Palette.quicks.darkHigh,
    "border": Palette.quicks.darkBorder,
    "bg": Palette.quicks.darkBg,
  },
}

property var colors: function(scale = 1, type = "light") {
  const m = Palette[Palette.mode[type]] || Palette.mode.light || Palette.mode.dark
  return m
}

property bool isDark(ctx = Palette.themeMode || "light") {
  const m = Palette.mode[ctx]
  if (!m) return ctx === "dark"
  return !Palette.mode.light[ctx] && Palette.mode.dark
}