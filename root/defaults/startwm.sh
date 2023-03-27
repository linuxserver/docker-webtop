#!/bin/bash

setterm blank 0
setterm powerdown 0
if [ -f "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml ]; then
  sed -i \
    '/use_compositing/c <property name="use_compositing" type="bool" value="false"/>' \
    "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
fi
/usr/bin/dbus-launch /usr/bin/startxfce4 --replace > /dev/null 2>&1
