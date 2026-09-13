#!/bin/bash

# Create User
USER=${USER:-root}
HOME=/root
if [ "$USER" != "root" ]; then
    echo "* enable custom user: $USER"
    useradd --create-home --shell /bin/bash --user-group --groups adm,sudo "$USER"
    echo "$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    if [ -z "$PASSWORD" ]; then
        echo "  set default password to \"ubuntu\""
        PASSWORD=ubuntu
    fi
    HOME="/home/$USER"
    echo "$USER:$PASSWORD" | /usr/sbin/chpasswd 2> /dev/null || echo ""
    cp -r /root/{.config,.gtkrc-2.0,.asoundrc} "$HOME" 2>/dev/null
    chown -R "$USER:$USER" "$HOME"
    [ -d "/dev/snd" ] && chgrp -R adm /dev/snd
fi

# RustDesk 受控端配置(环境变量设置 ID, 密码固定, 服务器/中继 192.168.9.234)
RD_ID=${RD_ID:-}
RD_SERVER=${RD_SERVER:-192.168.9.234}
RD_RELAY=${RD_RELAY:-192.168.9.234}
RD_PASSWORD=${RD_PASSWORD:-1234}
RD_DISPLAY=${RD_DISPLAY:-:1}   # 与 vncserver :1 保持一致

mkdir -p "$HOME/.config/rustdesk"
# RustDesk2.toml: 服务器/中继地址 + 固定密码策略
cat << EOF > "$HOME/.config/rustdesk/RustDesk2.toml"
[options]
custom-rendezvous-server = '$RD_SERVER'
relay-server = '$RD_RELAY'
verification-method = 'use-permanent-password'
EOF
# RustDesk.toml: 通过 id 字段注入自定义登录 ID(RD_ID 留空则由 RustDesk 自动生成)
# 格式需满足 RustDesk 要求: 字母开头, 6-16 位字母/数字/下划线/连字符
if [ -n "$RD_ID" ] && [[ ! "$RD_ID" =~ ^[a-zA-Z][a-zA-Z0-9_-]{5,15}$ ]]; then
    echo "WARN: RD_ID '$RD_ID' 格式无效, 回退为自动生成 ID"
    RD_ID=""
fi
cat << EOF > "$HOME/.config/rustdesk/RustDesk.toml"
enc_id = ''
id = '$RD_ID'
password = ''
salt = ''
key_pair = [ [], [] ]
key_confirmed = false
[keys_confirmed]
EOF
chown -R "$USER:$USER" "$HOME/.config/rustdesk"

# RustDesk 受控端启动脚本(以 root 运行以便通过 --password 设置固定密码,
# HOME 指向用户目录以读取正确配置)
RUSTDESK_RUN=/usr/local/bin/rustdesk_run.sh
cat << 'EOF' > $RUSTDESK_RUN
#!/bin/bash
export HOME="$RD_HOME"
export DISPLAY="$RD_DISPLAY"
# 等待 X server(noVNC 的 vncserver :1)就绪
for i in $(seq 1 60); do
    [ -e "/tmp/.X11-unix/X${RD_DISPLAY#:}" ] && break
    sleep 1
done
# 允许 root 访问 X server(noVNC 的 MATE 会话)
xhost +local: >/dev/null 2>&1
/usr/lib/rustdesk/rustdesk --server --no-tray &
SERVER_PID=$!
# 等待 IPC socket 就绪后设置固定密码
sleep 5
for i in $(seq 1 20); do
    [ -S "/tmp/RustDesk-0/ipc" ] && break
    sleep 1
done
/usr/lib/rustdesk/rustdesk --password "$RD_PASSWORD" >/dev/null 2>&1
wait "$SERVER_PID"
EOF
chmod 755 $RUSTDESK_RUN

# VNC password
VNC_PASSWORD=${PASSWORD:-ubuntu}

mkdir -p "$HOME/.vnc"
echo "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"
chown -R "$USER:$USER" "$HOME"
sed -i "s/password = WebUtil.getConfigVar('password');/password = '$VNC_PASSWORD'/" /usr/lib/novnc/app/ui.js

