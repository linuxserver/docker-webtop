#!/bin/bash

setterm blank 0
setterm powerdown 0
if [ ! -f "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
cat <<EOT >> "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOT
fi

/usr/bin/xfce4-session > /dev/null 2>&1
