ARG BASE_IMAGE=webtop-kde:base-latest
FROM ${BASE_IMAGE}

ARG USER_NAME
ARG USER_UID
ARG USER_GID
ARG USER_PASSWORD=""
ARG HOST_HOSTNAME="Docker-Host"
ARG USER_LANGUAGE="en"

ENV HOME="/home/${USER_NAME}" \
    USER_NAME="${USER_NAME}" \
    HOST_HOSTNAME="${HOST_HOSTNAME}" \
    SHELL="/bin/bash"

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
  && rm -f /etc/profile.d/00-ps1.sh /etc/profile.d/01-bashcomp.sh || true; \
  # reset sudoers to require password \
  sed -i 's/^%sudo\tALL=(ALL:ALL) NOPASSWD: ALL/%sudo\tALL=(ALL:ALL) ALL/' /etc/sudoers || true; \
  if ! grep -q "^%sudo\s\+ALL=(ALL:ALL)\s\+ALL" /etc/sudoers; then echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers; fi; \
  # disable PackageKit (causes DBus permission errors in minimal container) \
  apt-get purge -y packagekit || true; \
  rm -f /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service /etc/xdg/autostart/packagekitd.desktop || true; \
  mkdir -p /defaults /app /lsiopy && \
  chown -R "${TARGET_UID}:${TARGET_GID}" /defaults /app /lsiopy

# optional Japanese locale and input (toggle via USER_LANGUAGE=ja)
RUN set -eux; \
  if [ "${USER_LANGUAGE}" = "ja" ]; then \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      language-pack-ja-base language-pack-ja \
      fonts-noto-cjk fonts-noto-color-emoji \
      fcitx fcitx-mozc fcitx-frontend-gtk3 fcitx-frontend-qt5 fcitx-module-dbus fcitx-ui-classic \
      mozc-utils-gui && \
    locale-gen ja_JP.UTF-8 && \
    update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP:ja LC_ALL=ja_JP.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen || true; \
    echo 'LANG=ja_JP.UTF-8' > /etc/default/locale; \
    echo 'LANGUAGE=ja_JP:ja' >> /etc/default/locale; \
    echo 'LC_ALL=ja_JP.UTF-8' >> /etc/default/locale; \
  fi

# create XDG user dirs and desktop shortcuts (Home/Trash)
RUN set -eux; \
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do \
    install -d -m 755 "/home/${USER_NAME}/${d}"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/${d}"; \
  done; \
  install -d -m 755 "/home/${USER_NAME}/.config"; \
  cat > "/home/${USER_NAME}/.config/user-dirs.dirs" <<'EOF'

# Create XDG user directories
RUN mkdir -p /home/${USER_NAME}/.config && \
    mkdir -p /home/${USER_NAME}/Desktop && \
    mkdir -p /home/${USER_NAME}/Downloads && \
    mkdir -p /home/${USER_NAME}/Templates && \
    mkdir -p /home/${USER_NAME}/Public && \
    mkdir -p /home/${USER_NAME}/Documents && \
    mkdir -p /home/${USER_NAME}/Music && \
    mkdir -p /home/${USER_NAME}/Pictures && \
    mkdir -p /home/${USER_NAME}/Videos

# Configure XDG user directories
RUN echo 'XDG_DESKTOP_DIR="$HOME/Desktop"' > /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_DOWNLOAD_DIR="$HOME/Downloads"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_TEMPLATES_DIR="$HOME/Templates"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_PUBLICSHARE_DIR="$HOME/Public"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_DOCUMENTS_DIR="$HOME/Documents"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_MUSIC_DIR="$HOME/Music"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_PICTURES_DIR="$HOME/Pictures"' >> /home/${USER_NAME}/.config/user-dirs.dirs && \
    echo 'XDG_VIDEOS_DIR="$HOME/Videos"' >> /home/${USER_NAME}/.config/user-dirs.dirs

# Create Desktop shortcuts
RUN echo '[Desktop Entry]' > /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'Encoding=UTF-8' >> /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'Name=Home' >> /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'GenericName=Personal Files' >> /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'URL[$e]=$HOME' >> /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'Icon=user-home' >> /home/${USER_NAME}/Desktop/home.desktop && \
    echo 'Type=Link' >> /home/${USER_NAME}/Desktop/home.desktop

RUN echo '[Desktop Entry]' > /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'Name=Trash' >> /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'Comment=Contains removed files' >> /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'Icon=user-trash-full' >> /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'EmptyIcon=user-trash' >> /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'URL=trash:/' >> /home/${USER_NAME}/Desktop/trash.desktop && \
    echo 'Type=Link' >> /home/${USER_NAME}/Desktop/trash.desktop

# Set ownership of all user files
RUN chown -R ${USER_NAME} /home/${USER_NAME}

# Keep default USER=root so s6 init can modify system paths.
