#!/usr/bin/with-contenv bash

# Purge default labwc config
rm -Rf $HOME/.config/labwc

# Start DE
WAYLAND_DISPLAY=wayland-1 startxfce4 --wayland > /dev/null 2>&1