# xstartup
XSTARTUP_PATH="$HOME/.vnc/xstartup"
cat << EOF > "$XSTARTUP_PATH"
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
mate-session
EOF
chown "$USER:$USER" "$XSTARTUP_PATH"
chmod 755 "$XSTARTUP_PATH"

# vncserver launch
VNCRUN_PATH="$HOME/.vnc/vnc_run.sh"
cat << EOF > "$VNCRUN_PATH"
#!/bin/sh

# Workaround for issue when image is created with "docker commit".
# Thanks to @SaadRana17
# https://github.com/Tiryoh/docker-ros2-desktop-vnc/issues/131#issuecomment-2184156856

if [ -e /tmp/.X1-lock ]; then
    rm -f /tmp/.X1-lock
fi
if [ -e /tmp/.X11-unix/X1 ]; then
    rm -f /tmp/.X11-unix/X1
fi

if [ $(uname -m) = "aarch64" ]; then
    LD_PRELOAD=/lib/aarch64-linux-gnu/libgcc_s.so.1 vncserver :1 -fg -geometry 1920x1080 -depth 24
else
    vncserver :1 -fg -geometry 1920x1080 -depth 24
fi
EOF

# Supervisor
CONF_PATH=/etc/supervisor/conf.d/supervisord.conf
cat << EOF > $CONF_PATH
[supervisord]
nodaemon=true
user=root
[program:vnc]
command=gosu '$USER' bash '$VNCRUN_PATH'
[program:novnc]
command=gosu '$USER' bash -c "websockify --web=/usr/lib/novnc 80 localhost:5901"
[program:rustdesk]
command=/usr/local/bin/rustdesk_run.sh
autorestart=true
priority=30
environment=RD_HOME="$HOME",RD_PASSWORD="$RD_PASSWORD",RD_DISPLAY="$RD_DISPLAY"
EOF

# colcon
BASHRC_PATH="$HOME/.bashrc"
grep -F "source /opt/ros/$ROS_DISTRO/setup.bash" "$BASHRC_PATH" || echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> "$BASHRC_PATH"
grep -F "export ROS_AUTOMATIC_DISCOVERY_RANGE=" "$BASHRC_PATH" || echo "# export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST" >> "$BASHRC_PATH"
chown "$USER:$USER" "$BASHRC_PATH"

# Fix rosdep permission
mkdir -p "$HOME/.ros"
cp -r /root/.ros/rosdep "$HOME/.ros/rosdep"
chown -R "$USER:$USER" "$HOME/.ros"

