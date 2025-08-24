#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config
# =========================
PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD1GDXQ5Xgx4RAKC+wV//OhU5tYFW30TKtVd7+xT8qMKCAR/tXDZ8gP9p/V+6vrPwxyn1ImzDhUCA4NSORTvKe+/XjGKIbte11H05LsRmG9y9oOeMP/aesIgxYkUt9Nuu1CohIsbTGMxHfEUTM4MRfAKE3poxkoshPBv8Lt8o4RKDf91y+ih4rduPmJ++9xV031LXC+EC+bKfD4O+kaGy9WayRMWBrCtCcHhWPsXgQARQs5fjVV1LN4bmaAlVRxzJwBM1dCTqv0s41Y0bjqlzmxySjZDhFUyRnV1aPCFGhgVfoVDRH7s0YfuU/iiH/d+qkLHV4AmUfVV2xBjkncC4JR0i8Q1Gzpfd+JXxUBa/mSqg8E6NK2vXgycgiSy0YRzW5e/T/jlBNGb4RaDPHKVOae5VEnB4XTfPlO1hP/o8dWk2H5YLHrzMgIwjpc0yuhKp6GgNWJQjyMfajy7fPmHtverdP/shh9uon/XK1ylqrdjDuIrWx1nn1FWyKUBJmKVps= arash@Arashs-MacBook-Pro.local"

