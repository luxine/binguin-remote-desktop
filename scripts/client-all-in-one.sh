#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/client-install.sh"
CONFIG_SCRIPT="${SCRIPT_DIR}/ubuntu24-best-config.sh"

usage() {
  cat <<'EOF'
All-in-one script: install/update client + apply Ubuntu 24.04 best config.

Usage:
  sudo ./scripts/client-all-in-one.sh \
    --deb-file ./BinguinDesk-1.0.0.deb \
    --id-server desk.company.com \
    --key '<pubkey>' \
    --autologin-user <username>

Install options:
  --deb-file <path>
  --deb-url <url>
  --id-server <host[:port]>
  --relay-server <host[:port]>
  --api-server <url>
  --key <pubkey>
  --permanent-password <v>
  --permanent-password-file <path>
  --no-unattended-password
  --skip-apt-update

Config options:
  --autologin-user <user>
  --skip-autologin
  --skip-gsettings
  --skip-logind-restart

Other:
  -h, --help
EOF
}

log() { echo "[$SCRIPT_NAME] $*"; }
die() { echo "[$SCRIPT_NAME] ERROR: $*" >&2; exit 1; }

main() {
  [[ -x "${INSTALL_SCRIPT}" ]] || die "Missing install script: ${INSTALL_SCRIPT}"
  [[ -x "${CONFIG_SCRIPT}" ]] || die "Missing config script: ${CONFIG_SCRIPT}"

  local install_args=()
  local config_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deb-file|--deb-url|--id-server|--relay-server|--api-server|--key|--permanent-password|--permanent-password-file)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        install_args+=("$1" "$2")
        shift 2
        ;;
      --skip-apt-update|--no-watchdog|--no-hardening|--no-unattended-password)
        install_args+=("$1")
        shift
        ;;
      --autologin-user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        config_args+=("$1" "$2")
        shift 2
        ;;
      --skip-autologin|--skip-gsettings|--skip-logind-restart)
        config_args+=("$1")
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  log "Step 1/2: install or update client package..."
  "${INSTALL_SCRIPT}" "${install_args[@]}"

  log "Step 2/2: apply Ubuntu 24.04 best-practice config..."
  "${CONFIG_SCRIPT}" "${config_args[@]}"

  log "All done. Reboot is recommended."
}

main "$@"
