# build patched libkwin and screencast plugin (x86_64 only, see patches/)
FROM ghcr.io/linuxserver/baseimage-selkies:arch AS kwinbuild

COPY /patches /build/patches

RUN \
  echo "**** install build deps ****" && \
  pacman -Sy --noconfirm --needed \
    base-devel \
    cmake \
    extra-cmake-modules \
    kdoctools \
    krunner \
    kwin \
    plasma-wayland-protocols \
    python \
    vulkan-headers \
    wayland-protocols \
    xorg-xwayland && \
  echo "**** fetch arch kwin build recipe ****" && \
  KWIN_TAG=$(pacman -Q kwin | awk '{print $2}') && \
  mkdir -p /build/src && \
  cd /build/src && \
  curl -fLo PKGBUILD \
    https://gitlab.archlinux.org/archlinux/packaging/packages/kwin/-/raw/${KWIN_TAG}/PKGBUILD && \
  . ./PKGBUILD && \
  echo "**** fetch kwin ${pkgver} source ****" && \
  curl -fLo \
    kwin-${pkgver}.tar.xz \
    ${source[0]} && \
  echo "${sha256sums[0]}  kwin-${pkgver}.tar.xz" | sha256sum -c && \
  tar xf kwin-${pkgver}.tar.xz && \
  cd kwin-${pkgver}/ && \
  echo "**** build patched kwin targets ****" && \
  for kwin_patch in /build/patches/*.patch; do \
    patch -p1 < "${kwin_patch}"; \
  done && \
  . /etc/makepkg.conf && \
  export CFLAGS CXXFLAGS LDFLAGS && \
  cmake -B build \
    -DCMAKE_INSTALL_LIBEXECDIR=lib \
    -DBUILD_TESTING=OFF && \
  cmake --build build --parallel $(nproc) --target \
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

FROM ghcr.io/linuxserver/baseimage-selkies:arch

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Arch KDE" \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  pacman -Sy --noconfirm --needed \
    cargo \
    chromium \
    discover \
    dolphin \
    kate \
    konsole \
    kwin-x11 \
    plasma-desktop \
    plasma-x11-session && \
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
  setcap -r \
    /usr/sbin/kwin_wayland && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /config/.cargo \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY --from=kwinbuild /build/patched/ /
COPY /root /

# ports and volumes
EXPOSE 3001

VOLUME /config
