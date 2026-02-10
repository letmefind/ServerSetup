#!/usr/bin/env bash
set -euo pipefail

# Ensure we can read from terminal when piped
# Redirect /dev/tty to stdin if we're being piped and /dev/tty is available
if [[ ! -t 0 ]] && [[ -r /dev/tty ]] 2>/dev/null; then
  exec < /dev/tty
fi

# =========================
# Config
# =========================
PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD1GDXQ5Xgx4RAKC+wV//OhU5tYFW30TKtVd7+xT8qMKCAR/tXDZ8gP9p/V+6vrPwxyn1ImzDhUCA4NSORTvKe+/XjGKIbte11H05LsRmG9y9oOeMP/aesIgxYkUt9Nuu1CohIsbTGMxHfEUTM4MRfAKE3poxkoshPBv8Lt8o4RKDf91y+ih4rduPmJ++9xV031LXC+EC+bKfD4O+kaGy9WayRMWBrCtCcHhWPsXgQARQs5fjVV1LN4bmaAlVRxzJwBM1dCTqv0s41Y0bjqlzmxySjZDhFUyRnV1aPCFGhgVfoVDRH7s0YfuU/iiH/d+qkLHV4AmUfVV2xBjkncC4JR0i8Q1Gzpfd+JXxUBa/mSqg8E6NK2vXgycgiSy0YRzW5e/T/jlBNGb4RaDPHKVOae5VEnB4XTfPlO1hP/o8dWk2H5YLHrzMgIwjpc0yuhKp6GgNWJQjyMfajy7fPmHtverdP/shh9uon/XK1ylqrdjDuIrWx1nn1FWyKUBJmKVps= arash@Arashs-MacBook-Pro.local"

OFFLINE_PACKAGE_DIR="/tmp/server-setup-offline-install"
OFFLINE_INSTALL_DIR="/root/server-setup-offline-install"

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

# Helper function to read from terminal when piped
# When script is piped (curl | bash), stdin is the pipe, so we must read from /dev/tty
safe_read() {
  local prompt="$1"
  local var_name="$2"
  
  # Always try /dev/tty first (works when piped and when run normally)
  if [[ -r /dev/tty ]] 2>/dev/null; then
    read -rp "$prompt" "$var_name" </dev/tty 2>/dev/null || read -rp "$prompt" "$var_name"
  else
    # Fallback to stdin (only works when not piped)
    read -rp "$prompt" "$var_name"
  fi
}

