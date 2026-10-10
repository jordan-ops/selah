#!/bin/bash
# Persistent BlueZ pairing agent + pairable watchdog.
#
# Why this exists: quickshell's Bluetooth module only talks to
# org.bluez.Adapter1 / Device1 / Battery1 — it never calls
# AgentManager1.RegisterAgent — and nothing else here (no blueman, no
# gnome-bluetooth) registers one either. BlueZ needs a registered agent
# to authorise the PIN/passkey exchange, so every pairing attempt failed
# even with the adapter powered and discoverable. That is also why
# `bluetoothctl devices Paired` came back empty: nothing had ever paired
# on this machine.
#
# `agent NoInputNoOutput` pairs without an on-screen confirmation prompt,
# because there is nothing here to show one. The trade-off is that a
# nearby device can pair without you confirming it — which is why the
# adapter should only be made discoverable while you are actually
# pairing (180s timeout, not permanently visible).
#
# bluetoothctl is kept alive on a pipe whose write end is held open by
# `sleep infinity`, so it never reaches EOF and exits; if it does die,
# we exit too and systemd restarts us (Restart=always).
#
# The second half re-asserts Pairable every 15s as a safety net. The
# "who keeps resetting Pairable?" mystery turned out to have a clean
# answer, visible in the journal at the moment we registered:
#
#     Agent unregistered -> [CHG] Controller Pairable: no
#     Agent registered   -> [CHG] Controller Pairable: yes
#
# bluetoothd derives Pairable from whether an agent is registered, so
# every ad-hoc `bluetoothctl` session I ran to diagnose this dropped
# the agent on exit and silently turned pairing off behind our back.
# With this unit holding the agent open, Pairable stays on; the loop
# only matters if bluetoothd ever restarts without us noticing.

set -u

ADAPTER=/org/bluez/hci0
LOGTAG=bt-agent

log() { echo "$(date -Is) [$LOGTAG] $*"; }

# bluetoothctl auto-registers an agent on startup with an unknown
# capability, so `agent NoInputNoOutput` alone would be rejected with
# "Agent is already registered" and we would be left with whatever it
# picked (DisplayYesNo would then prompt on a stdin nobody reads, and
# pairing would hang). Unregister first, then register what we want.
#
# The sleeps are load-bearing: without them the three lines are queued
# before bluetoothctl's own auto-registration has finished, `agent off`
# unregisters nothing, and the re-register fails with "already
# registered". With a 1s gap between each, the sequence is:
#   Agent unregistered -> Agent registered -> Default agent request
#   successful
{
    echo "agent off"; sleep 1
    echo "agent NoInputNoOutput"; sleep 1
    echo "default-agent"
    exec sleep infinity
} | bluetoothctl 2>&1 | sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\r//g' &
# $! is the last element of the pipeline: sed. If bluetoothctl dies its
# stdout closes, sed gets EOF and exits, our kill -0 check fires and we
# exit so systemd restarts us with a fresh agent.
ctl_pid=$!
bt_pid=$ctl_pid

log "agent requested (pipeline pid $bt_pid)"

while :; do
    # bluetoothctl dying means we lost the agent — bail so systemd restarts
    if ! kill -0 "$bt_pid" 2>/dev/null; then
        log "bluetoothctl exited — losing agent, restarting"
        exit 1
    fi

    state=$(busctl get-property org.bluez "$ADAPTER" org.bluez.Adapter1 Pairable 2>/dev/null | tr -d ' \n')
    if [ "$state" = "bfalse" ]; then
        log "Pairable was reset to false — re-asserting"
        busctl set-property org.bluez "$ADAPTER" org.bluez.Adapter1 Pairable b true 2>/dev/null || true
    fi

    sleep 15
done
