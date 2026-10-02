FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Debian XFCE"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
    7zip \
    atril \
    chromium \
    chromium-l10n \
    elementary-xfce-icon-theme \
    greybird-gtk-theme \
    gvfs \
    libxfce4ui-utils \
    mousepad \
    pavucontrol \
    ristretto \
    thunar \
    thunar-archive-plugin \
    tumbler \
    unzip \
    xarchiver \
    xdg-user-dirs \
    xfce4-appfinder \
    xfce4-notifyd \
    xfce4-panel \
    xfce4-screenshooter \
    xfce4-session \
    xfce4-settings \
    xfce4-taskmanager \
    xfce4-terminal \
    xfconf \
    xfdesktop4 \
    xfwm4 \
    zip && \
  echo "**** xfce tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  mv \
    /usr/bin/exo-open \
    /usr/bin/exo-open-real && \
  mv \
    /usr/bin/thunar \
    /usr/bin/thunar-real && \
  rm -f \
    /etc/xdg/autostart/xscreensaver.desktop \
    /usr/share/dbus-1/services/org.knopwob.dunst.service && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