press_enter() { 
  if [[ -r /dev/tty ]] 2>/dev/null; then
    read -rp "Press Enter to continue..." </dev/tty 2>/dev/null || read -rp "Press Enter to continue..."
  else
    read -rp "Press Enter to continue..."
  fi
}
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local response
  while true; do
    safe_read "$prompt (y/n) [default: $default]: " response
    response="${response,,}"
    [[ -z "$response" ]] && response="$default"
    if [[ "$response" == "y" ]] || [[ "$response" == "yes" ]]; then
      return 0
    elif [[ "$response" == "n" ]] || [[ "$response" == "no" ]]; then
      return 1
    else
      echo "Please enter 'y' or 'n'"
    fi
  done
}

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
    safe_read "Choose an option [1-4]: " c
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
# Offline Package Creation
# =========================
create_offline_package() {
  require_root
  echo ">>> Creating offline installation package..."
  
  echo "This will download all dependencies for offline installation."
  
  echo
  
  mkdir -p "$OFFLINE_PACKAGE_DIR"
  mkdir -p "$OFFLINE_PACKAGE_DIR/binaries"
  mkdir -p "$OFFLINE_PACKAGE_DIR/scripts"
  mkdir -p "$OFFLINE_PACKAGE_DIR/data"
  mkdir -p "$OFFLINE_PACKAGE_DIR/configs"
  mkdir -p "$OFFLINE_PACKAGE_DIR/packages"
  mkdir -p "$OFFLINE_PACKAGE_DIR/docker"
  mkdir -p "$OFFLINE_PACKAGE_DIR/geo"
  mkdir -p "$OFFLINE_PACKAGE_DIR/warp"
  mkdir -p "$OFFLINE_PACKAGE_DIR/rathole"
  mkdir -p "$OFFLINE_PACKAGE_DIR/pingtunnel"
  mkdir -p "$OFFLINE_PACKAGE_DIR/xmplus"
  mkdir -p "$OFFLINE_PACKAGE_DIR/route"
  mkdir -p "$OFFLINE_PACKAGE_DIR/docker-compose"
  mkdir -p "$OFFLINE_PACKAGE_DIR/install-scripts"
  
  # Save this script
  cp "$0" "$OFFLINE_PACKAGE_DIR/install-scripts/server_setup.sh"
  chmod +x "$OFFLINE_PACKAGE_DIR/install-scripts/server_setup.sh"
  
  # Save route rules
  if [[ -f "$(dirname "$0")/route_rules.json" ]]; then
    cp "$(dirname "$0")/route_rules.json" "$OFFLINE_PACKAGE_DIR/route/route_rules.json"
  fi
  
  echo ">>> Downloading Docker installation script..."
  curl -fsSL https://get.docker.com -o "$OFFLINE_PACKAGE_DIR/scripts/get-docker.sh" || echo "⚠️ Failed to download Docker installer"
  
  echo ">>> Downloading XMPlus Docker ZIP..."
  wget --no-check-certificate -O "$OFFLINE_PACKAGE_DIR/xmplus/docker.zip" https://raw.githubusercontent.com/XMPlusDev/XMPlus/scripts/docker.zip || echo "⚠️ Failed to download XMPlus"
  
  echo ">>> Downloading route.json..."
  wget -O "$OFFLINE_PACKAGE_DIR/route/route.json" https://raw.githubusercontent.com/letmefind/ServerSetup/main/route_rules.json || echo "⚠️ Failed to download route.json"
  
  echo ">>> Downloading Geo Data files..."
  wget -O "$OFFLINE_PACKAGE_DIR/geo/geosite.dat" https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat || echo "⚠️ Failed to download geosite.dat"
  wget -O "$OFFLINE_PACKAGE_DIR/geo/geoip.dat" https://github.com/v2fly/geoip/releases/latest/download/geoip.dat || echo "⚠️ Failed to download geoip.dat"
  wget -O "$OFFLINE_PACKAGE_DIR/geo/iran.dat" https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat || echo "⚠️ Failed to download iran.dat"
  
  echo ">>> Downloading WARP script..."
  wget -N -O "$OFFLINE_PACKAGE_DIR/warp/menu.sh" https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh || echo "⚠️ Failed to download WARP script"
  
  echo ">>> Downloading rathole installer..."
  curl -Ls --ipv4 https://raw.githubusercontent.com/Musixal/rathole-tunnel/main/rathole_v2.sh -o "$OFFLINE_PACKAGE_DIR/rathole/rathole_v2.sh" || echo "⚠️ Failed to download rathole installer"
  
  echo ">>> Downloading pingtunnel binary..."
  wget -O "$OFFLINE_PACKAGE_DIR/pingtunnel/pingtunnel_linux_amd64.zip" https://github.com/esrrhs/pingtunnel/releases/download/2.8/pingtunnel_linux_amd64.zip || echo "⚠️ Failed to download pingtunnel"
  
  echo ">>> Downloading Docker Compose plugin..."
  # Docker Compose plugin (v2) - we'll download the binary
  local arch="$(uname -m)"
  local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  wget -O "$OFFLINE_PACKAGE_DIR/docker-compose/docker-compose-${os}-${arch}" \
    "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-${os}-${arch}" || \
    wget -O "$OFFLINE_PACKAGE_DIR/docker-compose/docker-compose-${os}-${arch}" \
    "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-${os}-${arch}" || echo "⚠️ Failed to download docker-compose plugin"
  
  # Create installation instructions
  cat > "$OFFLINE_PACKAGE_DIR/README-OFFLINE.txt" <<'EOF'
# Offline Installation Package
# =========================
This package contains all dependencies needed for offline server setup.
  
## Installation Steps:
1. Copy this entire directory to the target server
2. Run: bash install-scripts/server_setup.sh --offline
3. Follow the interactive prompts
  
## Package Contents:
- scripts/: Installation scripts
- binaries/: Binary files
- data/: Data files
- configs/: Configuration files
- packages/: Package files
- docker/: Docker-related files
- geo/: GeoIP/Geo data files
- warp/: WARP script
- rathole/: Rathole installer
- pingtunnel/: Pingtunnel binary
- xmplus/: XMPlus files
- route/: Route configuration
- docker-compose/: Docker Compose plugin
- install-scripts/: Installation scripts
EOF
  
  echo
  echo "✅ Offline package created at: $OFFLINE_PACKAGE_DIR"
  echo "   Package size: $(du -sh "$OFFLINE_PACKAGE_DIR" | awk '{print $1}')"
  echo
  echo "To create a tarball:"
  echo "  tar -czf server-setup-offline.tar.gz -C $(dirname "$OFFLINE_PACKAGE_DIR") $(basename "$OFFLINE_PACKAGE_DIR")"
}

