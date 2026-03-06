#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_ID_SERVER="3.144.200.111"
DEFAULT_SERVER_KEY="nLdVM05GRrC0PCzA1uJFTcuKQ6gitptntaokhFEayb0="
DEFAULT_PERMANENT_PASSWORD="Binguin1001"

usage() {
  cat <<'EOF'
One-click installer for BinguinDesk client on Ubuntu/Debian.

Usage:
  sudo ./scripts/client-install.sh [options]

Options:
  --deb-file <path>         Local .deb file path (BinguinDesk-*.deb / rustdesk-*.deb)
  --deb-url <url>           Download .deb from URL before install
  --id-server <host[:port]> Set custom-rendezvous-server (default: 3.144.200.111)
  --relay-server <host[:port]> Set relay-server
  --api-server <url>        Set api-server
  --key <public-key>        Set server public key (default: built-in value)
  --permanent-password <v>  Set permanent password (default: Binguin1001)
  --permanent-password-file <path> Read permanent password from file
  --no-unattended-password  Do not force unattended password mode
  --skip-apt-update         Skip apt-get update
  --no-watchdog             Do not install watchdog service/timer
  --no-hardening            Do not create systemd drop-in hardening config
  -h, --help                Show help

Examples:
  sudo ./scripts/client-install.sh --deb-file ./BinguinDesk-1.0.0.deb
  sudo ./scripts/client-install.sh --deb-url https://example.com/BinguinDesk-1.0.0.deb \
    --id-server desk.company.com --key '<pubkey>'
  sudo ./scripts/client-install.sh --deb-file ./BinguinDesk-1.0.0.deb \
    --permanent-password-file /root/.binguindesk/password.txt
EOF
}

log() { echo "[$SCRIPT_NAME] $*"; }
warn() { echo "[$SCRIPT_NAME] WARN: $*" >&2; }
die() { echo "[$SCRIPT_NAME] ERROR: $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_watchdog() {
  log "Installing RustDesk watchdog service and timer..."
  install -d -m 0755 /usr/local/sbin
  cat >/usr/local/sbin/rustdesk-watchdog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! systemctl is-enabled rustdesk >/dev/null 2>&1; then
  systemctl enable rustdesk
fi

if ! systemctl is-active rustdesk >/dev/null 2>&1; then
  systemctl restart rustdesk
fi
EOF
  chmod 0755 /usr/local/sbin/rustdesk-watchdog.sh

  cat >/etc/systemd/system/rustdesk-watchdog.service <<'EOF'
[Unit]
Description=RustDesk Watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/sbin/rustdesk-watchdog.sh
EOF

  cat >/etc/systemd/system/rustdesk-watchdog.timer <<'EOF'
[Unit]
Description=Run RustDesk Watchdog periodically

[Timer]
OnBootSec=90s
OnUnitActiveSec=60s
AccuracySec=10s
Unit=rustdesk-watchdog.service

[Install]
WantedBy=timers.target
EOF
}

install_hardening_dropin() {
  log "Writing rustdesk.service hardening drop-in..."
  install -d -m 0755 /etc/systemd/system/rustdesk.service.d
  cat >/etc/systemd/system/rustdesk.service.d/10-binguindesk-hardening.conf <<'EOF'
[Unit]
Wants=network-online.target
After=network-online.target systemd-user-sessions.service
StartLimitIntervalSec=0

[Service]
User=root
Restart=always
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30
KillMode=mixed
LimitNOFILE=100000
OOMScoreAdjust=-1000
Environment="PULSE_LATENCY_MSEC=60"
Environment="PIPEWIRE_LATENCY=1024/48000"

[Install]
WantedBy=multi-user.target
EOF
}

apply_client_option() {
  local key="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    return 0
  fi
  if ! command_exists rustdesk; then
    die "rustdesk command not found after install."
  fi
  log "Setting rustdesk option: ${key}"
  rustdesk --option "${key}" "${value}" || die "Failed to set option '${key}'."
}

set_permanent_password() {
  local password="$1"
  if [[ -z "${password}" ]]; then
    return 0
  fi
  if ! command_exists rustdesk; then
    die "rustdesk command not found after install."
  fi
  log "Setting rustdesk permanent password..."
  rustdesk --password "${password}" >/dev/null || die "Failed to set permanent password."
}

