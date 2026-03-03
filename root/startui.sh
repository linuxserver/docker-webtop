#! /bin/bash

export QT_QPA_PLATFORMTHEME=lxqt 
export XDG_CURRENT_DESKTOP=LXQt
export LXQT_SESSION_CONFIG=session

/usr/bin/pcmanfm-qt --desktop --profile=lxqt &
/usr/bin/lxqt-globalkeysd &
/usr/bin/lxqt-notificationd &
/usr/bin/lxqt-panel &
/usr/bin/lxqt-policykit-agent &
/usr/bin/lxqt-runner
