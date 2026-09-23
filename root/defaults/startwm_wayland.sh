#!/bin/bash

# Launch DE
setterm blank 0
setterm powerdown 0
WAYLAND_DISPLAY=wayland-1 Xwayland :1 &
sleep 2
/usr/bin/dbus-launch /usr/bin/mate-session > /dev/null 2>&1
