FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Ubuntu LXQt" \
    NO_FULL=true \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  add-apt-repository ppa:xtradeb/apps && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
    chromium \
    featherpad \
    gnome-keyring \
    libgtk-3-common \
    libqt6multimedia6 \
    libqt6svg6 \
    libqt6svgwidgets6 \
    libqt6widgets6 \
    libusb-1.0-0 \
    lxqt-core \
    papirus-icon-theme && \
  echo "**** lxqt tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  mv \
    /usr/bin/chromium \
    /usr/bin/chromium-browser && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /config/.launchpadlib \
    /tmp/* \
    /usr/share/applications/lxqt-config-monitor.desktop \
    /usr/share/applications/lxqt-hibernate.desktop \
    /usr/share/applications/lxqt-leave.desktop \
    /usr/share/applications/lxqt-lockscreen.desktop \
    /usr/share/applications/lxqt-logout.desktop \
    /usr/share/applications/lxqt-reboot.desktop \
    /usr/share/applications/lxqt-shutdown.desktop \
    /usr/share/applications/lxqt-suspend.desktop \
    /var/lib/apt/lists/* \
    /var/tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3001
VOLUME /config
