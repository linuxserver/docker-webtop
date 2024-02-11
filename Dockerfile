FROM ghcr.io/linuxserver/baseimage-kasmvnc:arch

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Arch IceWM"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  pacman -Sy --noconfirm --needed \
    chromium \
    icewm \
    xfce4-terminal && \
  echo "**** application tweaks ****" && \
  mv \
    /usr/bin/chromium \
    /usr/bin/chromium-real && \
  ln -s \
    /usr/sbin/xfce4-terminal \
    /usr/bin/x-terminal-emulator && \
  rm /usr/bin/xterm && \
  ln -s \
    /usr/sbin/xfce4-terminal \
    /usr/bin/xterm && \
  echo "**** theme ****" && \
  rm -Rf /usr/share/icewm/themes/default && \
  curl -s \
    http://ryankuba.com/ice.tar.gz \
    | tar zxf - -C /usr/share/icewm/themes/ && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
