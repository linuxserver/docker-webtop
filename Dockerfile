FROM ghcr.io/linuxserver/baseimage-selkies:debianbookworm

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Debian i3"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
    chromium \
    chromium-l10n \
    i3 \
    i3-wm \
    stterm && \
  echo "**** application tweaks ****" && \
  mv \
    /usr/bin/chromium \
    /usr/bin/chromium-real && \
  update-alternatives --set \
    x-terminal-emulator \
    /usr/bin/st && \
  echo "**** i3 tweaks ****" && \
  sed -i \
    '/status_command/d' \
    /etc/i3/config && \
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
