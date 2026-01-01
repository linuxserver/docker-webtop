# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-selkies:alpine323

# set version label
ARG BUILD_DATE
ARG VERSION
ARG XFCE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Alpine KDE" \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    breeze \
    chromium \
    discover \
    firefox \
    kde-applications-base \
    plasma-desktop \
    systemsettings && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /etc/xdg/autostart/* \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3001

VOLUME /config
