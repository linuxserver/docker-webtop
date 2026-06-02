#!/usr/bin/env bash
set -e

export XCURSOR_THEME=breeze
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
export XKB_DEFAULT_RULES=evdev
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export DESKTOP_SESSION=plasma
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORMTHEME=kde
export PULSE_SERVER="${PULSE_SERVER:-unix:/run/user/$(id -u)/pulse/native}"
unset PULSE_RUNTIME_PATH

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [ -S "${XDG_RUNTIME_DIR}/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
  else
    export WAYLAND_DISPLAY=wayland-0
  fi
fi

if [[ "${LANG:-}" == ja* ]]; then
  export XKB_DEFAULT_LAYOUT=jp
  export GTK_IM_MODULE=fcitx
  export QT_IM_MODULE=fcitx
  export SDL_IM_MODULE=fcitx
  export GLFW_IM_MODULE=fcitx
  export XMODIFIERS="@im=fcitx"
  export INPUT_METHOD=fcitx
else
  export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
fi

cd "${HOME}" || exit 1
LOG_SUFFIX="$(id -u)"

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  eval "$(dbus-launch --sh-syntax)"
fi

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment \
    WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    KDE_FULL_SESSION KDE_SESSION_VERSION QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \
    XDG_RUNTIME_DIR HOME LANG LANGUAGE LC_ALL \
    GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE \
    XMODIFIERS INPUT_METHOD DBUS_SESSION_BUS_ADDRESS \
    PULSE_SERVER \
    2>/dev/null || true
fi

if [ -x /usr/bin/startplasma-wayland ]; then
  /usr/bin/startplasma-wayland >"/tmp/startplasma-wayland-${LOG_SUFFIX}.log" 2>&1 &
  SESSION_PID=$!

  for _ in $(seq 1 120); do
    pgrep -u "$(id -u)" -x kwin_wayland >/dev/null 2>&1 || { sleep .5; continue; }
    pgrep -u "$(id -u)" -x kded6 >/dev/null 2>&1 || { sleep .5; continue; }
    [ -S "${XDG_RUNTIME_DIR}/wayland-0" ] || { sleep .5; continue; }

    # KWin-managed virtual keyboard path for Fcitx5 on Wayland.
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      kwriteconfig6 --file kwinrc --group Wayland --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
      kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true
    fi

    if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      WAYLAND_DISPLAY=wayland-0 DISPLAY="${DISPLAY:-:1}" /usr/bin/plasmashell >"/tmp/plasmashell-${LOG_SUFFIX}.log" 2>&1 &
    fi

    if pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      break
    fi

    sleep .5
  done

  # In some sessions fcitx starts in inactive state. Explicitly activate once
  # so selected IM (mozc / keyboard-jp) actually receives key events.
  if [[ "${LANG:-}" == ja* ]] && command -v gdbus >/dev/null 2>&1; then
    for _ in $(seq 1 40); do
      FCITX_PID="$(pgrep -u "$(id -u)" -x fcitx5 | head -1)"
      if [ -n "${FCITX_PID}" ]; then
        FCITX_DBUS="$(tr '\0' '\n' < "/proc/${FCITX_PID}/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)"
        if [ -n "${FCITX_DBUS}" ]; then
          DBUS_SESSION_BUS_ADDRESS="${FCITX_DBUS}" gdbus call --session \
            --dest org.fcitx.Fcitx5 \
            --object-path /controller \
            --method org.fcitx.Fcitx.Controller1.Activate \
            >/dev/null 2>&1 || true
          break
        fi
      fi
      sleep .25
    done
  fi

  wait "${SESSION_PID}"
  exit $?
fi

echo "ERROR: /usr/bin/startplasma-wayland is not available; KDE Plasma Wayland cannot be started" >&2
exit 1
