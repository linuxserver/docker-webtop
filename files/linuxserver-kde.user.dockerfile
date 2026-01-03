# Base image must be provided via --build-arg BASE_IMAGE=<image>
ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

ARG USER_NAME
ARG USER_UID
ARG USER_GID
# Note: USER_PASSWORD is used only during image build for initial setup.
# It is not stored in the image layers. Change password after first login.
ARG USER_PASSWORD=""
ARG HOST_HOSTNAME="Docker-Host"
ARG USER_LANGUAGE="en"
ARG USER_LANG_ENV="en_US.UTF-8"
ARG USER_LANGUAGE_ENV="en_US:en"

ENV HOME="/home/${USER_NAME}" \
    USER_NAME="${USER_NAME}" \
    HOST_HOSTNAME="${HOST_HOSTNAME}" \
    SHELL="/bin/bash" \
    LANG="${USER_LANG_ENV}" \
    LANGUAGE="${USER_LANGUAGE_ENV}" \
    LC_ALL="${USER_LANG_ENV}"

RUN set -eux; \
  TARGET_USER="${USER_NAME}"; \
  TARGET_UID="${USER_UID}"; \
  TARGET_GID="${USER_GID}"; \
  if [ -z "${TARGET_UID}" ] || [ -z "${TARGET_GID}" ]; then echo "USER_UID/USER_GID must be provided (host UID/GID)"; exit 1; fi; \
  if [ -z "${USER_PASSWORD}" ]; then echo "USER_PASSWORD must be provided"; exit 1; fi; \
  echo "Using user=${TARGET_USER} uid=${TARGET_UID} gid=${TARGET_GID}"; \
  # ensure primary group named ${TARGET_USER} exists with TARGET_GID (allow non-unique gid to satisfy chown <user>:<user>) \
  if getent group "${TARGET_USER}" >/dev/null; then \
    groupmod -g "${TARGET_GID}" "${TARGET_USER}" || true; \
  else \
    groupadd -o -g "${TARGET_GID}" "${TARGET_USER}" 2>/dev/null || true; \
  fi; \
  # remove any user that already has the desired UID to avoid conflicts \
  if getent passwd "${TARGET_UID}" >/dev/null; then \
    OLD_USER=$(getent passwd "${TARGET_UID}" | cut -d: -f1); \
    if [ "${OLD_USER}" != "${TARGET_USER}" ]; then \
      echo "UID ${TARGET_UID} in use by ${OLD_USER}, removing it"; \
      userdel -r "${OLD_USER}" || true; \
    fi; \
  fi; \
  # ensure common supplemental groups exist (similar to Ubuntu adduser) plus docker/sudo \
  for g in adm cdrom dip plugdev lpadmin lxd sudo docker users audio video render; do \
    getent group "$g" >/dev/null || groupadd "$g"; \
  done; \
  # set hostname to host-derived value (baked into image) \
  echo "${HOST_HOSTNAME}" > /etc/hostname; \
  # create or update main user matching host uid/gid (home=/home/<user>) \
  if ! getent passwd "${TARGET_USER}" >/dev/null; then \
    useradd -m -d "/home/${TARGET_USER}" -u "${TARGET_UID}" -g "${TARGET_USER}" -s /bin/bash "${TARGET_USER}"; \
  else \
    usermod -u "${TARGET_UID}" -g "${TARGET_USER}" -d "/home/${TARGET_USER}" "${TARGET_USER}"; \
    install -d -m 755 "/home/${TARGET_USER}"; \
  fi; \
  usermod -aG adm,cdrom,dip,plugdev,lpadmin,lxd,sudo,docker,users,audio,video,render "${TARGET_USER}"; \
  echo "${TARGET_USER}:${USER_PASSWORD}" | chpasswd; \
  # store auth secret/hash for web login \
  SECRET_SALT=$(openssl rand -hex 16); \
  env TARGET_USER="${TARGET_USER}" TARGET_PW="${USER_PASSWORD}" SECRET_SALT="${SECRET_SALT}" \
    python3 -c "import json,hashlib,os;user=os.environ['TARGET_USER'];pw=os.environ['TARGET_PW'];salt=os.environ['SECRET_SALT'];pw_hash=hashlib.sha256((pw+salt).encode()).hexdigest();secret=hashlib.sha256((user+pw+salt).encode()).hexdigest();data={'user':user,'salt':salt,'pw_hash':pw_hash,'secret':secret};open('/etc/web-auth.json','w').write(json.dumps(data));os.chmod('/etc/web-auth.json',0o600)" ; \
  # ensure skeleton and Ubuntu-like bashrc for user (HOME=/home/<user>) and root \
  install -d -m 755 "/home/${TARGET_USER}"; \
  chown -R "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}"; \
  # create common XDG-style folders in the user's home \
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do \
    install -d -m 755 "/home/${TARGET_USER}/${d}"; \
    chown "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}/${d}"; \
  done; \
  DEFAULT_BASHRC="/usr/local/share/default_bashrc"; \
  printf '%s\n' \
    "# DEFAULT_BASHRC" \
    "# ~/.bashrc: executed by bash(1) for non-login shells." \
    "# If not running interactively, don't do anything" \
    "case \$- in" \
    "    *i*) ;;" \
    "      *) return;;" \
    "esac" \
    "HISTCONTROL=ignoreboth" \
    "shopt -s histappend" \
    "HISTSIZE=1000" \
    "HISTFILESIZE=2000" \
    "shopt -s checkwinsize" \
    "[ -x /usr/bin/lesspipe ] && eval \"\$(SHELL=/bin/sh lesspipe)\"" \
    "if [ -z \"\${debian_chroot:-}\" ] && [ -r /etc/debian_chroot ]; then" \
    "    debian_chroot=\$(cat /etc/debian_chroot)" \
    "fi" \
    "case \"\$TERM\" in" \
    "    xterm-color|*-256color) color_prompt=yes;;" \
    "esac" \
    "if [ -n \"\$force_color_prompt\" ]; then" \
    "    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then" \
    "        color_prompt=yes" \
    "    else" \
    "        color_prompt=" \
    "    fi" \
    "fi" \
    "if [ \"\$color_prompt\" = yes ]; then" \
    "    PS1=\"\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;32m\\]\\u@${HOST_HOSTNAME}\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ \" " \
    "else" \
    "    PS1=\"\${debian_chroot:+(\$debian_chroot)}\\u@${HOST_HOSTNAME}:\\w\\$ \" " \
    "fi" \
    "unset color_prompt force_color_prompt" \
    "case \"\$TERM\" in" \
    "xterm*|rxvt*)" \
    "    PS1=\"\\[\\e]0;\${debian_chroot:+(\$debian_chroot)}\\u@${HOST_HOSTNAME}: \\w\\a\\]\$PS1\"" \
    "    ;;" \
    "*)" \
    "    ;;" \
    "esac" \
    "if [ -x /usr/bin/dircolors ]; then" \
    "    test -r ~/.dircolors && eval \"\$(dircolors -b ~/.dircolors)\" || eval \"\$(dircolors -b)\"" \
    "    alias ls='ls --color=auto'" \
    "    alias grep='grep --color=auto'" \
    "    alias fgrep='fgrep --color=auto'" \
    "    alias egrep='egrep --color=auto'" \
    "fi" \
    "alias ll='ls -alF'" \
    "alias la='ls -A'" \
    "alias l='ls -CF'" \
    "if [ -f ~/.bash_aliases ]; then" \
    "    . ~/.bash_aliases" \
    "fi" \
    "if ! shopt -oq posix; then" \
    "  if [ -f /usr/share/bash-completion/bash_completion ]; then" \
    "    . /usr/share/bash-completion/bash_completion" \
    "  elif [ -f /etc/bash_completion ]; then" \
    "    . /etc/bash_completion" \
    "  fi" \
    "fi" \
    > "${DEFAULT_BASHRC}" \
  && cp "${DEFAULT_BASHRC}" "/home/${TARGET_USER}/.bashrc" \
  && cp "${DEFAULT_BASHRC}" /root/.bashrc \
  && chown "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}/.bashrc" \
  && rm -f /etc/profile.d/00-ps1.sh /etc/profile.d/01-bashcomp.sh; \
  # reset sudoers to require password \
  sed -i 's/^%sudo\tALL=(ALL:ALL) NOPASSWD: ALL/%sudo\tALL=(ALL:ALL) ALL/' /etc/sudoers; \
  if ! grep -q "^%sudo\s\+ALL=(ALL:ALL)\s\+ALL" /etc/sudoers; then echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers; fi; \
  # disable PackageKit/UDisks2 autostart and D-Bus activation (prevents permission-denied spam) \
  rm -f \
    /etc/xdg/autostart/packagekitd.desktop \
    /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service \
    /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service; \
  install -d -m 755 /etc/dbus-1/system.d; \
  printf '%s\n' \
    '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"' \
    '"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">' \
    '<busconfig>' \
    '  <policy context="default">' \
    '    <deny send_destination="org.freedesktop.PackageKit"/>' \
    '    <deny send_destination="org.freedesktop.UDisks2"/>' \
    '  </policy>' \
    '</busconfig>' \
    > /etc/dbus-1/system.d/disable-packagekit.conf; \
  mkdir -p /defaults /app /lsiopy && \
  chown -R "${TARGET_UID}:${TARGET_GID}" /defaults /app /lsiopy

