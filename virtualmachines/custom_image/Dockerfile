FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Create ubuntu user with sudo privileges (if it doesn't exist)
RUN useradd -m -s /bin/bash -G sudo ubuntu 2>/dev/null || usermod -aG sudo ubuntu && \
    echo "ubuntu:ubuntu" | chpasswd

# Disable Security - UFW Firewall
# RUN ufw --force disable

# Update system and install all packages in one go for better caching
RUN apt update && apt upgrade -y && apt install -y \
    vim \
    curl \
    wget \
    xfce4 \
    xfce4-goodies \
    xorgxrdp \
    dbus-x11 \
    xrdp \
    tigervnc-standalone-server \
    tigervnc-xorg-extension \
    tigervnc-viewer \
    && rm -rf /var/lib/apt/lists/*

# Create or edit the startup file
RUN echo "startxfce4" | tee -a /etc/skel/.xsession

# Configure XRDP startwm.sh
RUN cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.backup && \
    printf '#!/bin/sh\nif [ -r /etc/default/locale ]; then\n    . /etc/default/locale\n    export LANG LANGUAGE\nfi\n\nstartxfce4\n' > /etc/xrdp/startwm.sh

# Switch to ubuntu user for VNC configuration
USER ubuntu
WORKDIR /home/ubuntu

# Create VNC Directory
RUN mkdir -p ~/.vnc

# Configure VNC for ubuntu user
# Set up VNC password to "vm2test" (using both methods for compatibility)
RUN echo "vm2test" | vncpasswd -f > ~/.vnc/passwd && \
    chmod 600 ~/.vnc/passwd && \
    echo "vm2test\nvm2test\nn" | vncpasswd || true

# Create VNC Startup Configuration with proper content
RUN printf '#!/bin/sh\n# VNC xstartup script\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\n\n# Start XFCE4 desktop environment\nexec startxfce4\n' > ~/.vnc/xstartup

# Make xstartup executable
RUN chmod +x ~/.vnc/xstartup

# Create VNC config file for additional settings
RUN printf 'geometry=1920x1080\ndepth=24\n' > ~/.vnc/config

# Configure session for ubuntu user
RUN echo "startxfce4" > ~/.xsession && \
    chmod +x ~/.xsession

# Switch back to root for Firefox installation
USER root

# Install OpenSSH server and Firefox
RUN apt update && apt install -y openssh-server firefox && \
    ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*

# Create startup script to start all services
RUN printf '#!/bin/bash\n# Start necessary services\nservice dbus start\nservice ssh start\nservice xrdp start\nservice xrdp-sesman start\n\n# Auto-start VNC server for ubuntu user\nsu - ubuntu -c "vncserver :0 -geometry 1920x1080 -depth 24 -localhost no" 2>/dev/null || true\nsu - ubuntu -c "vncserver :1 -geometry 1920x1080 -depth 24 -localhost no" 2>/dev/null || true\n\n# Keep container running\ntail -f /dev/null\n' > /usr/local/bin/start-services.sh

RUN chmod +x /usr/local/bin/start-services.sh

# Clean up
RUN apt autoremove -y && apt autoclean && rm -rf /var/lib/apt/lists/*

# Switch back to ubuntu user
USER ubuntu
WORKDIR /home/ubuntu

# Expose ports for SSH, RDP, and VNC
EXPOSE 22 3389 5900 5901

# Start all services
CMD ["/usr/local/bin/start-services.sh"]
