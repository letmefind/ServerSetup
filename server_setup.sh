#!/bin/bash

set -e

PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD1GDXQ5Xgx4RAKC+wV//OhU5tYFW30TKtVd7+xT8qMKCAR/tXDZ8gP9p/V+6vrPwxyn1ImzDhUCA4NSORTvKe+/XjGKIbte11H05LsRmG9y9oOeMP/aesIgxYkUt9Nuu1CohIsbTGMxHfEUTM4MRfAKE3poxkoshPBv8Lt8o4RKDf91y+ih4rduPmJ++9xV031LXC+EC+bKfD4O+kaGy9WayRMWBrCtCcHhWPsXgQARQs5fjVV1LN4bmaAlVRxzJwBM1dCTqv0s41Y0bjqlzmxySjZDhFUyRnV1aPCFGhgVfoVDRH7s0YfuU/iiH/d+qkLHV4AmUfVV2xBjkncC4JR0i8Q1Gzpfd+JXxUBa/mSqg8E6NK2vXgycgiSy0YRzW5e/T/jlBNGb4RaDPHKVOae5VEnB4XTfPlO1hP/o8dWk2H5YLHrzMgIwjpc0yuhKp6GgNWJQjyMfajy7fPmHtverdP/shh9uon/XK1ylqrdjDuIrWx1nn1FWyKUBJmKVps= arash@Arashs-MacBook-Pro.local"

# === 1. Add public key to ~/.ssh/authorized_keys ===
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
grep -qF "$PUBKEY" ~/.ssh/authorized_keys || echo "$PUBKEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
echo "✅ Public key added to ~/.ssh/authorized_keys"

# === 2. Ask to change hostname ===
read -p "❓ Do you want to change the server hostname? (y/n): " change_hostname
if [[ "$change_hostname" == "y" ]]; then
  read -p "Enter new hostname: " new_hostname
  hostnamectl set-hostname "$new_hostname"
  echo "✅ Hostname changed to $new_hostname"
fi

# === 3. Install Docker and Docker Compose ===
echo "📦 Installing Docker and Docker Compose..."
curl -fsSL https://get.docker.com | bash -s docker
curl -L "https://github.com/docker/compose/releases/download/1.26.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
chkconfig docker on || true
service docker start
systemctl enable docker

# === 4. Setup XMPlus ===
echo "📁 Setting up XMPlus..."
mkdir -p /etc/XMPlus
cd /etc/XMPlus
apt update && apt install unzip -y
wget --no-check-certificate https://raw.githubusercontent.com/XMPlusDev/XMPlus/scripts/docker.zip
unzip docker.zip
chmod -R 777 /etc/XMPlus
rm -rf docker.zip

# === 5. Download geo data ===
wget -O /etc/XMPlus/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
wget -O /etc/XMPlus/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
wget -O /etc/XMPlus/iran.dat https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat

# === 6. Run WARP setup script ===
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh

# === 7. Copy XMPlus to 01 and 02 ===
cp -r /etc/XMPlus /etc/XMPlus01
cp -r /etc/XMPlus /etc/XMPlus02

# === 8. Setup docker-compose environment ===
mkdir -p /etc/Docker
cp /etc/XMPlus/config.yml /etc/Docker/docker-compose.yml

# === 9. Install rathole ===
bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/Musixal/rathole-tunnel/main/rathole_v2.sh)

# === 10. Download pingtunnel binary ===
cd /root
wget https://github.com/esrrhs/pingtunnel/releases/download/2.8/pingtunnel_linux_amd64.zip
apt install unzip -y
unzip pingtunnel_linux_amd64.zip
cp pingtunnel /usr/local/bin/

# === 11. Ask if user wants to install pingtunnel service ===
read -p "❓ Do you want to create and enable a systemd service for pingtunnel? (y/n): " setup_pingtunnel
if [[ "$setup_pingtunnel" == "y" ]]; then
  read -p "🌐 Enter remote server IP address (e.g., 154.90.54.173): " remote_ip
  read -p "📣 Enter local listen port (default 443): " local_port
  local_port=${local_port:-443}
  echo "📄 Creating pingtunnel systemd service..."

  cat <<EOF >/etc/systemd/system/pingtunnel.service
[Unit]
Description=pingtunnel Client (Optimized)
After=network.target

[Service]
ExecStart=/usr/local/bin/pingtunnel \\
  -type client \\
  -l :$local_port \\
  -s $remote_ip \\
  -t $remote_ip:$local_port \\
  -tcp 1 \\
  -nolog 1 \\
  -noprint 1 \\
  -loglevel none \\
  -timeout 60 \\
  -tcp_bs 2097152 \\
  -tcp_mw 50000
Restart=on-failure
RestartSec=3
User=root
WorkingDirectory=/usr/local/bin
StandardOutput=journal
StandardError=journal
LimitNOFILE=65535
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.icmp_ratelimit=0; sysctl -w net.ipv4.icmp_ratemask=0'

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now pingtunnel.service
  systemctl stop pingtunnel.service
  echo "✅ pingtunnel service created and enabled (currently stopped)"
else
  echo "ℹ️ Skipped pingtunnel systemd setup. Script finished."
  exit 0
fi

echo "✅ All steps completed!"
