#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Disable compositing
setterm blank 0
setterm powerdown 0
if [ -f "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml ]; then
  sed -i \
    '/use_compositing/c <property name="use_compositing" type="bool" value="false"/>' \
    "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
fi

# Launch DE
/usr/bin/dbus-launch /usr/bin/startxfce4 --replace > /dev/null 2>&1
