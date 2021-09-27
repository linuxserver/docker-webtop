#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /startpulse.sh --start &
/usr/bin/mate-session > /dev/null 2>&1
