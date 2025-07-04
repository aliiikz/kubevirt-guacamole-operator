#!/bin/bash

# Copy-paste friendly version - no interactive prompts or here-docs
# Can be run line by line or as a whole script

set -e

echo "### Disabling UFW..."
sudo ufw status || true
sudo ufw disable

echo "### Installing XFCE Desktop Environment..."
sudo apt update
sudo apt install -y xfce4 xfce4-goodies xorgxrdp dbus-x11

echo "### Installing XRDP..."
sudo apt install -y xrdp
sudo systemctl enable --now xrdp
sudo systemctl status xrdp

echo "### Configuring XRDP session..."
echo "startxfce4" | sudo tee -a /etc/skel/.xsession
echo "startxfce4" > ~/.xsession

echo "### Editing /etc/xrdp/startwm.sh..."
sudo cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.backup
echo "#!/bin/sh" | sudo tee /etc/xrdp/startwm.sh
echo "if [ -r /etc/default/locale ]; then" | sudo tee -a /etc/xrdp/startwm.sh
echo "    . /etc/default/locale" | sudo tee -a /etc/xrdp/startwm.sh
echo "    export LANG LANGUAGE" | sudo tee -a /etc/xrdp/startwm.sh
echo "fi" | sudo tee -a /etc/xrdp/startwm.sh
echo "" | sudo tee -a /etc/xrdp/startwm.sh
echo "startxfce4" | sudo tee -a /etc/xrdp/startwm.sh

echo "### Restarting XRDP services..."
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "### Installing TigerVNC..."
sudo apt install -y tigervnc-standalone-server tigervnc-xorg-extension tigervnc-viewer

echo "### Setting up VNC for user: $USER"
echo "### Setting VNC password to 'vm2test' (no prompts)..."
mkdir -p ~/.vnc
echo "vm2test" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

echo "### Creating VNC startup script..."
mkdir -p ~/.vnc
echo "#!/bin/sh" > ~/.vnc/xstartup
echo "unset SESSION_MANAGER" >> ~/.vnc/xstartup
echo "unset DBUS_SESSION_BUS_ADDRESS" >> ~/.vnc/xstartup
echo "exec startxfce4" >> ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup

echo "### Starting VNC server on :0..."
vncserver -kill :0 || true
sleep 2
vncserver :0 -geometry 1920x1080 -depth 24 -localhost no

echo "### Removing Snap-based Firefox..."
sudo snap remove firefox || true
sudo apt remove -y firefox || true

echo "### Installing Firefox from Mozilla APT repo..."
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null

echo "### Creating Mozilla APT preferences..."
echo "Package: *" | sudo tee /etc/apt/preferences.d/mozilla
echo "Pin: origin packages.mozilla.org" | sudo tee -a /etc/apt/preferences.d/mozilla
echo "Pin-Priority: 1000" | sudo tee -a /etc/apt/preferences.d/mozilla

sudo apt update
sudo apt install -y firefox

echo "### Setup complete! XRDP and VNC are now configured."
echo "### VNC Password: vm2test"
