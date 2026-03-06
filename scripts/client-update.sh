#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/client-install.sh"

usage() {
  cat <<'EOF'
One-click updater for BinguinDesk client.

Usage:
  sudo ./scripts/client-update.sh [same options as client-install.sh]

Examples:
  sudo ./scripts/client-update.sh --deb-file ./BinguinDesk-1.0.1.deb
  sudo ./scripts/client-update.sh --deb-url https://example.com/BinguinDesk-1.0.1.deb \
    --id-server desk.company.com --key '<pubkey>'
  sudo ./scripts/client-update.sh --deb-file ./BinguinDesk-1.0.1.deb \
    --permanent-password-file /root/.binguindesk/password.txt
EOF
}

log() { echo "[$SCRIPT_NAME] $*"; }
die() { echo "[$SCRIPT_NAME] ERROR: $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

get_version() {
  dpkg-query -W -f='${Version}\n' rustdesk 2>/dev/null || echo "not-installed"
}

main() {
  require_root

  if [[ ! -x "${INSTALL_SCRIPT}" ]]; then
    die "Install script not found or not executable: ${INSTALL_SCRIPT}"
  fi

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local before after
  before="$(get_version)"
  log "Current version: ${before}"

  "${INSTALL_SCRIPT}" "$@"

  after="$(get_version)"
  log "Updated version: ${after}"
  if [[ "${before}" == "${after}" ]]; then
    log "Version unchanged. Package may already be up to date."
  else
    log "Update completed."
  fi
}

main "$@"
