#!/bin/bash
set -e

# =============================================================================
# ROS Noetic + Xfce + VNC Container Entrypoint
# =============================================================================

# --- Configuration defaults --------------------------------------------------
DEFAULT_USER=${USER:-ubuntu}
DEFAULT_PASSWORD=${PASSWORD:-ubuntu}
VNC_PORT=${VNC_PORT:-5901}
VNC_GEOMETRY=${VNC_GEOMETRY:-1280x720}
VNC_DEPTH=${VNC_DEPTH:-24}
ROS_DISTRO=${ROS_DISTRO:-noetic}

# --- Create / configure user ------------------------------------------------
HOME_DIR="/home/$DEFAULT_USER"
echo "* Setting up user: $DEFAULT_USER"

# Create user if not root
if [ "$DEFAULT_USER" != "root" ] && ! id "$DEFAULT_USER" &>/dev/null; then
    useradd --create-home --shell /bin/bash --user-group --groups adm,sudo "$DEFAULT_USER"
    echo "$DEFAULT_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo "$DEFAULT_USER:$DEFAULT_PASSWORD" | /usr/sbin/chpasswd 2>/dev/null || true
    # Copy root's dotfiles as starting point
    cp -r /root/{.config,.gtkrc-2.0,.asoundrc} "$HOME_DIR" 2>/dev/null || true
    [ -d "/dev/snd" ] && chgrp -R adm /dev/snd
fi

# Ensure HOME is set
export HOME="$HOME_DIR"

# --- VNC password setup ------------------------------------------------------
echo "* Configuring VNC password..."
mkdir -p "$HOME/.vnc"
echo "$DEFAULT_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

# --- Xfce wallpaper configuration (Ubuntu 20.04 default) --------------------
# The default Ubuntu Focal wallpaper is /usr/share/backgrounds/warty-final-ubuntu.png
# or /usr/share/backgrounds/fossa-default.jpg if ubuntu-wallpapers is installed.
WALLPAPER=""
if [ -f /usr/share/backgrounds/ubuntu-focal/ubuntu-focal.png ]; then
    WALLPAPER="/usr/share/backgrounds/ubuntu-focal/ubuntu-focal.png"
elif [ -f /usr/share/backgrounds/warty-final-ubuntu.png ]; then
    WALLPAPER="/usr/share/backgrounds/warty-final-ubuntu.png"
elif [ -f /usr/share/backgrounds/fossa-default.jpg ]; then
    WALLPAPER="/usr/share/backgrounds/fossa-default.jpg"
else
    WALLPAPER="/usr/share/backgrounds/xfce/xfce-blue.jpg"
fi
echo "* Using wallpaper: $WALLPAPER"

# Write xfce4-desktop.xml to set wallpaper via xfconf channel
mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
cat << XFCE_DESKTOP_EOF > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="0"/>
    <property name="icon-size" type="int" value="48"/>
    <property name="show-icon-text" type="bool" value="true"/>
    <property name="show-mounted" type="bool" value="true"/>
    <property name="show-trash" type="bool" value="false"/>
    <property name="show-home" type="bool" value="false"/>
    <property name="filesystem" type="empty">
      <property name="show-removable" type="bool" value="false"/>
    </property>
  </property>
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$WALLPAPER"/>
          <property name="image-style" type="int" value="5"/>
          <property name="color-style" type="int" value="0"/>
          <property name="primary-color" type="string" value="#000000"/>
          <property name="secondary-color" type="string" value="#000000"/>
        </property>
      </property>
    </property>
  </property>
  <property name="windowing" type="empty">
    <property name="show-wm-menu" type="bool" value="true"/>
  </property>
</channel>
XFCE_DESKTOP_EOF

# Also set fallback wallpaper in case xfconf doesn't load early
# Xfce expects filenames like icons.screen0-1280x720.rc (keep the 'x')
mkdir -p "$HOME/.config/xfce4/desktop"
cat << XFCE_ICONS_EOF > "$HOME/.config/xfce4/desktop/icons.screen0-${VNC_GEOMETRY}.rc"
[xfce-desktop]
last-image=$WALLPAPER
image-style=5
color-style=0
primary-color=#000000
secondary-color=#000000
show-icon-text=true
icon-size=48
show-mounted=true
show-trash=false
show-home=false
XFCE_ICONS_EOF

# --- Desktop shortcuts: only ONE application launcher card -------------------
echo "* Creating desktop shortcuts (Terminator only)..."
mkdir -p "$HOME/Desktop"

# Remove any existing .desktop files we don't want
rm -f "$HOME/Desktop/"*.desktop 2>/dev/null || true

# Keep ONLY Terminator as the single launcher card
cat << TERMINATOR_DESKTOP_EOF > "$HOME/Desktop/terminator.desktop"
[Desktop Entry]
Version=1.0
Name=Terminator
Comment=Multiple terminals in one window
TryExec=terminator
Exec=terminator
Icon=utilities-terminal
Type=Application
Categories=GNOME;GTK;Utility;TerminalEmulator;
StartupNotify=true
Keywords=terminal;shell;prompt;command;commandline;
TERMINATOR_DESKTOP_EOF

chmod +x "$HOME/Desktop/terminator.desktop"

# --- catkin_ws workspace initialization -------------------------------------
echo "* Initializing catkin_ws workspace..."
mkdir -p "$HOME/catkin_ws/src"

