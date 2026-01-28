#!/bin/bash
ulimit -c 0

setterm blank 0
setterm powerdown 0

# Start DE
WAYLAND_DISPLAY=wayland-1 exec dbus-launch --exit-with-session /usr/bin/sway > /dev/null 2>&1
