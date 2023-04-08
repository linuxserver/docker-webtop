#!/bin/bash

if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig5 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig5 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi
if [ ! -f $HOME/.config/kdeglobals ]; then
  kwriteconfig5 --file $HOME/.config/kdeglobals --group KDE --key LookAndFeelPackage org.fedoraproject.fedora.desktop
fi
setterm blank 0
setterm powerdown 0
/usr/bin/startplasma-x11 > /dev/null 2>&1
