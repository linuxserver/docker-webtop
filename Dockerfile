FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine319

# set version label
ARG BUILD_DATE
ARG VERSION
ARG I3_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    firefox \
    i3status \
    i3wm \
    st \
    util-linux-misc && \
  echo "**** application tweaks ****" && \
  ln -s \
    /usr/bin/st \
    /usr/bin/x-terminal-emulator && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
