#!/bin/sh
# Terminal wrapper for wifi-qr.py — the settings app's Network page runs
# this inside `foot -e bash -c '…; read -p …'`, so the code stays on
# screen until the reader dismisses it.
exec python3 "$(dirname "$0")/wifi-qr.py" "$@"
