# build patched libkwin and screencast plugin (x86_64 only, see patches/)
FROM ghcr.io/linuxserver/baseimage-selkies:dev AS kwinbuild
ARG DEBIAN_FRONTEND="noninteractive"

COPY /patches /build/patches

RUN \
  echo "**** enable source repos ****" && \
  sed -i \
    's/^Types: deb$/Types: deb deb-src/' \
    /etc/apt/sources.list.d/ubuntu.sources && \
  apt-get update && \
  echo "**** install build deps ****" && \
  apt-get install --no-install-recommends -y \
    ca-certificates \
    dpkg-dev && \
  apt-get build-dep -y kwin && \
  echo "**** build patched kwin targets ****" && \
  mkdir -p /build/src && \
  cd /build/src && \
  apt-get source kwin && \
  cd kwin-*/ && \
  for kwin_patch in /build/patches/*.patch; do \
    patch -p1 < "${kwin_patch}"; \
  done && \
  export DEB_BUILD_MAINT_OPTIONS="hardening=+all" && \
  export DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" && \
  dh_auto_configure -- \
    -DBUILD_TESTING=OFF \
    -DQTWAYLANDSCANNER_KDE_EXECUTABLE=/usr/lib/qt6/libexec/qtwaylandscanner && \
  dh_auto_build -- \
    kwin \
    screencast && \
  echo "**** stage patched files ****" && \
  LIBDIR=/build/patched/usr/lib/x86_64-linux-gnu && \
  mkdir -p \
    ${LIBDIR}/qt6/plugins/kwin/plugins && \
  cp \
    $(find obj-* -name 'libkwin.so.6.*' -type f) \
    ${LIBDIR}/ && \
  cp \
    $(find obj-* -name 'screencast.so' -type f) \
    ${LIBDIR}/qt6/plugins/kwin/plugins/ && \
  strip --strip-unneeded \
    --remove-section=.comment \
    --remove-section=.note \
    ${LIBDIR}/libkwin.so.6.* \
    ${LIBDIR}/qt6/plugins/kwin/plugins/screencast.so

FROM ghcr.io/linuxserver/baseimage-selkies:dev

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
ARG DEBIAN_FRONTEND="noninteractive"

# title
ENV TITLE="Ubuntu KDE" \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  add-apt-repository ppa:xtradeb/apps && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
    cargo \
    chromium \
    dolphin \
    gwenview \
    kde-config-gtk-style \
    kdialog \
    kfind \
    khotkeys \
    kio-extras \
    knewstuff-dialog \
    konsole \
    ksystemstats \
    kubuntu-settings-desktop \
    kubuntu-wallpapers \
    kwin-addons \
    kwin-x11 \
    kwrite \
    plasma-desktop \
    plasma-discover \
    plasma-workspace \
    qml-module-qt-labs-platform \
    systemsettings && \
  cargo install \
    wl-clipboard-rs-tools && \
  echo "**** replace wl-clipboard with rust ****" && \
  mv \
    /config/.cargo/bin/wl-* \
    /usr/bin/ && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** kde tweaks ****" && \
  setcap -r \
    /usr/bin/kwin_wayland && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /config/.cargo \
    /config/.launchpadlib \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY --from=kwinbuild /build/patched/ /
COPY /root /

# ports and volumes
EXPOSE 3001
VOLUME /config
