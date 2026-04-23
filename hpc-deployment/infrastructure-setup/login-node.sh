#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
MUNGEUSER=1001
SLURMUSER=1002

SLURM_DB_NAME="slurm_acct_db"
SLURM_DB_USER="slurm"
SLURM_DB_PASS="hashmi12"

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
  log "Installing packages"
  sudo apt-get update
  sudo apt-get install -y \
    munge \
    mariadb-server \
    slurmdbd \
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

  sudo mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge "$SHARED_DIR"
  sudo chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge
  sudo chmod 0700 /etc/munge /var/log/munge /var/lib/munge /run/munge

  if [ ! -f /etc/munge/munge.key ]; then
    echo "ERROR: /etc/munge/munge.key does not exist."
    echo "Create or place the munge key first, then rerun this script."
    exit 1
  fi

  sudo cp /etc/munge/munge.key "$SHARED_DIR/"
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
# DATABASE
# =========================
setup_database() {
  log "Configuring MariaDB database for Slurm"

  sudo systemctl enable mariadb
  sudo systemctl start mariadb

  sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${SLURM_DB_NAME};
CREATE USER IF NOT EXISTS '${SLURM_DB_USER}'@'localhost' IDENTIFIED BY '${SLURM_DB_PASS}';
GRANT ALL ON ${SLURM_DB_NAME}.* TO '${SLURM_DB_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
}

# =========================
# CONFIG FILES
# =========================
write_slurmdbd_conf() {
  log "Writing ${SLURM_ETC_DIR}/slurmdbd.conf"

  sudo mkdir -p "$SLURM_ETC_DIR" /var/log/slurm
  sudo touch /var/log/slurm/slurmdbd.log
  sudo chown -R slurm:slurm /var/log/slurm

  sudo tee "${SLURM_ETC_DIR}/slurmdbd.conf" >/dev/null <<EOF
AuthType=auth/munge
DbdAddr=localhost
DbdHost=localhost
DbdPort=6819
SlurmUser=slurm
DebugLevel=4
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurm/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageHost=localhost
StorageLoc=${SLURM_DB_NAME}
StoragePass=${SLURM_DB_PASS}
StorageUser=${SLURM_DB_USER}
PurgeEventAfter=12months
PurgeJobAfter=12months
PurgeResvAfter=2months
PurgeStepAfter=2months
PurgeSuspendAfter=1month
PurgeTXNAfter=12months
PurgeUsageAfter=12months
EOF

  sudo chown slurm:slurm "${SLURM_ETC_DIR}/slurmdbd.conf"
  sudo chmod 600 "${SLURM_ETC_DIR}/slurmdbd.conf"
}

write_slurm_conf() {
  log "Writing ${SLURM_ETC_DIR}/slurm.conf"

  sudo mkdir -p /var/spool/slurmctld /var/spool/slurmd /var/log/slurm
  sudo touch /var/log/slurm/slurmctld.log
  sudo chown -R slurm:slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm

  sudo tee "${SLURM_ETC_DIR}/slurm.conf" >/dev/null <<'EOF'
ClusterName=cluster
SlurmctldHost=vm1

SlurmUser=slurm

StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
ReturnToService=2

SchedulerType=sched/backfill

SwitchType=switch/none

MpiDefault=none

ProctrackType=proctrack/linuxproc

SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

TaskPlugin=task/none

AuthType=auth/munge

SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd-%h.log

SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd-%h.pid

JobAcctGatherType=jobacct_gather/linux
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
AccountingStoragePort=6819
AccountingStorageEnforce=associations

SlurmctldPort=6817
SlurmdPort=6818
LaunchParameters=enable_nss_slurm

NodeName=vm2 NodeAddr=192.168.1.28 CPUs=4 Boards=1 SocketsPerBoard=4 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=32093 State=UNKNOWN
NodeName=vm3 NodeAddr=192.168.1.26 CPUs=2 RealMemory=2048 State=UNKNOWN

PartitionName=debug Nodes=vm2,vm3 Default=YES MaxTime=INFINITE State=UP
EOF
}

write_cgroup_conf() {
  log "Ensuring cgroup.conf contains CgroupMountpoint"

  sudo mkdir -p "$SLURM_ETC_DIR_ALT"
  sudo touch "${SLURM_ETC_DIR_ALT}/cgroup.conf"

  grep -qxF 'CgroupMountpoint=/sys/fs/cgroup' "${SLURM_ETC_DIR_ALT}/cgroup.conf" || \
    echo "CgroupMountpoint=/sys/fs/cgroup" | sudo tee -a "${SLURM_ETC_DIR_ALT}/cgroup.conf" >/dev/null
}

# =========================
# FIREWALL
# =========================
open_firewall_ports() {
  log "Allowing firewall ports"
  sudo ufw allow 6817 || true
  sudo ufw allow 6818 || true
  sudo ufw allow 6819 || true
}

# =========================
# SERVICE FILE DISCOVERY
# =========================
find_service_files() {
  log "Finding service files"
  sudo find / -name "slurmctld.service" 2>/dev/null || true
  sudo find / -name "slurmd.service" 2>/dev/null || true
  sudo find / -name "slurmdbd.service" 2>/dev/null || true
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
  log "Starting Slurm services"

  sudo systemctl daemon-reload
  sudo systemctl enable slurmdbd
  sudo systemctl start slurmdbd
  sudo systemctl enable slurmctld
  sudo systemctl start slurmctld

  log "Service status"
  sudo systemctl status slurmdbd --no-pager || true
  sudo systemctl status slurmctld --no-pager || true
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
  setup_database
  write_slurmdbd_conf
  write_slurm_conf
  write_cgroup_conf
  open_firewall_ports
  find_service_files
  show_node_info
  start_services

  echo
  echo "Done."
  echo "Created:"
  echo "  ${SLURM_ETC_DIR}/slurm.conf"
  echo "  ${SLURM_ETC_DIR}/slurmdbd.conf"
  echo "  ${SLURM_ETC_DIR_ALT}/cgroup.conf"
}

main "$@"
