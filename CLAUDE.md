# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a one-click deployment toolkit for running Mihomo (Clash core fork) proxy service in containerized or remote Linux environments. It automates proxy setup, configuration management, and provides convenience functions for managing VPN/proxy services, particularly optimized for AutoDL and cloud server environments.

## Common Commands

### Service Management
```bash
# Initial setup (must use source to inject shell functions)
source ./start.sh

# Restart service (reload configuration)
source ./restart.sh
# or use injected function:
clash_on

# Stop service
source ./shutdown.sh
# or use injected function:
clash_off

# Complete removal (with double confirmation)
shutdown_system
```

### Diagnostics and Testing
```bash
# Run comprehensive health check
health_check
# or directly:
source ./health_check.sh

# Test node latency (concurrent testing, top 10 fastest)
clash_test
# or with options:
bash tools/clash_test.sh -t 3000 -n 5 -f "香港|HK"

# View logs
tail -f logs/mihomo.log

# Check listening ports
lsof -i -P -n | grep LISTEN | grep -E ':9090|:789[0-9]'
```

### Proxy Control (Injected Shell Functions)
```bash
proxy_on      # Enable HTTP/HTTPS proxy environment variables
proxy_off     # Disable proxy environment variables
```

### Configuration
```bash
# Setup environment variables
cp .env.example .env
vim .env      # Set CLASH_URL and CLASH_SECRET

# Manual config placement (recommended over subscription download)
# Copy your local Clash config.yaml to conf/config.yaml
```

## Architecture Overview

### Core Scripts and Their Responsibilities

**start.sh** (925 lines, main entry point):
- Detects CPU architecture (x86_64, aarch64, armv7) and downloads appropriate binaries
- Downloads Mihomo binary and yq tool with multi-mirror fallback
- Validates or downloads configuration from subscription URL
- Starts Mihomo service with nohup/disown for background execution
- Injects shell functions into ~/.bashrc or ~/.zshrc
- Performs network connectivity testing

**restart.sh**:
- Gracefully stops Mihomo processes (pkill -f mihomo)
- Clears logs/mihomo.log to prevent bloat
- Restarts service with fresh configuration

**shutdown.sh**:
- Terminates Mihomo processes
- Removes configuration files
- Clears injected shell functions from shell rc files
- Optional complete directory removal with confirmation

**health_check.sh**:
- Verifies process status, port listening (7890, 9090)
- Tests network connectivity (direct and proxied)
- Validates configuration files
- Checks for sensitive files in git tracking
- Analyzes logs for errors

**converter.sh** (568 lines):
- Parses subscription URLs and converts proxy protocols to Clash format
- Supports: Shadowsocks (SS), ShadowsocksR (SSR), VMess, VLESS
- Handles base64 decoding and duplicate name resolution
- Generates proxy groups and routing rules

**tools/clash_test.sh**:
- Concurrent latency testing for all proxy nodes
- Supports filtering/exclusion by regex patterns
- Outputs top N lowest-latency nodes
- Uses Mihomo API (port 9090) for node discovery

### Directory Structure

```
bin/                    # Pre-compiled binaries (mihomo, yq)
conf/                   # Runtime configuration
  ├── config.yaml       # Main Clash configuration (auto-downloaded or manual)
  ├── template.yaml     # Optional merge template (if ENABLE_TEMPLATE_MERGE=1)
  ├── geoip.metadb      # GeoIP routing database
  ├── geosite.dat       # GeoSite routing rules
  └── dashboard/        # YACD web UI
logs/                   # Service logs (auto-rotated on restart)
tools/                  # Utility scripts (latency testing)
```

### Key Configuration Points

**Environment Variables (.env)**:
- `CLASH_URL`: Subscription URL for auto-downloading config
- `CLASH_SECRET`: Dashboard authentication password (auto-generated if empty)
- `ENABLE_TEMPLATE_MERGE`: Set to 1 to merge conf/template.yaml with config.yaml

**Network Ports**:
- 7890: Mixed proxy port (HTTP/SOCKS5)
- 9090: Dashboard/API port
- 6006: External controller (configurable in config.yaml)

**Configuration Priority**:
1. Existing `conf/config.yaml` (if valid)
2. Download from `CLASH_URL` in .env
3. Manual placement of config.yaml

### Important Implementation Details

**Shell Function Injection**:
- `start.sh` appends functions to ~/.bashrc or ~/.zshrc between markers
- Functions are shell-agnostic (works with both Bash and Zsh)
- Markers: `# >>> clash initialize >>>` and `# <<< clash initialize <<<`

**Binary Management**:
- Auto-detects architecture and downloads from GitHub releases
- Falls back to multiple mirror sites (ghproxy.com, ghps.cc, gh-proxy.com)
- Validates binaries with chmod +x before execution

**Process Management**:
- Uses `nohup` and `disown` for background service execution
- Process cleanup via `pkill -f mihomo` (not PID files)
- Logs redirected to logs/mihomo.log

**Configuration Validation**:
- YAML syntax validation using yq
- Checks for required fields (proxies, proxy-groups, rules)
- Automatic template merging if ENABLE_TEMPLATE_MERGE=1

### Testing and Debugging

**Network Connectivity Tests**:
```bash
# Direct connection test
curl -L google.com

# Proxied connection test (after proxy_on)
curl -L google.com
```

**Common Issues**:
- Port conflicts: Check if 7890/9090 are already in use
- Subscription download failures: Manually place config.yaml in conf/
- Functions not available: Re-source the shell rc file or open new shell session
- Binary download failures: Check network or manually download from GitHub releases

### Proxy Protocol Conversion

The `converter.sh` script handles multiple proxy protocol formats:
- **SS**: `ss://base64(method:password@server:port)`
- **SSR**: `ssr://base64(server:port:protocol:method:obfs:base64(password))`
- **VMess**: JSON format with base64 encoding
- **VLESS**: `vless://uuid@server:port?params`

Conversion outputs standard Clash YAML format with proper cipher/transport settings.

## Development Notes

- All scripts are written in Bash and should be POSIX-compatible where possible
- Use `source` when running scripts that modify shell environment (start.sh, restart.sh)
- Configuration changes require service restart via `clash_on` or `source ./restart.sh`
- Dashboard access: `http://<server-ip>:9090/ui` (use CLASH_SECRET for authentication)
- The project name mentions "container" but actually runs directly on host (no Docker/Podman)
