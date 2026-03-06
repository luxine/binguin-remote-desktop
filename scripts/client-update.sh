#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/client-install.sh"

usage() {
  cat <<'EOF'
One-click updater for BinguinDesk client.
Default behavior: full uninstall old package first, then install new package.

Usage:
  sudo ./scripts/client-update.sh [options]

Options:
  --no-uninstall            Skip full uninstall, install directly
  --keep-snap-flatpak       Do not remove legacy snap/flatpak package
  --keep-apt-autoremove     Do not run apt autoremove after purge
  -h, --help                Show help

Install options (passed through to client-install.sh):
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
  --no-watchdog
  --no-hardening

Examples:
  sudo ./scripts/client-update.sh --deb-file ./BinguinDesk-1.0.1.deb
  sudo ./scripts/client-update.sh --no-uninstall --deb-file ./BinguinDesk-1.0.1.deb
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

is_pkg_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}\n' "${pkg}" 2>/dev/null | grep -q "^install ok installed$"
}

purge_apt_pkgs() {
  local pkgs=()
  local pkg
  for pkg in rustdesk binguindesk; do
    if is_pkg_installed "${pkg}"; then
      pkgs+=("${pkg}")
    fi
  done

  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    log "No legacy apt package found."
    return 0
  fi

  log "Purging apt packages: ${pkgs[*]}"
  apt-get purge -y "${pkgs[@]}"
}

purge_snap_pkg() {
  local pkg
  local removed=0
  command -v snap >/dev/null 2>&1 || return 0
  for pkg in rustdesk binguindesk; do
    if snap list "${pkg}" >/dev/null 2>&1; then
      log "Removing snap package: ${pkg}"
      snap remove "${pkg}" || warn "Failed to remove snap package: ${pkg}"
      removed=1
    fi
  done
  if [[ "${removed}" -eq 0 ]]; then
    log "No legacy snap package found."
  fi
}

purge_flatpak_pkg() {
  local app
  local removed=0
  command -v flatpak >/dev/null 2>&1 || return 0
  for app in com.rustdesk.RustDesk com.binguinpos.binguindesk; do
    if flatpak info "${app}" >/dev/null 2>&1; then
      log "Removing flatpak package: ${app}"
      flatpak uninstall -y "${app}" || warn "Failed to remove flatpak package: ${app}"
      removed=1
    fi
  done
  if [[ "${removed}" -eq 0 ]]; then
    log "No legacy flatpak package found."
  fi
}

full_uninstall_old() {
  local keep_snap_flatpak="$1"
  local keep_apt_autoremove="$2"

  log "Step A: full uninstall old client package(s)..."
  purge_apt_pkgs
  if [[ "${keep_apt_autoremove}" != "1" ]]; then
    apt-get autoremove --purge -y
  fi

  if [[ "${keep_snap_flatpak}" != "1" ]]; then
    purge_snap_pkg
    purge_flatpak_pkg
  else
    log "Skip removing snap/flatpak packages."
  fi
}

warn() { echo "[$SCRIPT_NAME] WARN: $*" >&2; }

get_version() {
  dpkg-query -W -f='${Version}\n' rustdesk 2>/dev/null || echo "not-installed"
}

main() {
  require_root

  if [[ ! -x "${INSTALL_SCRIPT}" ]]; then
    die "Install script not found or not executable: ${INSTALL_SCRIPT}"
  fi

  local do_uninstall="1"
  local keep_snap_flatpak="0"
  local keep_apt_autoremove="0"
  local install_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-uninstall)
        do_uninstall="0"; shift ;;
      --keep-snap-flatpak)
        keep_snap_flatpak="1"; shift ;;
      --keep-apt-autoremove)
        keep_apt_autoremove="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        install_args+=("$1")
        shift ;;
    esac
  done

  local before after
  before="$(get_version)"
  log "Current version: ${before}"

  if [[ "${do_uninstall}" == "1" ]]; then
    full_uninstall_old "${keep_snap_flatpak}" "${keep_apt_autoremove}"
  else
    log "Skip full uninstall."
  fi

  log "Step B: install new package..."
  "${INSTALL_SCRIPT}" "${install_args[@]}"

  after="$(get_version)"
  log "Updated version: ${after}"
  if [[ "${before}" == "${after}" ]]; then
    log "Version unchanged. Package may already be up to date."
  else
    log "Update completed."
  fi
}

main "$@"