# =========================
# Offline Installation Helper Functions
# =========================
use_offline() {
  [[ -n "${OFFLINE_MODE:-}" ]] && [[ "${OFFLINE_MODE:-}" == "yes" ]]
}

get_offline_file() {
  local file_path="$1"
  local dest_path="${2:-$file_path}"
  local source_path="$OFFLINE_INSTALL_DIR/$file_path"
  
  if use_offline && [[ -f "$source_path" ]]; then
    cp "$source_path" "$dest_path"
    return 0
  fi
  return 1
}

download_or_offline() {
  local url="$1"
  local dest="$2"
  local offline_path="$3"
  
  if use_offline && [[ -n "$offline_path" ]] && [[ -f "$OFFLINE_INSTALL_DIR/$offline_path" ]]; then
    echo "   Using offline file: $offline_path"
    cp "$OFFLINE_INSTALL_DIR/$offline_path" "$dest"
    return 0
  fi
  
  # Try to download
  if [[ "$url" == *"wget"* ]]; then
    wget "$url" -O "$dest" || return 1
  else
    curl "$url" -o "$dest" || return 1
  fi
  return 0
}

# =========================
# Main Installation Functions
# =========================
install_ssh_key() {
  if ! ask_yes_no ">>> (1) SSH key setup - Install?"; then
    echo "ℹ️ Skipped SSH key setup."
    return 0
  fi
  
  require_root
  echo ">>> Setting up SSH key..."
  mkdir -p ~/.ssh
  touch ~/.ssh/authorized_keys
  if ! grep -qF "$PUBKEY" ~/.ssh/authorized_keys; then
    echo "$PUBKEY" >> ~/.ssh/authorized_keys
  fi
  chmod 600 ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  echo "✅ Public key added."
}

install_hostname() {
  if ! ask_yes_no ">>> (2) Hostname change - Configure?"; then
    echo "ℹ️ Skipped hostname change."
    return 0
  fi
  
  require_root
  echo
  safe_read "Enter new hostname: " new_hostname
  if [[ -n "$new_hostname" ]]; then
    hostnamectl set-hostname "$new_hostname"
    echo "✅ Hostname changed to: $new_hostname"
  fi
}

install_docker() {
  if ! ask_yes_no ">>> (3) Docker & Docker Compose - Install?"; then
    echo "ℹ️ Skipped Docker installation."
    return 0
  fi
  
  require_root
  echo ">>> Installing Docker..."
  
  if ! cmd_exists docker; then
    if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/scripts/get-docker.sh" ]]; then
      echo "   Using offline Docker installer..."
      bash "$OFFLINE_INSTALL_DIR/scripts/get-docker.sh"
    else
    curl -fsSL https://get.docker.com | bash -s docker
    fi
  else
    echo "   Docker already installed."
  fi
  
  # Install Docker Compose plugin (v2)
  echo ">>> Installing Docker Compose plugin..."
  if ! docker compose version >/dev/null 2>&1; then
    local arch="$(uname -m)"
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local compose_binary="/usr/local/lib/docker/cli-plugins/docker-compose"
    mkdir -p "$(dirname "$compose_binary")"
    
    if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/docker-compose/docker-compose-${os}-${arch}" ]]; then
      echo "   Using offline Docker Compose plugin..."
      cp "$OFFLINE_INSTALL_DIR/docker-compose/docker-compose-${os}-${arch}" "$compose_binary"
      chmod +x "$compose_binary"
    else
      echo "   Downloading Docker Compose plugin..."
      curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-${os}-${arch}" \
        -o "$compose_binary" || \
      curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-${os}-${arch}" \
        -o "$compose_binary"
      chmod +x "$compose_binary"
    fi
    echo "✅ Docker Compose plugin installed."
  else
    echo "   Docker Compose already installed."
  fi
  
  # Enable/start docker
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker  >/dev/null 2>&1 || true
  service docker start     >/dev/null 2>&1 || true
  chkconfig docker on      >/dev/null 2>&1 || true
  echo "✅ Docker installed and started."
}

