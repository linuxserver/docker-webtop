FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine321

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KDE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Alpine KDE"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    chromium \
    dolphin \
    konsole \
    kwrite \
    breeze \
    breeze-gtk \
    breeze-icons \
    kde-gtk-config \
    kmenuedit \
    plasma-browser-integration \
    plasma-desktop \
    plasma-systemmonitor \
    plasma-workspace-wallpapers \
    plasma-workspace-x11 \
    systemsettings \
    util-linux-misc && \
  echo "**** kde tweaks ****" && \
  sed -i \
    's/applications:org.kde.discover.desktop,/applications:org.kde.konsole.desktop,/g' \
    /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml && \
  sed -i \
    's:/usr/bin/chromium-browser:/usr/bin/chromium:g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
