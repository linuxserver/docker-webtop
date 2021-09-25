#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /usr/bin/pulseaudio --start
/usr/bin/startxfce4 > /dev/null 2>&1
