FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine318

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KDE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"


RUN \
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
    khotkeys \
    kmenuedit \
    plasma-browser-integration \
    plasma-desktop \
    plasma-systemmonitor \
    plasma-workspace-wallpapers \
    systemsettings \
    util-linux-misc && \
 echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** kde tweaks ****" && \
  sed -i \
    's/applications:org.kde.discover.desktop,/applications:org.kde.konsole.desktop,/g' \
    /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