install_xmplus() {
  if ! ask_yes_no ">>> (4) XMPlus - Install?"; then
    echo "ℹ️ Skipped XMPlus installation."
    return 0
  fi
  
  require_root
  echo ">>> Installing XMPlus..."
  mkdir -p /etc/XMPlus
  cd /etc/XMPlus
  
  if cmd_exists apt; then
    apt update -y
    apt install -y unzip wget
  fi

  if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/xmplus/docker.zip" ]]; then
    echo "   Using offline XMPlus package..."
    cp "$OFFLINE_INSTALL_DIR/xmplus/docker.zip" /etc/XMPlus/
  else
  wget --no-check-certificate -O docker.zip https://raw.githubusercontent.com/XMPlusDev/XMPlus/scripts/docker.zip
  fi
  
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

  # 4.2 route.json
  rm -f /etc/XMPlus/route.json
  if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/route/route.json" ]]; then
    echo "   Using offline route.json..."
    cp "$OFFLINE_INSTALL_DIR/route/route.json" /etc/XMPlus/route.json
  else
  wget -O /etc/XMPlus/route.json https://raw.githubusercontent.com/letmefind/ServerSetup/main/route_rules.json
  fi

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

  # 4.4 docker-compose.yml with optimizations
  mkdir -p /etc/Docker
  cat > /etc/Docker/docker-compose.yml <<EOF
version: '3.8'
services:
  xray-server:
    image: ghcr.io/xmplusdev/xmplus:latest
    restart: always
    network_mode: host
    volumes:
      - /etc/XMPlus:/etc/XMPlus/
    ulimits:
      nofile:
        soft: 65535
        hard: 65535
      nproc: 65535
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
  
  # Also copy to XMPlus directory if it exists
  if [[ -d /etc/XMPlus ]]; then
    cp -f /etc/Docker/docker-compose.yml /etc/XMPlus/docker-compose.yml
  fi
  
  echo "✅ XMPlus installed."
}

