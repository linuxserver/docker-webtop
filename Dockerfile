FROM ghcr.io/linuxserver/baseimage-kasmvnc:fedora39

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Fedora Openbox"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /kclient/public/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    chromium \
    obconf-qt \
    st && \
  echo "**** application tweaks ****" && \
  mv \
    /usr/bin/chromium-browser \
    /usr/bin/chromium-real && \
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
