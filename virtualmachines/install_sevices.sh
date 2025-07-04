#!/bin/bash

set -e

echo "### Disabling UFW..."
sudo ufw status || true
sudo ufw disable

echo "### Installing XFCE Desktop Environment..."
sudo apt update
sudo apt install -y xfce4 xfce4-goodies xorgxrdp dbus-x11

echo "### Adding user to groups..."
sudo usermod -a -G ssl-cert,xrdp $USER

echo "### Installing XRDP..."
sudo apt install -y xrdp
sudo systemctl enable --now xrdp
sudo systemctl status xrdp

echo "### Configuring XRDP session..."
echo "startxfce4" | sudo tee -a /etc/skel/.xsession
echo "startxfce4" > ~/.xsession

echo "### Editing /etc/xrdp/startwm.sh..."
sudo cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.backup
sudo bash -c 'cat > /etc/xrdp/startwm.sh' << 'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

startxfce4
EOF

echo "### Restarting XRDP services..."
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "### Installing TigerVNC..."
sudo apt install -y tigervnc-standalone-server tigervnc-xorg-extension tigervnc-viewer

echo "### Setting up VNC for user: $USER"
vncpasswd <<EOF
vm2test
vm2test
n
EOF

mkdir -p ~/.vnc
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF

chmod +x ~/.vnc/xstartup

echo "### Starting VNC server on :0..."
# Kill any existing VNC server
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

sudo bash -c 'cat > /etc/apt/preferences.d/mozilla' << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

sudo apt update
sudo apt install -y firefox

echo "### Setup complete! XRDP and VNC are now configured."