# Add terminator shortcut
mkdir -p "$HOME/Desktop"
cat << EOF > "$HOME/Desktop/terminator.desktop"
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=Terminator
Comment=Multiple terminals in one window
TryExec=terminator
Exec=terminator
Icon=terminator
Type=Application
Categories=GNOME;GTK;Utility;TerminalEmulator;System;
StartupNotify=true
X-Ubuntu-Gettext-Domain=terminator
X-Ayatana-Desktop-Shortcuts=NewWindow;
Keywords=terminal;shell;prompt;command;commandline;
[NewWindow Shortcut Group]
Name=Open a New Window
Exec=terminator
TargetEnvironment=Unity
EOF
cat << EOF > "$HOME/Desktop/firefox.desktop"
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Name=Firefox Web Browser
Name[ar]=متصفح الويب فَيَرفُكْس
Name[ast]=Restolador web Firefox
Name[bn]=ফায়ারফক্স ওয়েব ব্রাউজার
Name[ca]=Navegador web Firefox
Name[cs]=Firefox Webový prohlížeč
Name[da]=Firefox - internetbrowser
Name[el]=Περιηγητής Firefox
Name[es]=Navegador web Firefox
Name[et]=Firefoxi veebibrauser
Name[fa]=مرورگر اینترنتی Firefox
Name[fi]=Firefox-selain
Name[fr]=Navigateur Web Firefox
Name[gl]=Navegador web Firefox
Name[he]=דפדפן האינטרנט Firefox
Name[hr]=Firefox web preglednik
Name[hu]=Firefox webböngésző
Name[it]=Firefox Browser Web
Name[ja]=Firefox ウェブ・ブラウザ
Name[ko]=Firefox 웹 브라우저
Name[ku]=Geroka torê Firefox
Name[lt]=Firefox interneto naršyklė
Name[nb]=Firefox Nettleser
Name[nl]=Firefox webbrowser
Name[nn]=Firefox Nettlesar
Name[no]=Firefox Nettleser
Name[pl]=Przeglądarka WWW Firefox
Name[pt]=Firefox Navegador Web
Name[pt_BR]=Navegador Web Firefox
Name[ro]=Firefox – Navigator Internet
Name[ru]=Веб-браузер Firefox
Name[sk]=Firefox - internetový prehliadač
Name[sl]=Firefox spletni brskalnik
Name[sv]=Firefox webbläsare
Name[tr]=Firefox Web Tarayıcısı
Name[ug]=Firefox توركۆرگۈ
Name[uk]=Веб-браузер Firefox
Name[vi]=Trình duyệt web Firefox
Name[zh_CN]=Firefox 网络浏览器
Name[zh_TW]=Firefox 網路瀏覽器
Comment=Browse the World Wide Web
Comment[ar]=تصفح الشبكة العنكبوتية العالمية
Comment[ast]=Restola pela Rede
Comment[bn]=ইন্টারনেট ব্রাউজ করুন
Comment[ca]=Navegueu per la web
Comment[cs]=Prohlížení stránek World Wide Webu
Comment[da]=Surf på internettet
Comment[de]=Im Internet surfen
Comment[el]=Μπορείτε να περιηγηθείτε στο διαδίκτυο (Web)
Comment[es]=Navegue por la web
Comment[et]=Lehitse veebi
Comment[fa]=صفحات شبکه جهانی اینترنت را مرور نمایید
Comment[fi]=Selaa Internetin WWW-sivuja
Comment[fr]=Naviguer sur le Web
Comment[gl]=Navegar pola rede
Comment[he]=גלישה ברחבי האינטרנט
Comment[hr]=Pretražite web
Comment[hu]=A világháló böngészése
Comment[it]=Esplora il web
Comment[ja]=ウェブを閲覧します
Comment[ko]=웹을 돌아 다닙니다
Comment[ku]=Li torê bigere
Comment[lt]=Naršykite internete
Comment[nb]=Surf på nettet
Comment[nl]=Verken het internet
Comment[nn]=Surf på nettet
Comment[no]=Surf på nettet
Comment[pl]=Przeglądanie stron WWW
Comment[pt]=Navegue na Internet
Comment[pt_BR]=Navegue na Internet
Comment[ro]=Navigați pe Internet
Comment[ru]=Доступ в Интернет
Comment[sk]=Prehliadanie internetu
Comment[sl]=Brskajte po spletu
Comment[sv]=Surfa på webben
Comment[tr]=İnternet'te Gezinin
Comment[ug]=دۇنيادىكى توربەتلەرنى كۆرگىلى بولىدۇ
Comment[uk]=Перегляд сторінок Інтернету
Comment[vi]=Để duyệt các trang web
Comment[zh_CN]=浏览互联网
Comment[zh_TW]=瀏覽網際網路
GenericName=Web Browser
GenericName[ar]=متصفح ويب
GenericName[ast]=Restolador Web
GenericName[bn]=ওয়েব ব্রাউজার
GenericName[ca]=Navegador web
GenericName[cs]=Webový prohlížeč
GenericName[da]=Webbrowser
GenericName[el]=Περιηγητής διαδικτύου
GenericName[es]=Navegador web
GenericName[et]=Veebibrauser
GenericName[fa]=مرورگر اینترنتی
GenericName[fi]=WWW-selain
GenericName[fr]=Navigateur Web
GenericName[gl]=Navegador Web
GenericName[he]=דפדפן אינטרנט
GenericName[hr]=Web preglednik
GenericName[hu]=Webböngésző
GenericName[it]=Browser web
GenericName[ja]=ウェブ・ブラウザ
GenericName[ko]=웹 브라우저
GenericName[ku]=Geroka torê
GenericName[lt]=Interneto naršyklė
GenericName[nb]=Nettleser
GenericName[nl]=Webbrowser
GenericName[nn]=Nettlesar
GenericName[no]=Nettleser
GenericName[pl]=Przeglądarka WWW
GenericName[pt]=Navegador Web
GenericName[pt_BR]=Navegador Web
GenericName[ro]=Navigator Internet
GenericName[ru]=Веб-браузер
GenericName[sk]=Internetový prehliadač
GenericName[sl]=Spletni brskalnik
GenericName[sv]=Webbläsare
GenericName[tr]=Web Tarayıcı
GenericName[ug]=توركۆرگۈ
GenericName[uk]=Веб-браузер
GenericName[vi]=Trình duyệt Web
GenericName[zh_CN]=网络浏览器
GenericName[zh_TW]=網路瀏覽器
Keywords=Internet;WWW;Browser;Web;Explorer
Keywords[ar]=انترنت;إنترنت;متصفح;ويب;وب
Keywords[ast]=Internet;WWW;Restolador;Web;Esplorador
Keywords[ca]=Internet;WWW;Navegador;Web;Explorador;Explorer
Keywords[cs]=Internet;WWW;Prohlížeč;Web;Explorer
Keywords[da]=Internet;Internettet;WWW;Browser;Browse;Web;Surf;Nettet
Keywords[de]=Internet;WWW;Browser;Web;Explorer;Webseite;Site;surfen;online;browsen
Keywords[el]=Internet;WWW;Browser;Web;Explorer;Διαδίκτυο;Περιηγητής;Firefox;Φιρεφοχ;Ιντερνετ
Keywords[es]=Explorador;Internet;WWW
Keywords[fi]=Internet;WWW;Browser;Web;Explorer;selain;Internet-selain;internetselain;verkkoselain;netti;surffaa
Keywords[fr]=Internet;WWW;Browser;Web;Explorer;Fureteur;Surfer;Navigateur
Keywords[he]=דפדפן;אינטרנט;רשת;אתרים;אתר;פיירפוקס;מוזילה;
Keywords[hr]=Internet;WWW;preglednik;Web
Keywords[hu]=Internet;WWW;Böngésző;Web;Háló;Net;Explorer
Keywords[it]=Internet;WWW;Browser;Web;Navigatore
Keywords[is]=Internet;WWW;Vafri;Vefur;Netvafri;Flakk
Keywords[ja]=Internet;WWW;Web;インターネット;ブラウザ;ウェブ;エクスプローラ
Keywords[nb]=Internett;WWW;Nettleser;Explorer;Web;Browser;Nettside
Keywords[nl]=Internet;WWW;Browser;Web;Explorer;Verkenner;Website;Surfen;Online
Keywords[pt]=Internet;WWW;Browser;Web;Explorador;Navegador
Keywords[pt_BR]=Internet;WWW;Browser;Web;Explorador;Navegador
Keywords[ru]=Internet;WWW;Browser;Web;Explorer;интернет;браузер;веб;файрфокс;огнелис
Keywords[sk]=Internet;WWW;Prehliadač;Web;Explorer
Keywords[sl]=Internet;WWW;Browser;Web;Explorer;Brskalnik;Splet
Keywords[tr]=İnternet;WWW;Tarayıcı;Web;Gezgin;Web sitesi;Site;sörf;çevrimiçi;tara
Keywords[uk]=Internet;WWW;Browser;Web;Explorer;Інтернет;мережа;переглядач;оглядач;браузер;веб;файрфокс;вогнелис;перегляд
Keywords[vi]=Internet;WWW;Browser;Web;Explorer;Trình duyệt;Trang web
Keywords[zh_CN]=Internet;WWW;Browser;Web;Explorer;网页;浏览;上网;火狐;Firefox;ff;互联网;网站;
Keywords[zh_TW]=Internet;WWW;Browser;Web;Explorer;網際網路;網路;瀏覽器;上網;網頁;火狐
Exec=firefox %u
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=firefox
Categories=GNOME;GTK;Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;
StartupNotify=true
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=Open a New Window
Name[ar]=افتح نافذة جديدة
Name[ast]=Abrir una ventana nueva
Name[bn]=Abrir una ventana nueva
Name[ca]=Obre una finestra nova
Name[cs]=Otevřít nové okno
Name[da]=Åbn et nyt vindue
Name[de]=Ein neues Fenster öffnen
Name[el]=Νέο παράθυρο
Name[es]=Abrir una ventana nueva
Name[fi]=Avaa uusi ikkuna
Name[fr]=Ouvrir une nouvelle fenêtre
Name[gl]=Abrir unha nova xanela
Name[he]=פתיחת חלון חדש
Name[hr]=Otvori novi prozor
Name[hu]=Új ablak nyitása
Name[it]=Apri una nuova finestra
Name[ja]=新しいウィンドウを開く
Name[ko]=새 창 열기
Name[ku]=Paceyeke nû veke
Name[lt]=Atverti naują langą
Name[nb]=Åpne et nytt vindu
Name[nl]=Nieuw venster openen
Name[pt]=Abrir nova janela
Name[pt_BR]=Abrir nova janela
Name[ro]=Deschide o fereastră nouă
Name[ru]=Новое окно
Name[sk]=Otvoriť nové okno
Name[sl]=Odpri novo okno
Name[sv]=Öppna ett nytt fönster
Name[tr]=Yeni pencere aç
Name[ug]=يېڭى كۆزنەك ئېچىش
Name[uk]=Відкрити нове вікно
Name[vi]=Mở cửa sổ mới
Name[zh_CN]=新建窗口
Name[zh_TW]=開啟新視窗
Exec=firefox -new-window

