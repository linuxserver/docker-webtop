FROM ghcr.io/linuxserver/baseimage-kasmvnc:arch

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Arch MATE"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  pacman -Sy --noconfirm --needed \
    chromium \
    mate \
    mate-media \
    mate-terminal \
    pluma && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
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
    /config/.cache \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