# =========================
# Helpers
# =========================
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
press_enter() { read -rp "Press Enter to continue..."; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# =========================
# Cron: restart-rathole.sh
# =========================
install_rathole_restart_cron() {
  require_root
  local script_path="/usr/local/bin/restart-rathole.sh"
  local log_path="/var/log/restart-rathole.log"
  local cron_line='0 * * * * /usr/local/bin/restart-rathole.sh >> /var/log/restart-rathole.log 2>&1'
  local tmp_cron
  tmp_cron="$(mktemp)"

  cat > "$script_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
echo "[$(timestamp)] ---- rathole restart pass started ----"

# Gather services that start with "rathole" and end with .service
mapfile -t services < <(
  {
    systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null || true
    systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null || true
  } | awk '{print $1}' | grep -E '^rathole.*\.service$' | sort -u
)

if [[ ${#services[@]} -eq 0 ]]; then
  echo "[$(timestamp)] No services matching 'rathole*.service' found."
  exit 0
fi

for svc in "${services[@]}"; do
  echo "[$(timestamp)] Restarting ${svc}..."
  if systemctl restart "$svc"; then
    echo "[$(timestamp)] OK: ${svc} restarted."
  else
    echo "[$(timestamp)] ERROR: Failed to restart ${svc}." >&2
  fi
done

echo "[$(timestamp)] ---- rathole restart pass finished ----"
EOF

  chmod +x "$script_path"
  touch "$log_path" || true

  # Root crontab: keep SHELL/PATH for reliability and add the job if missing
  crontab -l 2>/dev/null | grep -Fv "$script_path" > "$tmp_cron" || true
  grep -q '^SHELL=' "$tmp_cron" 2>/dev/null || echo "SHELL=/bin/bash" >> "$tmp_cron"
  grep -q '^PATH=' "$tmp_cron" 2>/dev/null || echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$tmp_cron"
  grep -Fq "$cron_line" "$tmp_cron" || echo "$cron_line" >> "$tmp_cron"
  crontab "$tmp_cron"
  rm -f "$tmp_cron"

  echo "✅ Installed hourly rathole restart cron."
  echo "   Script: $script_path"
  echo "   Log:    $log_path"
}

remove_rathole_restart_cron() {
  require_root
  local cron_line='0 * * * * /usr/local/bin/restart-rathole.sh >> /var/log/restart-rathole.log 2>&1'
  local tmp_cron
  tmp_cron="$(mktemp)"
  crontab -l 2>/dev/null | grep -Fv "$cron_line" > "$tmp_cron" || true
  crontab "$tmp_cron" || true
  rm -f "$tmp_cron"
  echo "🗑️  Removed the rathole restart cron (if present)."
}

show_root_crontab() {
  echo "----- Current root crontab -----"
  crontab -l 2>/dev/null || echo "(no crontab set for root)"
  echo "--------------------------------"
}

cron_menu() {
  while true; do
    echo
    echo "Cron Jobs Menu"
    echo "1) Install hourly restart for rathole*.service"
    echo "2) Remove that cron job"
    echo "3) Show root crontab"
    echo "4) Back to main menu"
    read -rp "Choose an option [1-4]: " c
    case "$c" in
      1) install_rathole_restart_cron ;;
      2) remove_rathole_restart_cron ;;
      3) show_root_crontab ; press_enter ;;
      4) break ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

# =========================
# Your original installer (cleaned)
# =========================
server_setup_main() {
  require_root
  echo ">>> (1) SSH key setup"
  mkdir -p ~/.ssh
  touch ~/.ssh/authorized_keys
  if ! grep -qF "$PUBKEY" ~/.ssh/authorized_keys; then
    echo "$PUBKEY" >> ~/.ssh/authorized_keys
  fi
  chmod 600 ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  echo "✅ Public key added."

  echo
  read -rp "❓ Change hostname? (y/n): " change_hostname
  if [[ "${change_hostname,,}" == "y" ]]; then
    read -rp "Enter new hostname: " new_hostname
    hostnamectl set-hostname "$new_hostname"
    echo "✅ Hostname changed to: $new_hostname"
  fi

  echo
  echo ">>> (3) Docker & docker-compose"
  if ! cmd_exists docker; then
    curl -fsSL https://get.docker.com | bash -s docker
  fi

  if ! [[ -x /usr/local/bin/docker-compose ]]; then
    curl -L "https://github.com/docker/compose/releases/download/1.26.1/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi

  # Enable/start docker (handle both systemd and sysvinit)
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker  >/dev/null 2>&1 || true
  service docker start     >/dev/null 2>&1 || true
  chkconfig docker on      >/dev/null 2>&1 || true

  echo
  echo ">>> (4) XMPlus"
  mkdir -p /etc/XMPlus
  cd /etc/XMPlus
  if cmd_exists apt; then
    apt update -y
    apt install -y unzip wget
  fi

  wget --no-check-certificate -O docker.zip https://raw.githubusercontent.com/XMPlusDev/XMPlus/scripts/docker.zip
  unzip -o docker.zip
  chmod -R 777 /etc/XMPlus
  rm -f docker.zip

  # 4.1 config.yml
  cat > /etc/XMPlus/config.yml <<'EOF'
Log:
  Level: none
  AccessPath:
  ErrorPath:
  DNSLog: false
  MaskAddress: half
DnsConfigPath: /etc/XMPlus/dns.json
RouteConfigPath: /etc/XMPlus/route.json
InboundConfigPath:
OutboundConfigPath: /etc/XMPlus/outbound.json
ConnectionConfig:
  Handshake: 8
  ConnIdle: 300
  UplinkOnly: 0
  DownlinkOnly: 0
  BufferSize: 64
Nodes:
  -
    ApiConfig:
      ApiHost: "https://www.symmetricnet.com"
      ApiKey: "0DiCibh0MkCgVWM00XTnmx"
      NodeID: 105
      Timeout: 30
      RuleListPath: /etc/XMPlus/rulelist
    ControllerConfig:
      EnableDNS: false
      DNSStrategy: AsIs
      CertConfig:
        Email: author@xmplus.dev
        CertFile: /etc/XMPlus/node1.xmplus.dev.crt
        KeyFile: /etc/XMPlus/node1.xmplus.dev.key
        Provider: cloudflare
        CertEnv:
          CLOUDFLARE_EMAIL:
          CLOUDFLARE_API_KEY:
      EnableFallback: false
      FallBackConfigs:
        - SNI:
          Alpn:
          Path:
          Dest: 80
          ProxyProtocolVer: 0
      IPLimit:
        Enable: false
        RedisNetwork: tcp
        RedisAddr: 127.0.0.1:6379
        RedisUsername:
        RedisPassword: YOUR PASSWORD
        RedisDB: 0
        Timeout: 5
        Expiry: 60
EOF

  # 4.2 route.json from GitHub
  rm -f /etc/XMPlus/route.json
  wget -O /etc/XMPlus/route.json https://raw.githubusercontent.com/letmefind/ServerSetup/main/route_rules.json

  # 4.3 outbound.json
  cat > /etc/XMPlus/outbound.json <<'EOF'
[
  {
    "protocol": "freedom",
    "settings": {}
  },
  {
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  },
  {
    "tag": "socks5-warp",
    "protocol": "socks",
    "settings": {
      "servers": [
        {
          "address": "127.0.0.1",
          "port": 40000
        }
      ]
    }
  }
]
EOF

  # 4.4 docker-compose
  mkdir -p /etc/Docker
  cp -f /etc/XMPlus/docker-compose.yml /etc/Docker/docker-compose.yml

  echo
  echo ">>> (5) Geo Data"
  wget -O /etc/XMPlus/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
  wget -O /etc/XMPlus/geoip.dat   https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
  wget -O /etc/XMPlus/iran.dat    https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat

  echo
  echo ">>> (6) WARP Script (interactive)"
  wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
  bash menu.sh || true

  echo
  echo ">>> (7) Duplicate XMPlus dirs to 01/02"
  cp -rf /etc/XMPlus /etc/XMPlus01
  cp -rf /etc/XMPlus /etc/XMPlus02

  echo
  echo ">>> (8) rathole installer"
  bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/Musixal/rathole-tunnel/main/rathole_v2.sh) || true

  echo
  echo ">>> (9) pingtunnel binary"
  cd /root
  wget -O pingtunnel_linux_amd64.zip https://github.com/esrrhs/pingtunnel/releases/download/2.8/pingtunnel_linux_amd64.zip
  apt install -y unzip || true
  unzip -o pingtunnel_linux_amd64.zip
  cp -f pingtunnel /usr/local/bin/

  echo
  read -rp "Set up pingtunnel as a systemd service? (y/n): " setup_pt
  if [[ "${setup_pt,,}" == "y" ]]; then
    cat >/etc/systemd/system/pingtunnel.service <<'EOF'
[Unit]
Description=Pingtunnel Server
After=network.target

[Service]
ExecStart=/usr/local/bin/pingtunnel \
  -type server \
  -nolog 1 \
  -noprint 1 \
  -loglevel none \
  -maxconn 500 \
  -maxprt 200 \
  -maxprb 5000
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.icmp_ratelimit=0; sysctl -w net.ipv4.icmp_ratemask=0'
Restart=on-failure
RestartSec=3
User=root
WorkingDirectory=/usr/local/bin
StandardOutput=journal
StandardError=journal
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now pingtunnel.service
    echo "✅ pingtunnel service installed and started."
  else
    echo "ℹ️ Skipped pingtunnel systemd setup."
  fi

  echo
  echo "🎉 All steps done successfully!"
}

# =========================
# Main Menu
# =========================
main_menu() {
  require_root
  while true; do
    echo
    echo "What do you want to run?"
    echo "1) server_setup.sh (original flow)"
    echo "2) Cron tasks"
    echo "3) Exit"
    read -rp "Choose an option [1-3]: " choice
    case "$choice" in
      1) server_setup_main ; press_enter ;;
      2) cron_menu ;;
      3) exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

main_menu
