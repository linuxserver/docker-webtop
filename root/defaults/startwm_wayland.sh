#!/bin/bash

# Launch DE
setterm blank 0
setterm powerdown 0
WAYLAND_DISPLAY=wayland-1 /usr/bin/sway > /dev/null 2>&1
