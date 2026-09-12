# build patched libkwin and screencast plugin (x86_64 only, see patches/)
FROM ghcr.io/linuxserver/baseimage-selkies:fedora44 AS kwinbuild

COPY /patches /build/patches

RUN \
  echo "**** install build packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    dnf5-plugins \
    kf6-rpm-macros \
    rpm-build && \
  echo "**** fetch fedora kwin source package ****" && \
  mkdir -p /build/src && \
  dnf download -y --srpm --destdir=/build/src \
    kwin && \
  dnf builddep -y --setopt=install_weak_deps=False \
    /build/src/kwin-*.src.rpm && \
  rpm --define "_topdir /build/rpmbuild" -i \
    /build/src/kwin-*.src.rpm && \
  echo "**** add patches to the fedora spec ****" && \
  i=100 && \
  for kwin_patch in /build/patches/*.patch; do \
    cp "${kwin_patch}" /build/rpmbuild/SOURCES/ && \
    sed -i "/^Source1:/a Patch${i}: $(basename "${kwin_patch}")" \
      /build/rpmbuild/SPECS/kwin.spec && \
    i=$((i + 1)); \
  done && \
  sed -i \
    's/^%cmake_build$/%cmake_build --target kwin screencast/' \
    /build/rpmbuild/SPECS/kwin.spec && \
  echo "**** build patched kwin targets ****" && \
  rpmbuild --define "_topdir /build/rpmbuild" -bc --nodeps \
    /build/rpmbuild/SPECS/kwin.spec && \
  echo "**** stage patched files ****" && \
  LIBDIR=/build/patched/usr/lib64 && \
  mkdir -p \
    ${LIBDIR}/qt6/plugins/kwin/plugins && \
  cp \
    $(find /build/rpmbuild/BUILD -name 'libkwin.so.6.*' -type f) \
    ${LIBDIR}/ && \
  cp \
    $(find /build/rpmbuild/BUILD -name 'screencast.so' -type f) \
    ${LIBDIR}/qt6/plugins/kwin/plugins/ && \
  strip --strip-unneeded \
    --remove-section=.comment \
    --remove-section=.note \
    ${LIBDIR}/libkwin.so.6.* \
    ${LIBDIR}/qt6/plugins/kwin/plugins/screencast.so

FROM ghcr.io/linuxserver/baseimage-selkies:fedora44

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Fedora KDE" \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    breeze-icon-theme \
    cargo \
    chromium \
    dolphin \
    kde-gtk-config \
    kde-settings-pulseaudio \
    kde-wallpapers \
    kdialog \
    kfind \
    kmenuedit \
    konsole5 \
    kwrite \
    plasma-breeze \
    plasma-desktop \
    plasma-discover \
    plasma-systemmonitor \
    plasma-workspace-xorg \
    qt5-qtscript && \
  cargo install \
    wl-clipboard-rs-tools && \
  echo "**** replace wl-clipboard with rust ****" && \
  mv \
    /config/.cargo/bin/wl-* \
    /usr/bin/ && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium-browser.desktop && \
  setcap -r \
    /usr/sbin/kwin_wayland && \
  ln -s \
    /usr/sbin/qdbus-qt6 \
    /usr/sbin/qdbus6 && \
  echo "**** kde tweaks ****" && \
  rm -f \
    /etc/xdg/autostart/at-spi-dbus-bus.desktop \
    /etc/xdg/autostart/gmenudbusmenuproxy.desktop \
    /etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop \
    /etc/xdg/autostart/powerdevil.desktop && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /config/.cargo \
    /config/.cache \
    /tmp/*

# add local files
COPY --from=kwinbuild /build/patched/ /
COPY /root /

# ports and volumes
EXPOSE 3001
VOLUME /config
