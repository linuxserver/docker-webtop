FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine317

# set version label
ARG BUILD_DATE
ARG VERSION
ARG MATE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"


RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    chromium \
    mate-desktop-environment \
    util-linux-misc && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** mate tweaks ****" && \
  sed -i \
    '/compositing-manager/{n;s/.*/      <default>false<\/default>/}' \
    /usr/share/glib-2.0/schemas/org.mate.marco.gschema.xml && \
    glib-compile-schemas /usr/share/glib-2.0/schemas/ && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
