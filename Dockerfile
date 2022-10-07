FROM ghcr.io/linuxserver/baseimage-rdesktop-web:fedora

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    desktop-backgrounds-compat \
    greybird-dark-theme \
    greybird-xfwm4-theme \
    gtk-xfce-engine \
    firefox \
    mousepad \
    Thunar \
    xfce4-appfinder \
    xfce4-datetime-plugin \
    xfce4-panel \
    xfce4-places-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-session \
    xfce4-settings \
    xfce4-terminal \
    xfconf \
    xfdesktop \
    xfwm4 \
    xfwm4-themes && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
