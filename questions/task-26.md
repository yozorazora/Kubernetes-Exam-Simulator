# Task 26 — DaemonSet
**Weight: 3%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

---

**Part A — Create a DaemonSet:**

Create a DaemonSet named **`task26-ds`** in namespace **`task26`** with:
- Image: `nginx:latest`
- Label on pods: `app=task26-ds`
- Update strategy: `RollingUpdate`

The DaemonSet must schedule **one pod on every schedulable node** in the cluster.

---

**Part B — Verify scheduling:**

Confirm the DaemonSet pod(s) are running on all expected nodes.

---

**Part C — Update the DaemonSet image:**

Update the DaemonSet's container image to `nginx:1.27.2-alpine` using a rolling update.  
Verify the rollout completes.

---

## Key Concepts

```
DaemonSet:
  Guarantees exactly one pod per (schedulable) node.
  New nodes added to the cluster automatically get a pod.
  Used for: log collectors (Fluentd), monitoring agents (node-exporter),
            network plugins (Calico, Flannel), storage drivers.

DaemonSet vs Deployment:
  Deployment  →  N replicas, scheduler places them on any node
  DaemonSet   →  1 replica per node, placement is automatic

Scheduling on control-plane nodes:
  By default, control-plane nodes have a NoSchedule taint:
    node-role.kubernetes.io/control-plane:NoSchedule
  DaemonSets respect this — pods won't run on control-plane
  UNLESS you add a matching toleration.

Update strategies:
  RollingUpdate  →  replaces one pod at a time (default, safe)
  OnDelete       →  only replaces pod when manually deleted (manual control)

Key fields:
  spec.selector              →  must match spec.template.metadata.labels
  spec.updateStrategy.type   →  RollingUpdate or OnDelete
  status.desiredNumberScheduled   →  how many nodes the DS targets
  status.numberReady              →  how many pods are Ready
```

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# DaemonSets cannot be created with kubectl run — you must use YAML
# Generate a skeleton from a Deployment and convert:
kubectl create deployment task26-ds --image=nginx:latest \
  --dry-run=client -o yaml | grep -v "replicas\|strategy" > /tmp/ds.yaml
# Then change kind: Deployment → kind: DaemonSet
# Remove spec.replicas, spec.strategy, add spec.updateStrategy
```

**Minimal DaemonSet YAML:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: task26-ds
  namespace: task26
spec:
  selector:
    matchLabels:
      app: task26-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: task26-ds
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

**Update image (Part C):**
```bash
kubectl set image daemonset/task26-ds nginx=nginx:1.27.2-alpine -n task26
kubectl rollout status daemonset/task26-ds -n task26
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: Create namespace and DaemonSet ────────────────────────────────────

kubectl create namespace task26 --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: task26-ds
  namespace: task26
  labels:
    app: task26-ds
spec:
  selector:
    matchLabels:
      app: task26-ds
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: task26-ds
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
EOF

# ── Part B: Verify scheduling ─────────────────────────────────────────────────

# Wait for pods to be Ready
kubectl rollout status daemonset/task26-ds -n task26

# Check pods — should show one pod per worker node
kubectl get pods -n task26 -o wide

# Check DaemonSet status
kubectl get daemonset task26-ds -n task26
# DESIRED and READY should match the number of schedulable nodes

# ── Part C: Rolling update ────────────────────────────────────────────────────

kubectl set image daemonset/task26-ds \
  nginx=nginx:1.27.2-alpine -n task26

# Watch rollout progress
kubectl rollout status daemonset/task26-ds -n task26

# Verify new image
kubectl get daemonset task26-ds -n task26 \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: nginx:1.27.2-alpine
```