# optional Japanese locale and input (toggle via USER_LANGUAGE=ja)
RUN set -eux; \
  LANG_SEL="$(echo "${USER_LANGUAGE}" | tr '[:upper:]' '[:lower:]')" ; \
  if [ "${LANG_SEL}" = "ja" ] || [ "${LANG_SEL}" = "ja_jp" ] || [ "${LANG_SEL}" = "ja-jp" ]; then \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      language-pack-ja-base language-pack-ja im-config \
      fonts-noto-cjk fonts-noto-color-emoji \
      fcitx fcitx-bin fcitx-data fcitx-table-all \
      fcitx-mozc fcitx-config-gtk \
      fcitx-frontend-gtk2 fcitx-frontend-gtk3 fcitx-frontend-qt5 \
      fcitx-module-dbus fcitx-module-kimpanel fcitx-module-x11 fcitx-module-lua fcitx-ui-classic \
      kde-config-fcitx \
      mozc-utils-gui && \
    locale-gen ja_JP.UTF-8 && \
    update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP:ja LC_ALL=ja_JP.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen || true; \
    echo 'LANG=ja_JP.UTF-8' > /etc/default/locale; \
    echo 'LANGUAGE=ja_JP:ja' >> /etc/default/locale; \
    echo 'LC_ALL=ja_JP.UTF-8' >> /etc/default/locale; \
    printf '%s\n' \
      'export GTK_IM_MODULE=fcitx' \
      'export QT_IM_MODULE=fcitx' \
      'export XMODIFIERS=@im=fcitx' \
      'export INPUT_METHOD=fcitx' \
      'export SDL_IM_MODULE=fcitx' \
      'export GLFW_IM_MODULE=fcitx' \
      'export FCITX_DEFAULT_INPUT_METHOD=mozc' \
      > /etc/profile.d/fcitx.sh; \
    chmod 644 /etc/profile.d/fcitx.sh; \
    printf '%s\n' \
      'XKBMODEL="jp106"' \
      'XKBLAYOUT="jp"' \
      'XKBVARIANT=""' \
      'XKBOPTIONS=""' \
      'BACKSPACE="guess"' \
      > /etc/default/keyboard; \
    install -d -m 755 /etc/X11/xorg.conf.d; \
    printf '%s\n' \
      'Section "InputClass"' \
      '    Identifier "system-keyboard"' \
      '    MatchIsKeyboard "on"' \
      '    Option "XkbLayout" "jp"' \
      '    Option "XkbModel" "jp106"' \
      '    Option "XkbVariant" ""' \
      '    Option "XkbOptions" ""' \
      'EndSection' \
      > /etc/X11/xorg.conf.d/00-keyboard.conf; \
    im-config -n fcitx; \
    install -d -m 755 /etc/xdg/autostart "/home/${USER_NAME}/.config/autostart"; \
    printf '%s\n' \
      '[Desktop Entry]' \
      'Type=Application' \
      'Exec=fcitx -d' \
      'Hidden=false' \
      'X-GNOME-Autostart-enabled=true' \
      'Name=fcitx' \
      'Comment=Start Fcitx input method daemon' \
      > /etc/xdg/autostart/fcitx-autostart.desktop; \
    cp /etc/xdg/autostart/fcitx-autostart.desktop "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
    printf '%s\n' \
      'export GTK_IM_MODULE=fcitx' \
      'export QT_IM_MODULE=fcitx' \
      'export XMODIFIERS=@im=fcitx' \
      'export INPUT_METHOD=fcitx' \
      'export SDL_IM_MODULE=fcitx' \
      'export GLFW_IM_MODULE=fcitx' \
      'export FCITX_DEFAULT_INPUT_METHOD=mozc' \
      'fcitx -d >/tmp/fcitx.log 2>&1' \
      > "/home/${USER_NAME}/.xprofile"; \
    printf '%s\n' \
      '[Layout]' \
      'DisplayNames=' \
      'LayoutList=jp' \
      'Model=jp106' \
      'Options=' \
      'ResetOldOptions=true' \
      'Use=true' \
      > "/home/${USER_NAME}/.config/kxkbrc"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.xprofile" "/home/${USER_NAME}/.config/kxkbrc"; \
  fi

