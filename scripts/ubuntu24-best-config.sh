#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
One-click best-practice configuration for Ubuntu 24.04 controlled endpoint.

What this script does:
  1) Force Ubuntu on Xorg (GDM Wayland disabled)
  2) Enable auto login (optional user parameter)
  3) Disable sleep / suspend / hibernate / screen lock
  4) Strengthen rustdesk systemd resident configuration
  5) Install rustdesk watchdog timer

Usage:
  sudo ./scripts/ubuntu24-best-config.sh --autologin-user <username>

Options:
  --autologin-user <user>   Enable GDM auto login for this user
  --skip-autologin          Skip auto login configuration
  --skip-gsettings          Skip GNOME lock/sleep gsettings for user
  --skip-logind-restart     Do not restart systemd-logind immediately
  -h, --help                Show help
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

install_hardening_dropin() {
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

install_watchdog() {
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

set_gdm_autologin_xorg() {
  local user="$1"

  [[ -f /etc/gdm3/custom.conf ]] || die "/etc/gdm3/custom.conf not found (gdm3 missing?)."
  id "${user}" >/dev/null 2>&1 || die "User does not exist: ${user}"

  if ! command_exists crudini; then
    log "Installing crudini to edit /etc/gdm3/custom.conf safely..."
    apt-get update -y
    apt-get install -y crudini
  fi

  cp -an /etc/gdm3/custom.conf "/etc/gdm3/custom.conf.bak.$(date +%Y%m%d-%H%M%S)"
  crudini --set /etc/gdm3/custom.conf daemon WaylandEnable false
  crudini --set /etc/gdm3/custom.conf daemon AutomaticLoginEnable true
  crudini --set /etc/gdm3/custom.conf daemon AutomaticLogin "${user}"
}

set_gnome_no_lock_no_suspend() {
  local user="$1"
  id "${user}" >/dev/null 2>&1 || die "User does not exist: ${user}"
  command_exists gsettings || { warn "gsettings not found, skipping user desktop policy."; return 0; }
  command_exists dbus-run-session || { warn "dbus-run-session not found, skipping gsettings."; return 0; }

  log "Applying GNOME no-lock/no-suspend policy for user: ${user}"
  sudo -u "${user}" dbus-run-session -- gsettings set org.gnome.desktop.session idle-delay uint32 0 || true
  sudo -u "${user}" dbus-run-session -- gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  sudo -u "${user}" dbus-run-session -- gsettings set org.gnome.desktop.screensaver lock-delay uint32 0 || true
  sudo -u "${user}" dbus-run-session -- gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
  sudo -u "${user}" dbus-run-session -- gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || true
}

main() {
  require_root

  local autologin_user=""
  local skip_autologin="0"
  local skip_gsettings="0"
  local skip_logind_restart="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --autologin-user)
        autologin_user="${2:-}"; shift 2 ;;
      --skip-autologin)
        skip_autologin="1"; shift ;;
      --skip-gsettings)
        skip_gsettings="1"; shift ;;
      --skip-logind-restart)
        skip_logind_restart="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown argument: $1" ;;
    esac
  done

  if [[ "${skip_autologin}" != "1" && -z "${autologin_user}" ]]; then
    die "Please provide --autologin-user <username>, or pass --skip-autologin."
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
      warn "This script is optimized for Ubuntu 24.04, current: ${PRETTY_NAME:-unknown}"
    fi
  fi

  log "Disabling system sleep/suspend/hibernate targets..."
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

  log "Writing logind no-suspend policy..."
  install -d -m 0755 /etc/systemd/logind.conf.d
  cat >/etc/systemd/logind.conf.d/99-binguindesk-no-suspend.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF

  log "Setting graphical target as default..."
  systemctl set-default graphical.target

  if [[ "${skip_autologin}" != "1" ]]; then
    log "Configuring GDM auto login + Ubuntu on Xorg..."
    set_gdm_autologin_xorg "${autologin_user}"
  else
    warn "Auto login was skipped."
  fi

  if [[ "${skip_gsettings}" != "1" && "${skip_autologin}" != "1" ]]; then
    set_gnome_no_lock_no_suspend "${autologin_user}"
  elif [[ "${skip_gsettings}" == "1" ]]; then
    warn "GNOME gsettings step was skipped."
  fi

  log "Applying RustDesk service hardening and watchdog..."
  install_hardening_dropin
  install_watchdog

  systemctl daemon-reload
  systemctl enable rustdesk || true
  systemctl restart rustdesk || true
  systemctl enable rustdesk-watchdog.timer
  systemctl restart rustdesk-watchdog.timer

  if [[ "${skip_logind_restart}" != "1" ]]; then
    warn "Restarting systemd-logind may terminate current GUI sessions."
    systemctl restart systemd-logind || warn "Failed to restart systemd-logind, reboot is required."
  fi

  log "Done. Reboot is strongly recommended to apply Xorg/autologin/display-manager policies."
}

main "$@"