[Desktop Action new-private-window]
Name=Open a New Private Window
Name[ar]=افتح نافذة جديدة للتصفح الخاص
Name[ca]=Obre una finestra nova en mode d'incògnit
Name[cs]=Otevřít nové anonymní okno
Name[de]=Ein neues privates Fenster öffnen
Name[el]=Νέο ιδιωτικό παράθυρο
Name[es]=Abrir una ventana privada nueva
Name[fi]=Avaa uusi yksityinen ikkuna
Name[fr]=Ouvrir une nouvelle fenêtre de navigation privée
Name[he]=פתיחת חלון גלישה פרטית חדש
Name[hu]=Új privát ablak nyitása
Name[it]=Apri una nuova finestra anonima
Name[nb]=Åpne et nytt privat vindu
Name[ru]=Новое приватное окно
Name[sl]=Odpri novo okno zasebnega brskanja
Name[sv]=Öppna ett nytt privat fönster
Name[tr]=Yeni gizli pencere aç
Name[uk]=Відкрити нове вікно у потайливому режимі
Name[zh_TW]=開啟新隱私瀏覽視窗
Exec=firefox -private-window
EOF
cat << EOF > "$HOME/Desktop/codium.desktop"
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=VSCodium
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=/usr/share/codium/codium --unity-launch %F
Icon=vscodium
Type=Application
StartupNotify=false
StartupWMClass=VSCodium
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-codium-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/share/codium/codium --new-window %F
Icon=vscodium
EOF
chmod +x "$HOME/Desktop/*.desktop"
chown -R "$USER:$USER" "$HOME/Desktop"

# clearup
PASSWORD=
VNC_PASSWORD=

echo "============================================================================================"
echo "NOTE: Before stopping to commit docker container to new docker image, log out first."
echo -e 'See \e]8;;https://github.com/Tiryoh/docker-ros2-desktop-vnc/issue/131\e\\https://github.com/Tiryoh/docker-ros2-desktop-vnc/issue/131\e]8;;\e\\'
echo "============================================================================================"

exec /bin/tini -- supervisord -n -c /etc/supervisor/supervisord.conf