install_system_optimizations() {
  if ! ask_yes_no ">>> (3.5) System Optimizations (BBR, TCP tuning, Ulimit) - Apply?"; then
    echo "ℹ️ Skipped system optimizations."
    return 0
  fi
  
  require_root
  echo ">>> Applying system optimizations..."
  
  # 1. Sysctl settings for BBR and TCP optimization
  echo ">>> Configuring sysctl settings..."
  cat >> /etc/sysctl.conf <<'EOF'

# Server Setup Script - System Optimizations
# فعال‌سازی BBR برای TCP
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# افزایش صف‌های انتظار (Backlog) برای جلوگیری از دراپ شدن کانکشن
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192

# مدیریت بافرهای TCP/UDP (بهینه شده برای 2GB رم)
# اعداد زیر (16MB max) کافی هستند و جلوی پر شدن رم را می‌گیرند
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_mem = 8192 262144 536870912

# بازیافت سریع پورت‌ها و فایل‌ها
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 1024 65000
fs.file-max = 1000000
EOF
  
  # Apply sysctl settings
  sysctl -p >/dev/null 2>&1 || true
  echo "   ✅ Sysctl settings applied"
  
  # 2. Ulimit settings for file descriptors
  echo ">>> Configuring ulimit settings..."
  if ! grep -qF "* soft nofile 65535" /etc/security/limits.conf; then
    echo "* soft nofile 65535" >> /etc/security/limits.conf
  fi
  if ! grep -qF "* hard nofile 65535" /etc/security/limits.conf; then
    echo "* hard nofile 65535" >> /etc/security/limits.conf
  fi
  echo "   ✅ Ulimit settings configured"
  
  # 3. Network interface queue length (apply to loopback and primary interface)
  echo ">>> Configuring network interface queue lengths..."
  ip link set lo txqueuelen 5000 2>/dev/null || true
  
  # Detect primary network interface
  primary_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
  if [[ -n "$primary_iface" ]]; then
    ip link set "$primary_iface" txqueuelen 5000 2>/dev/null || true
    echo "   ✅ Configured queue length for $primary_iface"
  else
    # Fallback to common interface names
    for iface in eth0 ens3 ens33 enp0s3; do
      if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" txqueuelen 5000 2>/dev/null || true
        echo "   ✅ Configured queue length for $iface"
        break
      fi
    done
  fi
  
  # Create systemd service to apply network settings on boot
  cat > /etc/systemd/system/network-optimization.service <<'EOF'
[Unit]
Description=Network Interface Queue Optimization
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip link set lo txqueuelen 5000; for iface in $(ip route | grep default | awk "{print \$5}" | head -n1); do ip link set $iface txqueuelen 5000 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable network-optimization.service >/dev/null 2>&1 || true
  echo "   ✅ Network optimization service created"
  
  echo "✅ System optimizations applied."
  echo "   Note: Some settings require reboot to take full effect."
}

install_geo_data() {
  if ! ask_yes_no ">>> (5) Geo Data files - Download?"; then
    echo "ℹ️ Skipped Geo Data download."
    return 0
  fi
  
  require_root
  echo ">>> Downloading Geo Data files..."
  
  if use_offline; then
    if [[ -f "$OFFLINE_INSTALL_DIR/geo/geosite.dat" ]]; then
      cp "$OFFLINE_INSTALL_DIR/geo/geosite.dat" /etc/XMPlus/
      echo "   ✅ Copied geosite.dat"
    fi
    if [[ -f "$OFFLINE_INSTALL_DIR/geo/geoip.dat" ]]; then
      cp "$OFFLINE_INSTALL_DIR/geo/geoip.dat" /etc/XMPlus/
      echo "   ✅ Copied geoip.dat"
    fi
    if [[ -f "$OFFLINE_INSTALL_DIR/geo/iran.dat" ]]; then
      cp "$OFFLINE_INSTALL_DIR/geo/iran.dat" /etc/XMPlus/
      echo "   ✅ Copied iran.dat"
    fi
  else
    wget -O /etc/XMPlus/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat || echo "⚠️ Failed to download geosite.dat"
    wget -O /etc/XMPlus/geoip.dat   https://github.com/v2fly/geoip/releases/latest/download/geoip.dat || echo "⚠️ Failed to download geoip.dat"
    wget -O /etc/XMPlus/iran.dat    https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat || echo "⚠️ Failed to download iran.dat"
  fi
  echo "✅ Geo Data files downloaded."
}

install_warp() {
  if ! ask_yes_no ">>> (6) WARP Script - Install?"; then
    echo "ℹ️ Skipped WARP installation."
    return 0
  fi
  
  require_root
  echo ">>> Installing WARP Script..."
  if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/warp/menu.sh" ]]; then
    echo "   Using offline WARP script..."
    bash "$OFFLINE_INSTALL_DIR/warp/menu.sh" || true
  else
  wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
  bash menu.sh || true
  fi
  echo "✅ WARP script executed."
}

install_xmplus_duplicates() {
  if ! ask_yes_no ">>> (7) Duplicate XMPlus dirs to 01/02 - Create?"; then
    echo "ℹ️ Skipped XMPlus duplicates."
    return 0
  fi
  
  require_root
  echo ">>> Creating XMPlus duplicates..."
  cp -rf /etc/XMPlus /etc/XMPlus01
  cp -rf /etc/XMPlus /etc/XMPlus02
  echo "✅ XMPlus directories duplicated."
}

