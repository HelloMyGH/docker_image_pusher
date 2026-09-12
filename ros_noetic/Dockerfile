# Copyright 2020-2024 Tiryoh<tiryoh@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This Dockerfile is based on https://github.com/AtsushiSaito/docker-ubuntu-sweb
# which is released under the Apache-2.0 license.

FROM ubuntu:focal-20250404

ARG TARGETPLATFORM
LABEL maintainer="Tiryoh<tiryoh@gmail.com>"

SHELL ["/bin/bash", "-c"]

# Upgrade OS
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
    apt-get autoclean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*
# Install locale
ENV LANG=C.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
  locales language-pack-zh-hans language-pack-gnome-zh-hans fonts-wqy-microhei  fonts-wqy-zenhei desktop-file-utils && \
  locale-gen zh_CN.UTF-8 && \
  update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh LC_ALL=zh_CN.UTF-8 && \
  update-desktop-database && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# Install Ubuntu xfce4 desktop
RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xubuntu-desktop && \
    apt-get autoclean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*

# Add Package
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        supervisor wget curl gosu git sudo python3-pip tini \
        build-essential vim sudo lsb-release locales \
        bash-completion tzdata terminator gedit \
        xvfb && \
    apt-get autoclean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*
# remove liboffice
RUN apt-get update && \
    apt-get purge -y "libreoffice*" && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
# Disable auto update and crash report
RUN sed -i 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
RUN sed -i 's/enabled=1/enabled=0/g' /etc/default/apport

# Install Firefox
RUN DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:mozillateam/ppa -y && \
    echo 'Package: *' > /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update -q && \
    apt-get install -y --allow-downgrades \
    firefox && \
    apt-get autoclean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*

# Install ROS
ENV ROS_DISTRO noetic
# desktop or ros-base
ARG INSTALL_PACKAGE=desktop

RUN apt-get update -q && \
    apt-get install -y curl gnupg2 lsb-release && \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros.list > /dev/null && \
    apt-get update -q && \
    apt-get install -y ros-${ROS_DISTRO}-${INSTALL_PACKAGE} \
    python3-rosinstall \
    python3-rosinstall-generator \
    python3-wstool \
    python3-catkin-tools \
    python3-osrf-pycommon \
    python3-argcomplete \
    python3-rosdep python3-vcstool && \
    rosdep init && \
    rm -rf /var/lib/apt/lists/*

RUN rosdep update
# Gazebo packages for arm64 are not maintained.
# http://repositories.ros.org/status_page/ros_noetic_dbv8.html?q=ign
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
    apt-get update -q && \
    apt-get install -y \
    ros-${ROS_DISTRO}-gazebo-ros-pkgs \
    ros-${ROS_DISTRO}-ros-ign-gazebo \
    ros-noetic-arbotix ros-noetic-gazebo-ros-control \
    ros-noetic-gmapping ros-noetic-map-server \
    ros-noetic-amcl ros-noetic-move-base \
    ros-noetic-navigation ros-noetic-teleop-twist-keyboard && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Enable apt-get completion after running `apt-get update` in the container
RUN rm /etc/apt/apt.conf.d/docker-clean

# RustDesk 被控端(无 GUI,只做 server)
COPY rustdesk-headless /usr/lib/rustdesk/rustdesk
RUN chmod 755 /usr/lib/rustdesk/rustdesk

COPY ./entrypoint.sh /
ENTRYPOINT [ "/bin/bash", "-c", "/entrypoint.sh" ]

ENV USER ubuntu
ENV PASSWD ubuntu
