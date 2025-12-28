#!/bin/bash

# Launch DE
setterm blank 0
setterm powerdown 0
WAYLAND_DISPLAY=wayland-1 Xwayland :1 &
sleep 2
/usr/bin/mate-session > /dev/null 2>&1
