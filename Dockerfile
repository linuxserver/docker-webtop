FROM ghcr.io/linuxserver/baseimage-kasmvnc:fedora38

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    chromium \
    desktop-backgrounds-compat \
    dex-autostart \
    greybird-dark-theme \
    greybird-xfwm4-theme \
    gtk-xfce-engine \
    mousepad \
    Thunar \
    xfce4-appfinder \
    xfce4-datetime-plugin \
    xfce4-panel \
    xfce4-places-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-session \
    xfce4-settings \
    xfce4-terminal \
    xfconf \
    xfdesktop \
    xfwm4 \
    xfwm4-themes && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium-browser.desktop && \
  mv /usr/bin/exo-open /usr/bin/exo-open-real && \
  echo "**** xfce tweaks ****" && \
  rm -f \
    /etc/xdg/autostart/xfce-polkit.desktop && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
