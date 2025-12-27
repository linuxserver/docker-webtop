#!/bin/bash

# Disable blanking
setterm blank 0
setterm powerdown 0

# Start DE
WAYLAND_DISPLAY=wayland-1 Xwayland :1 &
sleep 2
exec dbus-launch --exit-with-session /usr/bin/mate-session > /dev/null 2>&1
