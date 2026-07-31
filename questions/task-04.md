# Task 04 — Cluster Upgrade via kubeadm
**Weight: 8%** | **Cluster: wk8s**

---

## Task

```
kubectl config use-context wk8s
```

The cluster `wk8s` is running Kubernetes **v1.31.x** on the control-plane (the worker node is already on **v1.32.x**). Upgrade the **control-plane node only** to Kubernetes **v1.32.x** using `kubeadm`, so it matches the worker.

**Steps required:**
1. Drain the control-plane node (evict pods, mark unschedulable)
2. Upgrade `kubeadm` on the control-plane node
3. Run `kubeadm upgrade apply`
4. Upgrade `kubelet` and `kubectl` on the control-plane node
5. Restart `kubelet`
6. Uncordon the control-plane node

Do **not** upgrade the worker nodes.

---

## Additional Information

- SSH into the control-plane node: `ssh wk8s-control-plane`  
  *(In kind, use: `docker exec -it wk8s-control-plane bash`)*
- The control-plane node is the only node to upgrade in this task.
- Use `apt-get` (Ubuntu/Debian) or `dnf`/`yum` (RHEL/CentOS).

---

## Hint

<details>
<summary>Click to expand</summary>

The kubeadm upgrade flow on Ubuntu:

```bash
# From your local machine — drain the node first
kubectl drain wk8s-control-plane --ignore-daemonsets --delete-emptydir-data

# SSH into control-plane
docker exec -it wk8s-control-plane bash
  # Inside the node:
  apt-mark unhold kubeadm
  apt-get update
  apt-get install -y kubeadm=1.32.0-1.1
  apt-mark hold kubeadm

  kubeadm upgrade plan
  kubeadm upgrade apply v1.32.0

  apt-mark unhold kubelet kubectl
  apt-get install -y kubelet=1.32.0-1.1 kubectl=1.32.0-1.1
  apt-mark hold kubelet kubectl
  systemctl daemon-reload
  systemctl restart kubelet
  exit

# Back on local machine — uncordon
kubectl uncordon wk8s-control-plane
```

</details>

---

## Answer

```bash
kubectl config use-context wk8s

# Step 1: Drain control-plane
CPNODE=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl drain "$CPNODE" --ignore-daemonsets --delete-emptydir-data

# Step 2: Enter control-plane node
docker exec -it wk8s-control-plane bash

# Inside node — upgrade kubeadm
apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.32.0-1.1 && apt-mark hold kubeadm
kubeadm upgrade apply v1.32.0 --yes

# Upgrade kubelet + kubectl
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.32.0-1.1 kubectl=1.32.0-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
exit

# Step 3: Uncordon
kubectl uncordon "$CPNODE"

# Verify
kubectl get nodes
# Control-plane should show v1.32.x, matching the worker
```

> **Note:** kind node images don't ship with the Kubernetes apt repo configured, so a plain kind cluster can't run these apt commands for real. This simulator's `reset` for Task 04 adds the real `pkgs.k8s.io` v1.32 repo to `wk8s-control-plane` automatically, so the commands above work exactly as shown — no VM needed.
