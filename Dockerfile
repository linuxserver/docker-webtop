FROM ghcr.io/linuxserver/baseimage-selkies:fedora44

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE="Fedora MATE"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    7zip \
    atril \
    caja \
    caja-open-terminal \
    caja-sendto \
    caja-wallpaper \
    chromium \
    dconf-editor \
    engrampa \
    eom \
    liberation-fonts-all \
    marco \
    mate-applets \
    mate-calc \
    mate-control-center \
    mate-desktop \
    mate-icon-theme \
    mate-media \
    mate-menus \
    mate-menus-preferences-category-menu \
    mate-notification-daemon \
    mate-panel \
    mate-session-manager \
    mate-system-monitor \
    mate-terminal \
    mate-themes \
    mate-utils \
    mozo \
    pluma \
    unzip \
    xdg-user-dirs \
    zip && \
  echo "**** application tweaks ****" && \
  sed -i \
    's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium-browser.desktop && \
  echo "**** mate tweaks ****" && \
  rm -f \
    /etc/xdg/autostart/at-spi-dbus-bus.desktop \
    /etc/xdg/autostart/gnome-keyring-pkcs11.desktop \
    /etc/xdg/autostart/gnome-keyring-secrets.desktop \
    /etc/xdg/autostart/gnome-keyring-ssh.desktop \
    /etc/xdg/autostart/mate-power-manager.desktop \
    /etc/xdg/autostart/mate-screensaver.desktop \
    /etc/xdg/autostart/polkit-mate-authentication-agent-1.desktop \
    /usr/share/dbus-1/services/org.knopwob.dunst.service \
    /usr/share/dbus-1/services/org.mate.ScreenSaver.service && \
  sed -i \
    '/compositing-manager/{n;s/.*/      <default>false<\/default>/}' \
    /usr/share/glib-2.0/schemas/org.mate.marco.gschema.xml && \
    glib-compile-schemas /usr/share/glib-2.0/schemas/ && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /config/.cache \
    /tmp/* \
    /usr/bin/mate-screensaver

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