# create XDG user dirs and desktop shortcuts (Home/Trash)
RUN set -eux; \
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do \
    install -d -m 755 "/home/${USER_NAME}/${d}"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/${d}"; \
  done; \
  install -d -m 755 "/home/${USER_NAME}/.config"; \
  printf '%s\n' \
    'XDG_DESKTOP_DIR="$HOME/Desktop"' \
    'XDG_DOWNLOAD_DIR="$HOME/Downloads"' \
    'XDG_TEMPLATES_DIR="$HOME/Templates"' \
    'XDG_PUBLICSHARE_DIR="$HOME/Public"' \
    'XDG_DOCUMENTS_DIR="$HOME/Documents"' \
    'XDG_MUSIC_DIR="$HOME/Music"' \
    'XDG_PICTURES_DIR="$HOME/Pictures"' \
    'XDG_VIDEOS_DIR="$HOME/Videos"' \
    > "/home/${USER_NAME}/.config/user-dirs.dirs"; \
  printf '%s\n' \
    '[Desktop Entry]' \
    'Encoding=UTF-8' \
    'Name=Home' \
    'GenericName=Personal Files' \
    'URL[$e]=$HOME' \
    'Icon=user-home' \
    'Type=Link' \
    > "/home/${USER_NAME}/Desktop/home.desktop"; \
  printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Trash' \
    'Comment=Contains removed files' \
    'Icon=user-trash-full' \
    'EmptyIcon=user-trash' \
    'URL=trash:/' \
    'Type=Link' \
    > "/home/${USER_NAME}/Desktop/trash.desktop"; \
  chown "${USER_UID}:${USER_GID}" /home/${USER_NAME}/Desktop/home.desktop /home/${USER_NAME}/Desktop/trash.desktop

