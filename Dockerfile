FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine318

# set version label
ARG BUILD_DATE
ARG VERSION
ARG ICEWM_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
  echo "**** install packages ****" && \
  apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    icewm && \
  apk add --no-cache \
    chromium \
    st \
    util-linux-misc && \
  echo "**** application tweaks ****" && \
  mv \
    /usr/bin/chromium-browser \
    /usr/bin/chromium-real && \
  ln -s \
    /usr/bin/st \
    /usr/bin/x-terminal-emulator && \
  rm /usr/bin/xterm && \
  ln -s \
    /usr/bin/st \
    /usr/bin/xterm && \
  echo "**** theme ****" && \
  rm -Rf /usr/share/icewm/themes/default && \
  curl -s \
    http://ryankuba.com/ice.tar.gz \
    | tar zxf - -C /usr/share/icewm/themes/ && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