install_rathole() {
  if ! ask_yes_no ">>> (8) Rathole installer - Install?"; then
    echo "ℹ️ Skipped Rathole installation."
    return 0
  fi
  
  require_root
  echo ">>> Installing Rathole..."
  if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/rathole/rathole_v2.sh" ]]; then
    echo "   Using offline Rathole installer..."
    bash "$OFFLINE_INSTALL_DIR/rathole/rathole_v2.sh" || true
  else
  bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/Musixal/rathole-tunnel/main/rathole_v2.sh) || true
  fi
  echo "✅ Rathole installation completed."
}

install_pingtunnel() {
  if ! ask_yes_no ">>> (9) Pingtunnel binary - Install?"; then
    echo "ℹ️ Skipped Pingtunnel installation."
    return 0
  fi
  
  require_root
  echo ">>> Installing Pingtunnel..."
  cd /root
  
  if use_offline && [[ -f "$OFFLINE_INSTALL_DIR/pingtunnel/pingtunnel_linux_amd64.zip" ]]; then
    echo "   Using offline Pingtunnel package..."
    cp "$OFFLINE_INSTALL_DIR/pingtunnel/pingtunnel_linux_amd64.zip" /root/
    unzip -o pingtunnel_linux_amd64.zip
  else
  wget -O pingtunnel_linux_amd64.zip https://github.com/esrrhs/pingtunnel/releases/download/2.8/pingtunnel_linux_amd64.zip
  apt install -y unzip || true
  unzip -o pingtunnel_linux_amd64.zip
  fi
  
  cp -f pingtunnel /usr/local/bin/

  echo
  if ask_yes_no "Set up pingtunnel as a systemd service?"; then
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
}

# =========================
# Main Installation Flow
# =========================
server_setup_main() {
  require_root
  
  # Initialize OFFLINE_MODE if not set
  OFFLINE_MODE="${OFFLINE_MODE:-no}"
  
  # Check for offline mode
  if [[ "${1:-}" == "--offline" ]] || [[ "${OFFLINE_MODE:-}" == "yes" ]]; then
    if [[ -d "$OFFLINE_INSTALL_DIR" ]]; then
      OFFLINE_MODE="yes"
      echo "📦 Offline mode enabled. Using package from: $OFFLINE_INSTALL_DIR"
    else
      echo "⚠️ Offline mode requested but package directory not found: $OFFLINE_INSTALL_DIR"
      echo "   Please extract the offline package to: $OFFLINE_INSTALL_DIR"
      exit 1
    fi
  fi
  
  echo "=========================================="
  echo "Server Setup Script"
  echo "=========================================="
  echo
  
  install_ssh_key
  install_hostname
  install_docker
  install_system_optimizations
  install_xmplus
  install_geo_data
  install_warp
  install_xmplus_duplicates
  install_rathole
  install_pingtunnel
  
  echo
  echo "🎉 All steps completed successfully!"
}

# =========================
# Main Menu
# =========================
main_menu() {
  require_root
  while true; do
    echo
    echo "=========================================="
    echo "Server Setup Menu"
    echo "=========================================="
    echo "1) Run server setup (interactive)"
    echo "2) Create offline package"
    echo "3) Cron tasks"
    echo "4) Exit"
    safe_read "Choose an option [1-4]: " choice
    case "$choice" in
      1) server_setup_main ; press_enter ;;
      2) create_offline_package ; press_enter ;;
      3) cron_menu ;;
      4) exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

# Check for command line arguments
if [[ $# -gt 0 ]]; then
  case "$1" in
    --offline)
      OFFLINE_INSTALL_DIR="${2:-$OFFLINE_INSTALL_DIR}"
      if [[ -z "$OFFLINE_INSTALL_DIR" ]]; then
        echo "Usage: $0 --offline [package-directory]"
        echo "Example: $0 --offline /root/server-setup-offline-install"
        exit 1
      fi
      server_setup_main --offline
      ;;
    --create-package)
      create_offline_package
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--offline [dir] | --create-package]"
      exit 1
      ;;
  esac
else
main_menu
fi