# browser wrappers (Chromium on arm64, Chrome on amd64) to enforce flags even after package updates
RUN set -eux; \
  ARCH="$(dpkg --print-architecture)"; \
  if [ "${ARCH}" = "arm64" ]; then \
    if [ -x /usr/bin/chromium ]; then \
      echo '#!/bin/bash' > /usr/local/bin/chromium-wrapped && \
      echo 'CHROME_BIN=\"/usr/bin/chromium\"' >> /usr/local/bin/chromium-wrapped && \
      echo 'exec \"${CHROME_BIN}\" --password-store=basic --in-process-gpu --no-sandbox ${CHROME_EXTRA_FLAGS} \"$@\"' >> /usr/local/bin/chromium-wrapped && \
      chmod 755 /usr/local/bin/chromium-wrapped; \
      if [ -f /usr/share/applications/chromium.desktop ]; then \
        mkdir -p /home/${USER_NAME}/.local/share/applications && \
        cp /usr/share/applications/chromium.desktop /home/${USER_NAME}/.local/share/applications/chromium.desktop && \
        sed -i -e 's#Exec=/usr/bin/chromium#Exec=/usr/local/bin/chromium-wrapped#g' /home/${USER_NAME}/.local/share/applications/chromium.desktop && \
        chown ${USER_UID}:${USER_GID} /home/${USER_NAME}/.local/share/applications/chromium.desktop; \
      fi; \
    fi; \
  else \
    if [ -x /usr/bin/google-chrome-stable ]; then \
      echo '#!/bin/bash' > /usr/local/bin/google-chrome-wrapped && \
      echo 'CHROME_BIN="/usr/bin/google-chrome-stable"' >> /usr/local/bin/google-chrome-wrapped && \
      echo 'exec "${CHROME_BIN}" --password-store=basic --in-process-gpu --no-sandbox ${CHROME_EXTRA_FLAGS} "$@"' >> /usr/local/bin/google-chrome-wrapped && \
      chmod 755 /usr/local/bin/google-chrome-wrapped; \
      for chrome_bin in google-chrome google-chrome-beta google-chrome-unstable; do \
        if [ -x \"/usr/bin/${chrome_bin}\" ]; then \
          echo '#!/bin/bash' > \"/usr/local/bin/${chrome_bin}-wrapped\" && \
          echo 'exec /usr/local/bin/google-chrome-wrapped \"$@\"' >> \"/usr/local/bin/${chrome_bin}-wrapped\" && \
          chmod 755 \"/usr/local/bin/${chrome_bin}-wrapped\"; \
        fi; \
      done; \
      for desktop in /usr/share/applications/google-chrome*.desktop; do \
        [ -f "$desktop" ] || continue; \
        sed -i -E 's#Exec=/usr/bin/google-chrome-stable([^\\n]*)#Exec=/usr/local/bin/google-chrome-wrapped#g' "$desktop"; \
      done; \
      mkdir -p /home/${USER_NAME}/.local/share/applications; \
      for desktop in /usr/share/applications/google-chrome*.desktop; do \
        [ -f "$desktop" ] || continue; \
        base=$(basename "$desktop"); \
        cp "$desktop" "/home/${USER_NAME}/.local/share/applications/$base"; \
        sed -i -E 's#Exec=/usr/bin/google-chrome-stable([^\\n]*)#Exec=/usr/local/bin/google-chrome-wrapped#g' "/home/${USER_NAME}/.local/share/applications/$base"; \
        chown ${USER_UID}:${USER_GID} "/home/${USER_NAME}/.local/share/applications/$base"; \
      done; \
    fi; \
  fi

# Keep default USER=root so s6 init can modify system paths.
