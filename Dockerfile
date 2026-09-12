# syntax=docker/dockerfile:1

# build patched libkwin and screencast plugin (x86_64 only, see patches/)
FROM ghcr.io/linuxserver/baseimage-selkies:alpine324 AS kwinbuild

COPY /patches /build/patches

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    build-base \
    xz && \
  echo "**** fetch alpine kwin build recipe ****" && \
  mkdir -p /build/src && \
  cd /build/src && \
  curl -fLo APKBUILD \
    https://raw.githubusercontent.com/alpinelinux/aports/3.24-stable/community/kwin/APKBUILD && \
  . ./APKBUILD && \
  echo "**** install build deps ****" && \
  apk add --no-cache \
    ${makedepends} && \
  echo "**** fetch kwin ${pkgver} source ****" && \
  curl -fLo \
    kwin-${pkgver}.tar.xz \
    ${source} && \
  echo "${sha512sums}" | grep "kwin-${pkgver}.tar.xz" | sha512sum -c && \
  tar xf kwin-${pkgver}.tar.xz && \
  cd kwin-${pkgver}/ && \
  echo "**** build patched kwin targets ****" && \
  for kwin_patch in /build/patches/*.patch; do \
    patch -p1 < "${kwin_patch}"; \
  done && \
  CFLAGS="-O2 -g1" CXXFLAGS="-O2 -g1" \
  cmake -B build -G Ninja \
    -DBUILD_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib && \
  cmake --build build --target \
    kwin \
    screencast && \
  echo "**** stage patched files ****" && \
  LIBDIR=/build/patched/usr/lib && \
  mkdir -p \
    ${LIBDIR}/qt6/plugins/kwin/plugins && \
  cp \
    $(find build -name 'libkwin.so.6.*' -type f) \
    ${LIBDIR}/ && \
  cp \
    $(find build -name 'screencast.so' -type f) \
    ${LIBDIR}/qt6/plugins/kwin/plugins/ && \
  strip --strip-unneeded \
    --remove-section=.comment \
    --remove-section=.note \
    ${LIBDIR}/libkwin.so.6.* \
    ${LIBDIR}/qt6/plugins/kwin/plugins/screencast.so

FROM ghcr.io/linuxserver/baseimage-selkies:alpine324

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KDE_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Alpine KDE" \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install build packages ****" && \
  apk add --no-cache --upgrade --virtual=build-dependencies \
    cargo \
    libcap-utils \
    rust && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    breeze \
    chromium \
    discover \
    firefox \
    kde-applications-base \
    plasma-desktop \
    systemsettings && \
  cargo install \
    wl-clipboard-rs-tools && \
  echo "**** replace wl-clipboard with rust ****" && \
  mv \
    /config/.cargo/bin/wl-* \
    /usr/bin/ && \
  echo "**** kde tweaks ****" && \
  if getcap /usr/bin/kwin_wayland | grep -q cap; then \
    setcap -r /usr/bin/kwin_wayland; \
  fi && \
  echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /config/.cargo \
    /config/.cache \
    /etc/xdg/autostart/* \
    /tmp/*

# add local files
COPY --from=kwinbuild /build/patched/ /
COPY /root /

# ports and volumes
EXPOSE 3001

VOLUME /config
