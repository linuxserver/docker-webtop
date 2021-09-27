#!/bin/bash
PULSE_SCRIPT=/etc/xrdp/pulse/default.pa /startpulse.sh & 
/usr/bin/i3 > /dev/null 2>&1
