#!/bin/bash
ulimit -c 0

# Launch DE
setterm blank 0
setterm powerdown 0
WAYLAND_DISPLAY=wayland-1 exec dbus-launch --exit-with-session /usr/bin/sway --unsupported-gpu > /dev/null 2>&1
