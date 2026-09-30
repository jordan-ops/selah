#!/bin/bash

# selah-install-app — install Arch packages by display name, with the sudo
# password prompt in a real terminal.
#
#   install-app.sh <display-name> <packages>    non-interactive
#   install-app.sh                              prompts for both
#
# Port of omarchy/bin/omarchy-install-app. omarchy wraps the install in
# `omarchy-launch-floating-terminal-with-presentation`; here that becomes
# `foot -e`, skipped entirely when you already have a TTY — running this
# from your own shell should not spawn a second terminal just to prompt you.
#
# Sudo is invoked BY THIS SCRIPT, in a terminal. It needs a TTY for the
# password, which is the entire reason this file opens one.

set -e

name="${1-}"
packages="${2-}"

usage() {
    echo "Usage: install-app.sh <display-name> <packages>" >&2
    echo "       install-app.sh                      (prompts)" >&2
    exit 1
}

# Package names reach a generated shell line. Rather than escape them for
# every possible metacharacter, reject anything that is not a legal pacman
# name — a name outside this set would not have installed anyway.
validate_packages() {
    local p
    for p in $1; do
        if [[ ! $p =~ ^[a-zA-Z0-9@._+-]+$ ]]; then
            echo "Not a valid package name: $p" >&2
            exit 1
        fi
    done
}

# Emit the shell line the terminal runs. NO `set -e` in here on purpose:
# when this runs under `foot -e`, an abort would close the window before
# the user could read the error, so every step reports and carries on.
build_script() {
    local pkgs=$1 p verify=""
    for p in $pkgs; do
        verify+="if ! pacman -Q '$p' &>/dev/null; then printf '  \033[31m%s did not install\033[0m\n' '$p'; fi; "
    done
    printf '%s' \
        "printf '\033[1mInstalling %s\033[0m\n' '$name'; echo; \
if sudo pacman -S --noconfirm --needed $pkgs; then echo; $verify \
  printf '\033[32mDone.\033[0m\n'; else \
  printf '\n\033[31mInstall failed.\033[0m\n'; fi"
}

# --- no TTY: started by the settings app ----------------------------
if [ ! -t 0 ]; then
    if [ -z "$name" ] || [ -z "$packages" ]; then
        # Nothing to go on and nowhere to prompt: open an interactive
        # instance of this same script.
        exec foot -e bash -c "$(printf '%q' "$0"); echo; read -p 'Press Enter to close' "
    fi
    validate_packages "$packages"
    exec foot -e bash -c "$(build_script "$packages"); echo; read -p 'Press Enter to close' "
fi

# --- we have a terminal --------------------------------------------
if [ -z "$name" ]; then
    printf '\n\033[32mInstall an Arch package\033[0m\n\n'
    while :; do
        read -r -p "Display name> " name || exit 1
        [ -n "$name" ] && break
        printf '  a label for the install, e.g. "LM Studio"\n' >&2
    done
    while :; do
        read -r -p "Package(s)> " packages || exit 1
        [ -n "$packages" ] && break
        printf '  one or more pacman names, e.g. "jq ripgrep"\n' >&2
    done
fi

# The display name is echoed into the generated line above, so keep it to
# characters that cannot close the single quotes it lands in.
name=${name//[\'\\]/}
validate_packages "$packages"

printf 'Installing \033[1m%s\033[0m → %s\n\n' "$name" "$packages"
eval "$(build_script "$packages")"
