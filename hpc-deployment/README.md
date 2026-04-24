# CARTA Deployment on HPC using Slurm

This folder contains the scripts, configuration files, and setup steps used to deploy CARTA in an HPC-oriented environment using **Slurm** as the resource manager. The deployment was implemented on three Ubuntu virtual machines provisioned in OpenStack and connected through a shared CephFS storage layer.

The Slurm-based environment was designed to support authenticated multi-user access to CARTA, user-specific working directories, shared persistent storage, and controller-managed backend launch through the HPC scheduler.

---

## Test Bed Overview

The Slurm-based CARTA test bed was deployed on three Ubuntu virtual machines:

- **Login/control node**
  - 32 GB RAM
  - 20 GB storage
  - 4 vCPUs

- **Compute node 1**
  - 16 GB RAM
  - 20 GB storage
  - 4 vCPUs

- **Compute node 2**
  - 16 GB RAM
  - 20 GB storage
  - 4 vCPUs

All nodes were placed on the same subnet to support:

- Slurm scheduling
- authentication
- controller-to-worker communication
- access to shared CephFS storage

---

## Deployment Layers

### 1. Infrastructure Layer

This layer prepares the base HPC environment required for CARTA.

It includes:

- preparing the login/control node and compute nodes
- configuring hostname and identity resolution
- setting up `extrausers`
- modifying `nsswitch.conf`
- enabling `nss_slurm` for managed node hostname resolution
- installing and configuring **MUNGE**
- distributing a shared `munge.key`
- installing Slurm and its supporting services
- configuring MariaDB for Slurm accounting through `slurmdbd`

#### Main configuration files
- `slurm.conf`
- `slurmdbd.conf`
- `cgroup.conf`

#### Typical scripts/files in this layer
- login node setup script
- compute node setup script
- MUNGE setup script
- Slurm configuration files
- MariaDB / accounting configuration

#### Outcome
After completing this layer, the Slurm cluster is installed, authentication between nodes is working, accounting services are configured, and the control node can communicate with the compute nodes.

---

### 2. Application Deployment Layer

This layer adapts CARTA to the Slurm-based HPC environment.

It includes:

- creating user accounts explicitly on compute nodes
- creating user home directories
- preparing per-user directories on CephFS
- assigning correct ownership to user directories
- restricting access with `chmod 700`
- configuring the CARTA controller on the login node
- defining backend launch and kill commands
- configuring PAM-based authentication
- defining folder templates so users start in their own directories

Instead of launching backend services as Kubernetes-managed pods, the controller delegates backend execution into the Slurm-managed environment.

#### Main application resources
- `config.json`
- backend launch scripts
- user directory creation scripts
- CephFS ownership and permission scripts

#### Outcome
After completing this layer, the CARTA controller can authenticate users and launch user-specific backend sessions through Slurm while keeping each user restricted to their own working directory.

---

### 3. Operational Setup and Maintenance Layer

This layer covers the practical steps required to run, expose, and maintain the deployment.

It includes:

- enabling and starting:
  - `munge`
  - `slurmdbd`
  - `slurmctld`
  - `slurmd`
- opening firewall ports for controller, daemon, and database services
- creating log, spool, and PID file directories
- validating cluster health using:
  - `systemctl status`
  - `scontrol ping`
  - `sinfo`
  - `squeue`
- testing access to the controller through SSH tunneling
- applying cgroup-based resource constraints

Compared with the Kubernetes deployment, this layer involves more direct administrator control and repeated node-level coordination.

#### Outcome
After completing this layer, the Slurm services are active, the compute nodes are registered, and CARTA can be accessed and tested through the login node.

---

## Recommended Deployment Order

Run the setup in the following order:

1. Complete the **Infrastructure Layer**
2. Complete the **Application Deployment Layer**
3. Complete the **Operational Setup and Maintenance Layer**

This order ensures that the scheduler, authentication, and shared storage are ready before deploying and testing CARTA.

---

## Example Workflow

### Step 1: Prepare the infrastructure
- configure `/etc/hosts`
- configure `extrausers`
- modify `nsswitch.conf`
- install and configure MUNGE
- distribute `munge.key`
- install Slurm and `slurmdbd`
- configure MariaDB
- create `slurm.conf`, `slurmdbd.conf`, and `cgroup.conf`

### Step 2: Prepare the application environment
- create user accounts on compute nodes
- create user directories on CephFS
- assign ownership and permissions
- configure CARTA `config.json`
- define backend launch and kill commands
- configure folder templates and PAM authentication

### Step 3: Start and validate services
- start `munge`
- start `slurmdbd`
- start `slurmctld`
- start `slurmd`
- verify node registration
- test controller access with SSH tunneling
- validate user backend launches

---

## Validation Commands

Useful commands for checking the deployment:

```bash
systemctl status munge
systemctl status slurmdbd
systemctl status slurmctld
systemctl status slurmd