find_default_deb() {
  local candidate
  candidate="$(ls -1t ./*BinguinDesk*.deb ./BinguinDesk-*.deb ./rustdesk-*.deb 2>/dev/null | head -n 1 || true)"
  echo "${candidate}"
}

main() {
  require_root

  local deb_file=""
  local deb_url=""
  local id_server="${DEFAULT_ID_SERVER}"
  local relay_server=""
  local api_server=""
  local server_key="${DEFAULT_SERVER_KEY}"
  local permanent_password="${DEFAULT_PERMANENT_PASSWORD}"
  local permanent_password_file=""
  local unattended_password_mode="1"
  local skip_apt_update="0"
  local no_watchdog="0"
  local no_hardening="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deb-file)
        deb_file="${2:-}"; shift 2 ;;
      --deb-url)
        deb_url="${2:-}"; shift 2 ;;
      --id-server)
        id_server="${2:-}"; shift 2 ;;
      --relay-server)
        relay_server="${2:-}"; shift 2 ;;
      --api-server)
        api_server="${2:-}"; shift 2 ;;
      --key)
        server_key="${2:-}"; shift 2 ;;
      --permanent-password)
        permanent_password="${2:-}"; shift 2 ;;
      --permanent-password-file)
        permanent_password_file="${2:-}"; shift 2 ;;
      --no-unattended-password)
        unattended_password_mode="0"; shift ;;
      --skip-apt-update)
        skip_apt_update="1"; shift ;;
      --no-watchdog)
        no_watchdog="1"; shift ;;
      --no-hardening)
        no_hardening="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown argument: $1" ;;
    esac
  done

  if [[ -n "${permanent_password_file}" ]]; then
    [[ -f "${permanent_password_file}" ]] || die "Password file not found: ${permanent_password_file}"
    permanent_password="$(head -n 1 "${permanent_password_file}" | tr -d '\r\n')"
  fi

  if [[ -n "${deb_url}" ]]; then
    command_exists curl || die "curl not found."
    install -d -m 0755 /tmp/binguindesk
    deb_file="/tmp/binguindesk/client-latest.deb"
    log "Downloading package: ${deb_url}"
    curl -fL "${deb_url}" -o "${deb_file}" || die "Failed to download package."
  fi

  if [[ -z "${deb_file}" ]]; then
    deb_file="$(find_default_deb)"
  fi

  if [[ -z "${deb_file}" ]]; then
    die "No .deb package found. Use --deb-file or --deb-url."
  fi
  if [[ ! -f "${deb_file}" ]]; then
    die "Package not found: ${deb_file}"
  fi

  deb_file="$(readlink -f "${deb_file}")"
  log "Using package: ${deb_file}"

  if [[ "${skip_apt_update}" != "1" ]]; then
    log "Running apt-get update..."
    apt-get update -y
  fi

  log "Installing package..."
  apt-get install -y "${deb_file}"

  if [[ "${no_hardening}" != "1" ]]; then
    install_hardening_dropin
  fi

  if [[ "${no_watchdog}" != "1" ]]; then
    install_watchdog
  fi

  apply_client_option "custom-rendezvous-server" "${id_server}"
  apply_client_option "relay-server" "${relay_server}"
  apply_client_option "api-server" "${api_server}"
  apply_client_option "key" "${server_key}"
  if [[ "${unattended_password_mode}" == "1" ]]; then
    apply_client_option "approve-mode" "password"
    apply_client_option "verification-method" "use-permanent-password"
    set_permanent_password "${permanent_password}"
  fi

  log "Reloading and restarting services..."
  systemctl daemon-reload
  systemctl enable rustdesk
  systemctl restart rustdesk
  if [[ "${no_watchdog}" != "1" ]]; then
    systemctl enable rustdesk-watchdog.timer
    systemctl restart rustdesk-watchdog.timer
  fi

  log "Quick status:"
  systemctl is-enabled rustdesk || true
  systemctl is-active rustdesk || true
  systemctl status rustdesk --no-pager -n 15 || true
  if [[ "${no_watchdog}" != "1" ]]; then
    systemctl is-enabled rustdesk-watchdog.timer || true
    systemctl is-active rustdesk-watchdog.timer || true
  fi

  log "Done."
}

main "$@"
