#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
MUNGEUSER=1001
SLURMUSER=1002

SLURM_REPO_URL="https://github.com/SchedMD/slurm.git"
SLURM_SRC_PARENT="/opt"
SLURM_SRC_DIR="${SLURM_SRC_PARENT}/slurm"

SLURM_ETC_DIR="/etc/slurm"
SLURM_ETC_DIR_ALT="/etc/slurm-llnl"
SHARED_DIR="/data/slurm"

# =========================
# HELPERS
# =========================
log() {
  echo
  echo "==== $1 ===="
}

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required"
    exit 1
  fi
}

# =========================
# USERS
# =========================
setup_users() {
  log "Creating munge and slurm users/groups"

  if ! getent group munge >/dev/null 2>&1; then
    sudo groupadd -g "$MUNGEUSER" munge
  fi

  if ! id -u munge >/dev/null 2>&1; then
    sudo useradd -m -c "MUNGE Uid 'N' Gid Emporium" \
      -d /var/lib/munge -u "$MUNGEUSER" -g munge -s /sbin/nologin munge
  fi

  if ! getent group slurm >/dev/null 2>&1; then
    sudo groupadd -g "$SLURMUSER" slurm
  fi

  if ! id -u slurm >/dev/null 2>&1; then
    sudo useradd -m -c "SLURM workload manager" \
      -d /var/lib/slurm -u "$SLURMUSER" -g slurm -s /bin/bash slurm
  fi
}

# =========================
# PACKAGES
# =========================
install_packages() {
  log "Installing compute-node packages"
  sudo apt-get update
  sudo apt-get install -y \
    munge \
    slurmd \
    slurm-wlm \
    git \
    build-essential \
    libmunge-dev \
    ufw
}

# =========================
# MUNGE
# =========================
setup_munge() {
  log "Configuring munge"

  sudo mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
  sudo chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge
  sudo chmod 0700 /etc/munge /var/log/munge /var/lib/munge /run/munge

  if [ ! -f "${SHARED_DIR}/munge.key" ]; then
    echo "ERROR: ${SHARED_DIR}/munge.key does not exist."
    echo "Copy the munge key from the login node first."
    exit 1
  fi

  sudo cp "${SHARED_DIR}/munge.key" /etc/munge/munge.key
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 0400 /etc/munge/munge.key

  sudo systemctl enable munge
  sudo systemctl restart munge
}

# =========================
# NSS_SLURM
# =========================
build_nss_slurm() {
  log "Cloning Slurm source and building nss_slurm"

  sudo mkdir -p "$SLURM_SRC_PARENT"

  if [ ! -d "$SLURM_SRC_DIR" ]; then
    sudo git clone "$SLURM_REPO_URL" "$SLURM_SRC_DIR"
  fi

  cd "$SLURM_SRC_DIR/contribs/nss_slurm"
  make
  sudo make install
}

# =========================
# CONFIG FILES
# =========================
setup_configs() {
  log "Setting up Slurm config files"

  sudo mkdir -p "$SLURM_ETC_DIR" "$SLURM_ETC_DIR_ALT" /var/spool/slurmd /var/log/slurm

  if [ ! -f "${SHARED_DIR}/slurm.conf" ]; then
    echo "ERROR: ${SHARED_DIR}/slurm.conf does not exist."
    echo "Copy slurm.conf from the login node first."
    exit 1
  fi

  sudo cp "${SHARED_DIR}/slurm.conf" "${SLURM_ETC_DIR}/slurm.conf"

  sudo touch /var/log/slurm/slurmd.log
  sudo chown -R slurm:slurm /var/spool/slurmd /var/log/slurm

  grep -qxF 'CgroupMountpoint=/sys/fs/cgroup' "${SLURM_ETC_DIR_ALT}/cgroup.conf" 2>/dev/null || \
    echo "CgroupMountpoint=/sys/fs/cgroup" | sudo tee -a "${SLURM_ETC_DIR_ALT}/cgroup.conf" >/dev/null
}

# =========================
# FIREWALL
# =========================
open_firewall_ports() {
  log "Allowing compute-node firewall port"
  sudo ufw allow 6818 || true
}

# =========================
# INFO
# =========================
show_node_info() {
  log "Showing node hardware info"
  slurmd -C || true
}

# =========================
# START SERVICES
# =========================
start_services() {
  log "Starting compute-node services"

  sudo systemctl daemon-reload
  sudo systemctl enable munge
  sudo systemctl start munge

  sudo systemctl enable slurmd.service
  sudo systemctl start slurmd.service

  log "Service status"
  sudo systemctl status munge --no-pager || true
  sudo systemctl status slurmd.service --no-pager || true
}

# =========================
# MAIN
# =========================
main() {
  require_sudo
  setup_users
  install_packages
  setup_munge
  build_nss_slurm
  setup_configs
  open_firewall_ports
  show_node_info
  start_services

  echo
  echo "Done."
  echo "Compute node is configured."
}

main "$@"