# --- ROS environment setup in .bashrc ---------------------------------------
echo "* Configuring ROS environment..."
BASHRC="$HOME/.bashrc"
touch "$BASHRC"

grep -F "source /opt/ros/$ROS_DISTRO/setup.bash" "$BASHRC" || \
    echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> "$BASHRC"

grep -F "source \$HOME/catkin_ws/devel/setup.bash" "$BASHRC" || \
    echo "[ -f \$HOME/catkin_ws/devel/setup.bash ] && source \$HOME/catkin_ws/devel/setup.bash" >> "$BASHRC"

grep -F "export ROS_AUTOMATIC_DISCOVERY_RANGE=" "$BASHRC" || \
    echo "# export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST" >> "$BASHRC"

# --- xstartup for VNC session ------------------------------------------------
echo "* Writing xstartup..."
XSTARTUP="$HOME/.vnc/xstartup"
cat << XSTARTUP_EOF > "$XSTARTUP"
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
exec startxfce4
XSTARTUP_EOF
chmod 755 "$XSTARTUP"

# --- VNC server launch script -----------------------------------------------
echo "* Writing VNC launch script (geometry=${VNC_GEOMETRY}, depth=${VNC_DEPTH})..."
VNCRUN="$HOME/.vnc/vnc_run.sh"
cat << VNCRUN_EOF > "$VNCRUN"
#!/bin/bash
# Clean up stale VNC lock files
rm -f /tmp/.X*-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X* 2>/dev/null || true
rm -rf /tmp/.X11-unix 2>/dev/null || true

# Stop any existing VNC on :1
vncserver -kill :1 2>/dev/null || true
sleep 1

# Start VNC server (-localhost no: bind 0.0.0.0 so Docker port map works)
# TigerVNC 1.10.0 (Ubuntu 20.04 focal) uses '-localhost no' not '-no-localhost'
if [ "\$(uname -m)" = "aarch64" ]; then
    LD_PRELOAD=/lib/aarch64-linux-gnu/libgcc_s.so.1 \
        vncserver :1 -fg -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -localhost no
else
    vncserver :1 -fg -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -localhost no
fi
VNCRUN_EOF
chmod +x "$VNCRUN"

# --- noVNC launch script -----------------------------------------------------
# Port 8080 is used instead of 80 because non-root users can't bind to port 80
NOVNC_RUN="$HOME/.vnc/novnc_run.sh"
cat << NOVNC_EOF > "$NOVNC_RUN"
#!/bin/bash
# Wait briefly for VNC to be ready
sleep 2
exec websockify --web=/usr/lib/novnc 8080 localhost:5901
NOVNC_EOF
chmod +x "$NOVNC_RUN"

# --- Supervisor configuration ------------------------------------------------
echo "* Configuring supervisord..."
CONF="/etc/supervisor/conf.d/supervisord.conf"
cat << SUPERVISOR_EOF > "$CONF"
[supervisord]
nodaemon=true
user=root
logfile=/dev/null
pidfile=/tmp/supervisord.pid

[program:vnc]
command=gosu ${DEFAULT_USER} bash ${VNCRUN}
autorestart=true
restartsecs=3
stopsignal=TERM
stopasgroup=true
killasgroup=true

[program:novnc]
command=gosu ${DEFAULT_USER} bash ${NOVNC_RUN}
autorestart=true
restartsecs=3
SUPERVISOR_EOF

# --- Fix rosdep permissions --------------------------------------------------
echo "* Fixing rosdep permissions..."
mkdir -p "$HOME/.ros"
if [ -d /root/.ros/rosdep ]; then
    cp -r /root/.ros/rosdep "$HOME/.ros/rosdep" 2>/dev/null || true
fi

# --- Terminator profile config ----------------------------------------------
mkdir -p "$HOME/.config/terminator"
cat << TERMINATOR_CFG_EOF > "$HOME/.config/terminator/config"
[global_config]
[profiles]
  [[default]]
    background_color = "#1e1e1e"
    foreground_color = "#ffffff"
    palette = "#2d2d2d:#f27779:#b3de81:#eedc82:#83a598:#faacd3:#86c1b9:#eeeeec:#535353:#f27779:#b3de81:#eedc82:#83a598:#faacd3:#86c1b9:#ffffff"
    font = "DejaVu Sans Mono 11"
    use_system_font = False
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
TERMINATOR_CFG_EOF

# --- Apply correct ownership -------------------------------------------------
echo "* Setting ownership for $DEFAULT_USER..."
chown -R "$DEFAULT_USER:$DEFAULT_USER" "$HOME" 2>/dev/null || true
[ -d "/dev/snd" ] && chgrp -R adm /dev/snd 2>/dev/null || true

# --- Clear secrets -----------------------------------------------------------
# (Print summary BEFORE clearing the password variable)
echo ""
echo "====================================================================="
echo "  ROS Noetic + Xfce + VNC container ready!"
echo "  VNC port:  5901  (connect with AVNC using container IP)"
echo "  noVNC URL: http://<container-ip>:8080/"
echo "  Username:  $DEFAULT_USER"
echo "  Password:  $DEFAULT_PASSWORD"
echo "  Geometry:  ${VNC_GEOMETRY} (override with VNC_GEOMETRY env)"
echo "====================================================================="
echo ""

PASSWORD=""
DEFAULT_PASSWORD=""

# --- Launch supervisord (fix: single exec, removed the dangling second exec) -
exec /bin/tini -- supervisord -n -c /etc/supervisor/supervisord.conf
