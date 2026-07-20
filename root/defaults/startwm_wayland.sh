#!/bin/bash

setterm blank 0
setterm powerdown 0

# dbus
eval $(dbus-launch --sh-syntax)

# default wayfire config
mkdir -p "$HOME/.config/mate"
if [ ! -f "$HOME/.config/mate/wayfire.ini" ]; then
    cp /defaults/wayfire.ini "$HOME/.config/mate/wayfire.ini"
fi

# start de
export XDG_CURRENT_DESKTOP=MATE
export WAYLAND_DISPLAY=wayland-1
gsettings set org.gnome.desktop.interface gtk-theme 'Menta'
gsettings set org.gnome.desktop.interface icon-theme 'mate'
exec wayfire -c "$HOME/.config/mate/wayfire.ini" > /dev/null 2>&1
