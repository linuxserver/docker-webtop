#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi > /dev/null 2>&1 && ls -A /dev/dri 2>/dev/null && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

setterm blank 0
setterm powerdown 0

# Start DE
exec dbus-launch --exit-with-session /usr/bin/i3 > /dev/null 2>&1
