#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /usr/bin/pulseaudio --start
/usr/bin/startplasma-x11 > /dev/null 2>&1
