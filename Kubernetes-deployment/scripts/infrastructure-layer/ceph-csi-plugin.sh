#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/ceph-csi}"
CEPH_CSI_BRANCH="${CEPH_CSI_BRANCH:-devel}"

log() {
  echo
  echo "==== $1 ===="
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1"
    exit 1
  }
}

log "Checking prerequisites"
require_cmd git
require_cmd kubectl

if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning ceph-csi"
  git clone --branch "$CEPH_CSI_BRANCH" https://github.com/ceph/ceph-csi.git "$REPO_DIR"
else
  log "Using existing repo at $REPO_DIR"
fi

cd "$REPO_DIR/deploy/cephfs/kubernetes"

log "Writing csi-config-map.yaml"
cat > csi-config-map.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
data:
  config.json: |-
    [
      {
        "clusterID": "295c678a-9297-4f37-907f-f9cf69ef067b",
        "monitors": [
          "172.16.42.63:3300"
        ],
        "cephFS": {
          "subvolumeGroup": "csi"
        }
      }
    ]
EOF

log "Writing ceph-csi-encryption-kms-config.yaml"
cat > ceph-csi-encryption-kms-config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-encryption-kms-config
data:
  config.json: |-
    {}
EOF

log "Deploying CephFS CSI resources"
kubectl create -f csidriver.yaml || kubectl apply -f csidriver.yaml
kubectl create -f csi-provisioner-rbac.yaml || kubectl apply -f csi-provisioner-rbac.yaml
kubectl create -f csi-nodeplugin-rbac.yaml || kubectl apply -f csi-nodeplugin-rbac.yaml
kubectl create -f csi-config-map.yaml || kubectl apply -f csi-config-map.yaml
kubectl create -f ceph-csi-encryption-kms-config.yaml || kubectl apply -f ceph-csi-encryption-kms-config.yaml
kubectl create -f ../../ceph-conf.yaml || kubectl apply -f ../../ceph-conf.yaml
kubectl create -f csi-cephfsplugin-provisioner.yaml || kubectl apply -f csi-cephfsplugin-provisioner.yaml
kubectl create -f csi-cephfsplugin.yaml || kubectl apply -f csi-cephfsplugin.yaml

log "Done"
kubectl get pods -A | grep ceph || true
