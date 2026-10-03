pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick

// PolicyKit authentication agent. The shell registers exactly one
// PolkitAgent listener on the docs' default path (/org/quickshell/Polkit),
// so pkexec / GNOME-style privilege prompts land here. Nothing else on
// this machine provides an agent (no polkit-gnome, lxpolkit or
// hyprpolkitagent is installed and there is no autostart for one), so
// registering takes effect immediately — polkitd falls back to the
// auth agent bus name and our dialog is what shows.
//
// This file owns STATE + ACTIONS only; Bar.qml's "polkit" pill mode
// draws it (PolkitDialog.qml is deprecated). The
// flow handling follows the two references this was built from:
//   - omarchy backup shell PolkitAgent.qml: exclusive-focus overlay,
//     shake on wrong password, Enter submits / Escape cancels, short
//     close delay after success or cancel.
//   - nothing_os Polkit.qml / PolkitDialog.qml: identity chips when the
//     flow offers several accounts, supplementary/error notes, explicit
//     Cancel button (an auth request is never dismissed by clicking
//     away).
Singleton {
    id: root

    readonly property PolkitAgent agent: agentInst

    // live flow or null — every display string the dialog needs hangs
    // off this (message, actionId, inputPrompt, supplementaryMessage,
    // identities, responseVisible, failed, …)
    readonly property var flow: agent.flow

    // held true for a beat after the request completes so the dialog can
    // animate out instead of vanishing the instant polkitd answers
    property bool closing: false
    readonly property bool open: agent.isActive || closing

    // in-flight response bookkeeping
    property bool submitted: false
    property bool errorFlash: false   // "wrong password" tint window
    property int failures: 0          // increments per failed attempt —
                                      // the dialog's shake listens to this

    // the screen that must show the dialog, captured when the request
    // starts (same ownerScreen pattern as ControlCenter: the focused
    // monitor at open time, never every screen at once)
    property string ownerScreen: ""

    onFlowChanged: {
        // a brand new flow object = fresh conversation
        submitted = false
        errorFlash = false
    }

    Connections {
        target: agentInst
        function onIsActiveChanged() {
            if (agentInst.isActive) {
                root.closing = false
                closeTimer.stop()
                root.submitted = false
                root.errorFlash = false
                root.failures = 0
                const fm = Hyprland.focusedMonitor
                root.ownerScreen = fm ? fm.name
                    : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
            } else if (!root.closing) {
                root.beginClose()
            }
        }
    }

    function beginClose() {
        closing = true
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: root.closing = false
    }

    function submit(value) {
        if (!flow || !flow.isResponseRequired) return
        submitted = true
        errorFlash = false
        flow.submit(value)
    }

    function cancel() {
        submitted = false
        beginClose()
        if (flow) flow.cancelAuthenticationRequest()
    }

    function pickIdentity(identity) {
        // writing selectedIdentity aborts the current conversation and
        // restarts with the picked user/group (docs' contract)
        if (flow) flow.selectedIdentity = identity
    }

    function triggerFailure() {
        submitted = false
        errorFlash = true
        failures++
        failTimer.restart()
    }

    Timer {
        id: failTimer
        interval: 1200
        onTriggered: root.errorFlash = false
    }

    Connections {
        target: root.flow

        // PAM finished one round: either a new prompt is pending (wrong
        // password → flash + shake) or the request is over (close path
        // is driven by isActive going false).
        function onFailedChanged() {
            if (root.flow && root.flow.failed) root.triggerFailure()
        }
        function onIsResponseRequiredChanged() {
            if (root.flow && !root.flow.isResponseRequired) root.submitted = false
        }
    }

    PolkitAgent {
        id: agentInst
        // docs default path — nothing else on the system claims an
        // agent name, so this is the one polkitd talks to
        onIsRegisteredChanged: {
            if (isRegistered)
                console.log("qs polkit agent registered at /org/quickshell/Polkit")
            else
                console.warn("qs polkit agent NOT registered — another agent may be running")
        }
    }
}
