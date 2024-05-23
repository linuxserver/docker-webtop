#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Launch DE
setterm blank 0
setterm powerdown 0
/usr/bin/dbus-launch /usr/bin/mate-session > /dev/null 2>&1
