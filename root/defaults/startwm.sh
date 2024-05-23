#!/bin/bash

# Disable blanking
setterm blank 0
setterm powerdown 0

# Start DE
/usr/bin/dbus-launch /usr/bin/mate-session > /dev/null 2>&1
