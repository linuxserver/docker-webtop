FROM ghcr.io/linuxserver/baseimage-kasmvnc:alpine319

# set version label
ARG BUILD_DATE
ARG VERSION
ARG MATE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Alpine MATE"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    firefox \
    mate-desktop-environment \
    util-linux-misc && \
  echo "**** mate tweaks ****" && \
  sed -i \
    '/compositing-manager/{n;s/.*/      <default>false<\/default>/}' \
    /usr/share/glib-2.0/schemas/org.mate.marco.gschema.xml && \
    glib-compile-schemas /usr/share/glib-2.0/schemas/ && \
  rm -f \
    /etc/xdg/autostart/mate-power-manager.desktop \
    /etc/xdg/autostart/mate-screensaver.desktop && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
