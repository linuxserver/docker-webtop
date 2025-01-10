FROM ghcr.io/linuxserver/baseimage-kasmvnc:fedora41

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Fedora i3"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    chromium \
    dmenu \
    feh \
    i3 \
    i3status \
    st && \
  echo "**** application tweaks ****" && \
  mv \
    /usr/bin/chromium-browser \
    /usr/bin/chromium-real && \
  ln -s \
    /usr/bin/st-fedora \
    /usr/bin/x-terminal-emulator && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
