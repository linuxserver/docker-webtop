#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /startpulse.sh &
/usr/bin/openbox-session > /dev/null 2>&1
