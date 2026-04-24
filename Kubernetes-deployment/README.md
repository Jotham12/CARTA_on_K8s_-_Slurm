# CARTA Deployed on Kubernetes

This directory contains the resources used to deploy CARTA in a Kubernetes-based environment. The deployment is organised into two main parts:

- `carta-controller` — contains the main CARTA controller code
- `scripts` — contains deployment scripts and YAML manifests grouped into:
  - `Infrastructure-layer`
  - `Application-layer`
  - `Operational-layer`

The Kubernetes test bed was deployed on three Ubuntu virtual machines using **kubeadm**: one control-plane node and two worker nodes. Shared persistent storage was provided through **CephFS** integrated into Kubernetes via the **Ceph-CSI plugin**. Application resources were isolated in a dedicated namespace called `carta`.

---

## Deployment Layers

### 1. Infrastructure Layer

This layer prepares the Kubernetes cluster and the storage environment required for CARTA. It covers cluster bootstrapping with `kubeadm`, worker-node participation, CephFS integration through Ceph-CSI, namespace creation, and persistent storage provisioning.

#### Main responsibilities

- initialize the Kubernetes cluster
- configure node access through `kubeconfig`
- deploy Ceph-CSI components
- create the `carta` namespace
- create the StorageClass and PersistentVolumeClaim for shared CephFS storage

#### Scripts and files in this layer

- `setup-kubeadm.sh` — prepares the control-plane and worker nodes for Kubernetes
- `setup-cephfs-csi.sh` — deploys the Ceph-CSI CephFS driver
- `cephfs-storageclass.yaml` — defines the CephFS StorageClass
- `cephfs-pvc.yaml` — creates the shared PersistentVolumeClaim
- namespace manifest — creates the `carta` namespace

#### Outcome

After completing this layer, the Kubernetes cluster is running, shared storage is available through CephFS, and the environment is ready for CARTA application deployment.

---

### 2. Application Deployment Layer

This layer deploys the CARTA controller and the supporting application resources inside Kubernetes. It includes controller configuration, Secrets, ConfigMaps, RBAC, mounted identity files, and backend execution behavior.

The CARTA controller runs as a Kubernetes Deployment inside the `carta` namespace. Its configuration is divided between a Secret containing `config.json` and a ConfigMap containing backend runtime parameters. Supporting resources such as `nsswitch.conf`, host keys, and `extrausers` are mounted into the controller pod so that user identity resolution inside the container remains consistent with the external filesystem environment.

A service account, role, and role binding are defined to allow the controller to create, list, and remove backend pods and inspect pod logs within the namespace. Backend workloads are scheduled onto worker nodes by the Kubernetes control plane.

A key modification was introduced to support secure multi-user access. User authentication is handled through PAM, while backend launch arguments are adjusted so that each session opens within a user-specific path derived from the authenticated username, for example `/images/${username}`. This ensures that the controller, authentication layer, and shared storage permissions work together to keep each user within the correct working directory.

Supporting platform services include cert-manager for certificate management and MongoDB, deployed through the MongoDB Community Operator.

#### Main responsibilities

- deploy the CARTA controller into the `carta` namespace
- provide controller configuration through a Secret and ConfigMap
- mount supporting files such as `nsswitch.conf`, host keys, and `extrausers`
- define RBAC resources for backend pod management
- deploy supporting services such as MongoDB and cert-manager

#### Scripts and files in this layer

- `kubectl create secret generic carta-config --from-file=config.json` — creates a Secret containing the CARTA configuration file
- `mongodb-community.yaml` — deploys MongoDB for persistent controller state
- `kubectl create secret generic carta-extrausers --from-file=extrausers` — creates a Secret for extra user identity files
- `carta-controller.yaml` — deploys the CARTA controller and related Kubernetes resources, including:
  - Deployment
  - Service
  - ServiceAccount
  - Role
  - RoleBinding

#### Outcome

After completing this layer, the CARTA controller is deployed and able to create and manage backend sessions for authenticated users.

---

### 3. Operational Setup and Maintenance Layer

This layer covers the configuration needed to make the deployment usable and maintainable in practice. It focuses on user identity consistency, storage permissions, access control, and external connectivity.

Operationally, the Kubernetes environment requires node-level preparation on all three virtual machines before cluster initialization. This includes installing the container runtime, `kubeadm`, `kubelet`, and `kubectl`, preparing the control-plane node, and joining the worker nodes to the cluster. After cluster formation, pod networking is enabled through a Container Network Interface plugin so that nodes can transition to the `Ready` state and support multi-node workload scheduling.

To support multi-user access control, directories are created on CephFS for each user, with ownership mapped using the appropriate UIDs and GIDs and permissions restricted using `chmod 700`. Identity information, including `passwd`, `group`, and `shadow`, is packaged into a Kubernetes Secret and mounted into the controller container together with `nsswitch.conf`, allowing authentication and filesystem permissions to operate consistently across the application and storage layers.

External access to the platform is provided through SSH port forwarding for testing, NGINX Ingress for HTTP routing, and MetalLB for load-balanced exposure in OpenStack.

#### Main responsibilities

- create per-user directories on CephFS
- assign correct UIDs and GIDs for user isolation
- restrict directory access with appropriate permissions
- ensure PAM-based authentication works with the mounted identity files
- expose the deployment through Ingress and external access mechanisms
- verify that the platform is functioning correctly

#### Scripts and files in this layer

- `create-user-directories.sh` — creates user directories on CephFS
- `set-directory-permissions.sh` — applies ownership and `chmod 700`
- `ingress.yaml` — exposes the CARTA controller externally
- `metallb-config.yaml` — provides load-balanced access where required

#### Outcome

After completing this layer, users can authenticate, access only their own directories, and use CARTA through the deployed entry point.

---

## Recommended Deployment Order

Run the setup in the following order:

1. Complete the **Infrastructure Layer**
2. Complete the **Application Deployment Layer**
3. Complete the **Operational Setup and Maintenance Layer**

This order ensures that the cluster, storage, and namespace are ready before deploying the CARTA application and configuring user access controls.

---

## Notes

- The `carta` namespace is used to isolate application resources.
- CephFS storage is exposed to Kubernetes through the Ceph-CSI plugin.
- The shared PersistentVolumeClaim uses `ReadWriteMany` access mode so that multiple pods can access the same storage.
- User isolation is enforced through PAM authentication, user-specific startup directories, CephFS ownership, and restricted filesystem permissions.
