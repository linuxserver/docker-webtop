#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /startpulse.sh --start &
/usr/bin/startxfce4 > /dev/null 2>&1
