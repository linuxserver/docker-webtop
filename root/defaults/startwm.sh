#!/bin/bash

# Disable compositing and screen locking
if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig6 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig6 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi
setterm blank 0
setterm powerdown 0

# Start DE
/usr/bin/startplasma-x11 > /dev/null 2>&1
