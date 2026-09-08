# =============================================================================
# ROS Noetic + Xfce Desktop + VNC (AVNC Compatible)
# Base: Ubuntu 20.04 LTS (focal)
# =============================================================================

FROM ubuntu:focal-20250404

ARG TARGETPLATFORM
LABEL maintainer="Tiryoh<tiryoh@gmail.com>"
LABEL description="ROS Noetic desktop container with Xfce + TigerVNC + noVNC"

SHELL ["/bin/bash", "-c"]

# -----------------------------------------------------------------------------
# 1. Base OS upgrade
# -----------------------------------------------------------------------------
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
    apt-get autoclean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 2. Locale & Chinese fonts
# -----------------------------------------------------------------------------
ENV LANG=C.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    locales language-pack-zh-hans language-pack-gnome-zh-hans \
    fonts-wqy-microhei fonts-wqy-zenhei \
    desktop-file-utils && \
    locale-gen zh_CN.UTF-8 && \
    update-locale LANG=C.UTF-8 LANGUAGE=zh_CN:zh LC_ALL=C.UTF-8 && \
    update-desktop-database && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 3. Xfce Desktop + Ubuntu Focal wallpapers
# -----------------------------------------------------------------------------
# xubuntu-desktop pulls in Xfce + core apps (thunar, xfce4-terminal, etc.)
# NOTE: metapackage needs recommends to pull in full Xfce components.
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xubuntu-desktop && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Ubuntu Focal default wallpaper + additional backgrounds
# ubuntu-wallpapers provides warty-final-ubuntu.png (the iconic Ubuntu wallpaper)
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ubuntu-wallpapers && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 4. Core packages: TigerVNC, supervisor, tools
# -----------------------------------------------------------------------------
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        tigervnc-common \
        supervisor \
        wget curl gosu git sudo python3-pip tini \
        build-essential vim lsb-release \
        bash-completion tzdata terminator gedit \
        xfconf software-properties-common && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Remove LibreOffice to shrink image
RUN apt-get update -q && \
    apt-get purge -y "libreoffice*" 2>/dev/null || true && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 5. noVNC + Websockify (for browser-based access)
# -----------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/AtsushiSaito/noVNC.git -b add_clipboard_support /usr/lib/novnc && \
    pip install --no-cache-dir git+https://github.com/novnc/websockify.git@v0.10.0 && \
    ln -sf /usr/lib/novnc/vnc.html /usr/lib/novnc/index.html && \
    sed -i "s/UI.initSetting('resize', 'off');/UI.initSetting('resize', 'remote');/g" \
        /usr/lib/novnc/app/ui.js

# -----------------------------------------------------------------------------
# 6. Disable auto-update & crash reporter
# -----------------------------------------------------------------------------
RUN sed -i 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades && \
    sed -i 's/enabled=1/enabled=0/g' /etc/default/apport

# -----------------------------------------------------------------------------
# 7. Firefox (via Mozilla Team PPA for snap-less install)
# -----------------------------------------------------------------------------
RUN DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:mozillateam/ppa -y && \
    echo 'Package: *' > /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update -q && \
    apt-get install -y --allow-downgrades --no-install-recommends firefox && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 8. ROS Noetic installation
# -----------------------------------------------------------------------------
ENV ROS_DISTRO=noetic
ARG INSTALL_PACKAGE=desktop

RUN apt-get update -q && \
    apt-get install -y curl gnupg2 lsb-release && \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/ros.list > /dev/null && \
    apt-get update -q && \
    apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-${INSTALL_PACKAGE} \
        python3-rosinstall \
        python3-rosinstall-generator \
        python3-wstool \
        python3-catkin-tools \
        python3-osrf-pycommon \
        python3-argcomplete \
        python3-rosdep \
        python3-vcstool && \
    rosdep init && \
    rm -rf /var/lib/apt/lists/*

RUN rosdep update

# Gazebo + navigation stack (amd64 only — arm64 not maintained)
# http://repositories.ros.org/status_page/ros_noetic_dbv8.html?q=ign
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        apt-get update -q && \
        apt-get install -y --no-install-recommends \
            ros-${ROS_DISTRO}-gazebo-ros-pkgs \
            ros-${ROS_DISTRO}-ros-ign-gazebo \
            ros-noetic-arbotix \
            ros-noetic-gazebo-ros-control \
            ros-noetic-gmapping \
            ros-noetic-map-server \
            ros-noetic-amcl \
            ros-noetic-move-base \
            ros-noetic-navigation \
            ros-noetic-teleop-twist-keyboard && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# -----------------------------------------------------------------------------
# 9. Docker optimisation: allow apt-get completion inside container
# -----------------------------------------------------------------------------
RUN rm -f /etc/apt/apt.conf.d/docker-clean

# -----------------------------------------------------------------------------
# 10. Ports — VNC direct + noVNC web
# -----------------------------------------------------------------------------
EXPOSE 5901 8080

# -----------------------------------------------------------------------------
# 11. Default env (can be overridden at runtime)
# -----------------------------------------------------------------------------
ENV USER=ubuntu
ENV PASSWORD=ubuntu
ENV VNC_GEOMETRY=1280x720
ENV VNC_DEPTH=24
ENV VNC_PORT=5901

# -----------------------------------------------------------------------------
# 12. Copy entrypoint & launch
# -----------------------------------------------------------------------------
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
