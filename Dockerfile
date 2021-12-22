FROM lsiobase/rdesktop-web:alpine

# set version label
ARG BUILD_DATE
ARG VERSION
ARG OPENBOX_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"


RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    firefox-esr && \
  apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    obconf-qt && \
  echo "**** openbox tweaks ****" && \
  ln -s /usr/bin/obconf-qt /usr/bin/obconf && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
