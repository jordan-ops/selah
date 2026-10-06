#!/usr/bin/env python3
# Wi-Fi QR for the settings app's Network page.
#
# nmcli reads the active connection's SSID and PSK (-s: secrets are
# owner-readable, no root), segno (vendored in scripts/vendor, BSD-3)
# encodes the standard WIFI: join payload, and the matrix prints as
# half-block glyphs on a truecolor white plate so a phone camera can
# scan it straight off the terminal. One character = two modules tall,
# quiet zone included, so the whole code stays under 50 columns and
# never wraps (a wrapped QR is an unscannable QR).
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor"))
import segno  # noqa: E402


def nmcli(*args):
    out = subprocess.run(["nmcli", "-s", "-t", *args],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("nmcli failed: " + out.stderr.strip())
    return out.stdout


def unescape(s):
    # nmcli -t escapes '\' and ':' with a backslash
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(s[i + 1])
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def field_unescape(s):
    # WIFI payloads escape \ ; , : " inside SSID/PSK (WIFI spec)
    return "".join("\\" + c if c in '\\;:,"' else c for c in s)


conns = []
for line in nmcli("-f", "TYPE,NAME", "connection", "show", "--active").splitlines():
    if ":" in line:
        t, n = line.split(":", 1)
        conns.append((unescape(t), unescape(n)))
wifi = next((name for t, name in conns if t == "802-11-wireless"), None)
if not wifi:
    sys.exit("No active Wi-Fi connection.")

fields = {}
for line in nmcli("-f", "802-11-wireless.ssid,802-11-wireless-security.psk",
                  "connection", "show", wifi).splitlines():
    if ":" in line:
        k, v = line.split(":", 1)
        fields[k] = unescape(v)
ssid = fields.get("802-11-wireless.ssid", "")
psk = fields.get("802-11-wireless-security.psk", "")
if not ssid:
    sys.exit("Could not read the SSID of the active connection.")

auth = "WPA" if psk else "nopass"
payload = "WIFI:T:%s;S:%s;" % (auth, field_unescape(ssid))
if psk:
    payload += "P:%s;" % field_unescape(psk)
payload += ";"

qr = segno.make(payload, error="m")
m = [list(row) for row in qr.matrix_iter(border=0)]
n = len(m)
quiet = 4


def color(black):
    return (0, 0, 0) if black else (255, 255, 255)


def cell(x, y):
    if quiet <= y < quiet + n and quiet <= x < quiet + n:
        return m[y - quiet][x - quiet]
    return False


total_rows = n + 2 * quiet
if total_rows % 2:
    total_rows += 1  # keep the pairing even — one white row at the bottom

print()
print("  Scan to join  \u2014  %s" % ssid)
print()
for y in range(0, total_rows, 2):
    parts = []
    for x in range(0, n + 2 * quiet):
        r1, g1, b1 = color(cell(x, y))       # upper half -> fg
        r2, g2, b2 = color(cell(x, y + 1))   # lower half -> bg
        parts.append("\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm\u2580"
                     % (r1, g1, b1, r2, g2, b2))
    parts.append("\x1b[0m")
    print("".join(parts))
print()
