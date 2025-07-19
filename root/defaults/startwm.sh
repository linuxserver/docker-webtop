#!/bin/bash

# Disable blanking
setterm blank 0
setterm powerdown 0

# Start DE
exec dbus-launch --exit-with-session /usr/bin/i3 > /dev/null 2>&1
