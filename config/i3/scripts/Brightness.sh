#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# Script for Monitor backlights (if supported), through Platform.sh: brightnessctl (Linux), FreeBSD's backlight,
# xbacklight (screens RandR can dim: OpenBSD, NetBSD, ...)

iDIR="${XDG_CONFIG_HOME:-$HOME/.config}/i3/icons"
step=10  # INCREASE/DECREASE BY THIS VALUE

# Get current brightness as an integer (without %)
P="${XDG_CONFIG_HOME:-$HOME/.config}/i3/scripts/Platform.sh"
get_brightness() {
    "$P" brightness get
}

# Determine the icon based on brightness level
get_icon_path() {
    local brightness=$1
    local level=$(( (brightness + 19) / 20 * 20 ))  # Round up to next 20
    if (( level > 100 )); then
        level=100
    fi
    echo "$iDIR/brightness-${level}.png"
}

# Send notification
send_notification() {
    local brightness=$1
    local icon_path=$2

    notify-send -e \
        -h string:x-canonical-private-synchronous:brightness_notif \
        -h int:value:"$brightness" \
        -u low \
        -i "$icon_path" \
        "Screen" "Brightness: ${brightness}%"
}

# Change brightness and notify
change_brightness() {
    local delta=$1
    local current new icon

    current=$(get_brightness)
    if [ -z "$current" ]; then
        notify-send -e -u low "Screen" "This screen's brightness cannot be changed from here" 2>/dev/null
        return 1
    fi
    new=$((current + delta))

    # Clamp between 5 and 100
    (( new < 5 )) && new=5
    (( new > 100 )) && new=100

    "$P" brightness set "$new"

    icon=$(get_icon_path "$new")
    send_notification "$new" "$icon"
}

# Main
case "$1" in
    "--get")
        get_brightness
        ;;
    "--inc")
        change_brightness "$step"
        ;;
    "--dec")
        change_brightness "-$step"
        ;;
    *)
        get_brightness
        ;;
esac