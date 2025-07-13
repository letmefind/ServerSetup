#!/bin/bash

set -e

# === 1. SSH Key ===
PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD1GDXQ5Xgx4RAKC+wV//OhU5tYFW30TKtVd7+xT8qMKCAR/tXDZ8gP9p/V+6vrPwxyn1ImzDhUCA4NSORTvKe+/XjGKIbte11H05LsRmG9y9oOeMP/aesIgxYkUt9Nuu1CohIsbTGMxHfEUTM4MRfAKE3poxkoshPBv8Lt8o4RKDf91y+ih4rduPmJ++9xV031LXC+EC+bKfD4O+kaGy9WayRMWBrCtCcHhWPsXgQARQs5fjVV1LN4bmaAlVRxzJwBM1dCTqv0s41Y0bjqlzmxySjZDhFUyRnV1aPCFGhgVfoVDRH7s0YfuU/iiH/d+qkLHV4AmUfVV2xBjkncC4JR0i8Q1Gzpfd+JXxUBa/mSqg8E6NK2vXgycgiSy0YRzW5e/T/jlBNGb4RaDPHKVOae5VEnB4XTfPlO1hP/o8dWk2H5YLHrzMgIwjpc0yuhKp6GgNWJQjyMfajy7fPmHtverdP/shh9uon/XK1ylqrdjDuIrWx1nn1FWyKUBJmKVps= arash@Arashs-MacBook-Pro.local"

mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
grep -qF "$PUBKEY" ~/.ssh/authorized_keys || echo "$PUBKEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
echo "✅ Public key added to ~/.ssh/authorized_keys"

# === 2. Hostname Change ===
read -p "❓ Do you want to change the hostname? (y/n): " change_hostname
if [[ "$change_hostname" == "y" ]]; then
  read -p "Enter new hostname: " new_hostname
  hostnamectl set-hostname "$new_hostname"
  echo "✅ Hostname changed to $new_hostname"
fi

# === 8. Install Rathole ===
bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/Musixal/rathole-tunnel/main/rathole_v2.sh)

# === 9. Install pingtunnel ===
cd /root
wget https://github.com/esrrhs/pingtunnel/releases/download/2.8/pingtunnel_linux_amd64.zip
apt update && apt install unzip -y
unzip -o pingtunnel_linux_amd64.zip
cp pingtunnel /usr/local/bin/

read -p "❓ Do you want to create a systemd service for pingtunnel? (y/n): " setup_pingtunnel
if [[ "$setup_pingtunnel" == "y" ]]; then
  read -p "🌐 Enter remote IP: " remote_ip
  read -p "📣 Enter local listen port (default 443): " local_port
  local_port=${local_port:-443}

  cat <<EOF >/etc/systemd/system/pingtunnel.service
[Unit]
Description=pingtunnel Client
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
  echo "✅ pingtunnel systemd service configured"
else
  echo "ℹ️ Skipped pingtunnel systemd setup"
fi

echo "🎉 Basic setup completed."
