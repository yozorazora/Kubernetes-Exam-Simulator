# Task 24 — Helm Fundamentals
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Use **Helm** to manage a chart release in namespace **`task24`**:

---

**Part A — Add the Bitnami repository and install a release:**

1. Add the Bitnami Helm repository (URL: `https://charts.bitnami.com/bitnami`) with the name `bitnami`
2. Update your local chart cache
3. Install the `bitnami/nginx` chart as a release named **`task24-nginx`** in namespace **`task24`** (create the namespace if it doesn't exist)

---

**Part B — Upgrade the release:**

Upgrade `task24-nginx` to set `replicaCount=2`.

---

**Part C — Inspect the release:**

1. List all Helm releases in namespace `task24` — confirm `task24-nginx` is deployed
2. Check the release status with `helm status`
3. View the release history with `helm history`

---

**Part D — Rollback:**

Roll the release back to **revision 1** (the initial install).

---

## Key Concepts

```
Helm v3 Architecture:
  Repository  →  chart source (bitnami, stable, etc.)
  Chart       →  package of Kubernetes manifests + default values
  Release     →  named deployment of a chart into a cluster
  Revision    →  each install/upgrade/rollback creates a new revision

Core commands:
  helm repo add <name> <url>     →  register a chart repository
  helm repo update               →  refresh local chart cache
  helm install <release> <chart> →  deploy a chart
  helm upgrade <release> <chart> →  update a deployed release
  helm rollback <release> <rev>  →  revert to a previous revision
  helm list -n <ns>              →  list releases in a namespace
  helm status <release> -n <ns>  →  show release status + notes
  helm history <release> -n <ns> →  show all revisions

Override values at install/upgrade time:
  --set key=value                →  inline value override
  --values file.yaml             →  load from a YAML file

Useful flags:
  --create-namespace             →  create namespace if it doesn't exist
  --namespace / -n               →  target namespace
```

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# Part A
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install task24-nginx bitnami/nginx \
  --namespace task24 \
  --create-namespace

# Part B
helm upgrade task24-nginx bitnami/nginx \
  --namespace task24 \
  --set replicaCount=2

# Part C
helm list -n task24
helm status task24-nginx -n task24
helm history task24-nginx -n task24

# Part D
helm rollback task24-nginx 1 -n task24
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: Add repo and install ──────────────────────────────────────────────

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install task24-nginx bitnami/nginx \
  --namespace task24 \
  --create-namespace

# Wait for the release to become deployed
helm list -n task24

# ── Part B: Upgrade with overridden value ─────────────────────────────────────

helm upgrade task24-nginx bitnami/nginx \
  --namespace task24 \
  --set replicaCount=2

# Verify upgrade took effect
kubectl get deployment -n task24

# ── Part C: Inspect release ───────────────────────────────────────────────────

# List all releases in namespace
helm list -n task24
# STATUS column should show: deployed

# Full status output
helm status task24-nginx -n task24

# Show revision history
helm history task24-nginx -n task24
# REVISION 1: install
# REVISION 2: upgrade (replicaCount=2)

# ── Part D: Rollback to revision 1 ────────────────────────────────────────────

helm rollback task24-nginx 1 -n task24

# Verify — revision 3 should appear in history with DESCRIPTION: Rollback to 1
helm history task24-nginx -n task24

# Pod count should be back to default (1)
kubectl get pods -n task24
```
