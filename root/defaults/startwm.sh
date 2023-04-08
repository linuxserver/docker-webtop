#!/bin/bash

setterm blank 0
setterm powerdown 0
gsettings set org.mate.Marco.general compositing-manager false
/usr/bin/mate-session > /dev/null 2>&1
