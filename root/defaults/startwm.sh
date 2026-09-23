#!/bin/bash

# Disable compositing
setterm blank 0
setterm powerdown 0
gsettings set org.mate.Marco.general compositing-manager false

# Start DE
exec dbus-launch --exit-with-session /usr/bin/mate-session > /dev/null 2>&1
