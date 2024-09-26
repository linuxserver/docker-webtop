FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine320

# set version label
ARG BUILD_DATE
ARG VERSION
ARG OPENBOX_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Alpine Openbox"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    chromium \
    obconf-qt \
    st \
    util-linux-misc && \
  echo "**** application tweaks ****" && \
  ln -s \
    /usr/bin/st \
    /usr/bin/x-terminal-emulator && \
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
