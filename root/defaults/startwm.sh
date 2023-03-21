#!/bin/bash

if [ ! -f /config/.config/kwinrc ]; then
echo '[Compositing]
Enabled=false' > /config/.config/kwinrc
fi
setterm blank 0
setterm powerdown 0
xset s 0 0
/usr/bin/dbus-launch /usr/bin/startplasma-x11 > /dev/null 2>&1
