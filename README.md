# ServerSetup

A comprehensive server setup script for configuring Linux servers with Docker, XMPlus, WARP, Rathole, Pingtunnel, and other tools.

## 🚀 Quick Install

Copy and paste this command to run the script directly on your server:

```bash
curl -fsSL https://raw.githubusercontent.com/letmefind/ServerSetup/main/server_setup.sh | sudo bash
```

## Features

- ✅ **Interactive Installation**: Choose which components to install
- ✅ **Docker Compose v2**: Uses modern `docker compose` command (plugin version)
- ✅ **Offline Installation**: Create packages for servers without internet access
- ✅ **Modular Design**: Install only what you need

## Requirements

- Linux server (Ubuntu/Debian recommended)
- Root/sudo access
- Internet connection (unless using offline package)

## Quick Start

### One-Line Installation (Recommended)

Run the script directly from GitHub without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/letmefind/ServerSetup/main/server_setup.sh | sudo bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/letmefind/ServerSetup/main/server_setup.sh | sudo bash
```

**That's it!** The script will download and run, prompting you to select which components to install.

### Clone and Run on Server

Alternatively, you can clone the repository first:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/letmefind/ServerSetup.git
   cd ServerSetup
   ```

2. **Make the script executable (if needed):**
   ```bash
   chmod +x server_setup.sh
   ```

3. **Run the setup script:**
   ```bash
   sudo bash server_setup.sh
   ```

4. **Follow the interactive prompts** to select which components to install.

Or clone and run in one command:

```bash
git clone https://github.com/letmefind/ServerSetup.git && cd ServerSetup && sudo bash server_setup.sh
```

## Usage

### Interactive Installation

Run the script and follow the prompts:

```bash
sudo bash server_setup.sh
```

The script will ask you for each component:
1. SSH key setup
2. Hostname change
3. Docker & Docker Compose
4. System Optimizations (BBR, TCP tuning, Ulimit, Network queues)
5. XMPlus
6. Geo Data files
7. WARP Script
8. XMPlus duplicates (01/02)
9. Rathole installer
10. Pingtunnel binary

### Creating an Offline Package

To create an offline installation package (for servers without internet):

```bash
sudo bash server_setup.sh --create-package
```

Or use the menu:
```bash
sudo bash server_setup.sh
# Choose option 2: Create offline package
```

This will download all dependencies to `/tmp/server-setup-offline-install/`.

**To create a tarball:**
```bash
cd /tmp
tar -czf server-setup-offline.tar.gz server-setup-offline-install/
```

### Installing from Offline Package

1. Copy the offline package to your server:
   ```bash
   scp server-setup-offline.tar.gz user@server:/root/
   ```

2. Extract the package:
   ```bash
   ssh user@server
   cd /root
   tar -xzf server-setup-offline.tar.gz
   ```

3. Run the installation:
   ```bash
   cd server-setup-offline-install/install-scripts
   sudo bash server_setup.sh --offline /root/server-setup-offline-install
   ```

## What Gets Installed

### 1. SSH Key Setup
Adds your public SSH key to `~/.ssh/authorized_keys` for secure access.

### 2. Hostname Change
Optionally change the server hostname.

### 3. Docker & Docker Compose
- Installs Docker Engine
- Installs Docker Compose plugin (v2) - uses `docker compose` command
- Enables and starts Docker service

### 4. System Optimizations
Applies system-level optimizations for better performance:
- **BBR TCP Congestion Control**: Enables BBR for improved network throughput
- **TCP/UDP Buffer Tuning**: Optimizes buffer sizes for 2GB RAM servers
- **Connection Queue Optimization**: Increases backlog queues to prevent connection drops
- **File Descriptor Limits**: Increases ulimit (nofile) to 65535
- **Network Interface Queues**: Sets txqueuelen to 5000 for better packet handling
- **Port Range Optimization**: Configures local port range and TCP timeouts
- Creates systemd service to persist network optimizations across reboots

**Note**: Some settings require a reboot to take full effect.

### 5. XMPlus
- Downloads XMPlus Docker configuration
- Sets up configuration files:
  - `config.yml`
  - `route.json` (from repository)
  - `outbound.json`
- Creates optimized `docker-compose.yml` with:
  - Network mode: host (reduces Docker network overhead)
  - Ulimit settings: 65535 file descriptors
  - Log rotation: Max 10MB per file, 3 files max
  - Auto-restart: always
- Saves docker-compose.yml to `/etc/Docker/` and `/etc/XMPlus/`

### 6. Geo Data Files
Downloads geo data files:
- `geosite.dat` - Domain list
- `geoip.dat` - IP geolocation
- `iran.dat` - Iran-specific domains

### 7. WARP Script
Downloads and runs the WARP configuration script.

### 8. XMPlus Duplicates
Creates duplicate XMPlus directories (`/etc/XMPlus01` and `/etc/XMPlus02`).

### 9. Rathole
Installs Rathole tunnel service.

### 10. Pingtunnel
- Downloads Pingtunnel binary
- Optionally sets up as systemd service

## Cron Jobs

The script includes a cron menu for managing scheduled tasks:

```bash
sudo bash server_setup.sh
# Choose option 3: Cron tasks
```

### Available Cron Tasks:
- Install hourly restart for rathole*.service
- Remove cron job
- Show root crontab

## Docker Compose Usage

The script now uses Docker Compose v2 (plugin version). Use it like this:

```bash
docker compose up -d
docker compose down
docker compose ps
```

**Note**: The old `docker-compose` command is no longer used. The new version is `docker compose` (with a space).

## Offline Package Contents

The offline package includes:
- All installation scripts
- Docker installation script
- XMPlus Docker ZIP
- Route configuration files
- Geo data files
- WARP script
- Rathole installer
- Pingtunnel binary
- Docker Compose plugin binary

## Configuration

### SSH Public Key
Edit the `PUBKEY` variable at the top of `server_setup.sh` to use your own SSH key.

### XMPlus Configuration
The XMPlus configuration is set up in `/etc/XMPlus/config.yml`. You may need to customize:
- API host and key
- Node ID
- Certificate configuration

## Troubleshooting

### Docker Compose Not Found
If `docker compose` command doesn't work:
1. Make sure Docker is installed
2. Check if the plugin is installed: `ls /usr/local/lib/docker/cli-plugins/`
3. Re-run the Docker installation step

### Offline Installation Fails
- Ensure the offline package directory exists
- Check file permissions
- Verify all files were downloaded correctly

### Permission Denied
Make sure you're running the script with sudo:
```bash
sudo bash server_setup.sh
```

## License

This script is provided as-is for server setup purposes.

## Contributing

Feel free to submit issues or pull requests to improve this script.
