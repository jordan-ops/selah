.pragma library
// Ported from Nebula's MatrialShapes/shape-library.js (GPL-3.0) —
// the name whitelist the shapeLock pickers validate against.

var names = [
    "circle", "square", "slanted", "arch", "fan", "arrow", "semiCircle", "oval",
    "pill", "triangle", "diamond", "clamShell", "pentagon", "gem", "sunny", "verySunny",
    "cookie4", "cookie6", "cookie7", "cookie9", "cookie12", "ghostish", "clover4", "clover8",
    "burst", "softBurst", "boom", "softBoom", "flower", "puffy", "puffyDiamond", "pixelCircle",
    "pixelTriangle", "bun", "heart", "hexagon", "octagon", "star5", "sparkle", "cross",
    "cookie3", "cookie5", "cookie8", "cookie10", "scallop", "clover3", "squircle", "pebble",
    "blob", "leaf", "drop", "shield", "bolt", "chevron", "moon", "pixelHeart"
]

function get(name) {
    return names.indexOf(name) >= 0 ? name : null
}
