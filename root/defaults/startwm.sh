#!/bin/bash

setterm blank 0
setterm powerdown 0
/usr/bin/dbus-launch /usr/bin/mate-session > /dev/null 2>&1
