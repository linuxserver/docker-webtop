#!/bin/sh
sleep 1

export PATH="$PATH:/usr/local/libexec:/usr/libexec"

# propagate session env to dbus
if ! grep -q "dbus-update-activation-environment" "$HOME/.config/mate/wayfire.ini" 2>/dev/null; then
    dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XAUTHORITY
fi

# respawn a program while wayfire is running
restart_while_running() {
    while true; do
        "$@"
        pgrep "wayfire" > /dev/null || break
    done
}

restart_while_running mate-panel &
restart_while_running mate-notification-daemon &
restart_while_running caja -n &

nm-applet --indicator &
