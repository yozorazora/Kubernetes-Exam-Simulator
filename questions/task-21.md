# Task 21 — Taints and Tolerations
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Complete the following three parts in namespace `task21`:

**Part 1 — Add a taint to the worker node:**

Taint node `k8s-worker` with the effect `NoSchedule`:
- Key: `dedicated`
- Value: `blue`
- Effect: `NoSchedule`

**Part 2 — Create a pod that is BLOCKED by the taint:**

Create a pod named `pod-no-toleration` in namespace `task21`:
- Image: `nginx:latest`
- No toleration for the taint
- This pod should remain `Pending` because it cannot schedule on the tainted node

**Part 3 — Create a pod that TOLERATES the taint:**

Create a pod named `pod-tolerant` in namespace `task21`:
- Image: `nginx:latest`
- Add a toleration that allows it to schedule on `k8s-worker`
- This pod should be `Running` on the tainted node

---

## Key Concepts

```
┌─────────────────────────────────────────────────────────────────────┐
│  Taint on Node           │  Toleration on Pod                       │
│  ──────────────────────  │  ───────────────────────────────────     │
│  dedicated=blue:         │  - key: dedicated                        │
│    NoSchedule            │    operator: Equal                       │
│                          │    value: blue                           │
│                          │    effect: NoSchedule                    │
└─────────────────────────────────────────────────────────────────────┘

Taint Effects:
  NoSchedule   → New pods that lack the toleration will NOT be scheduled
  NoExecute    → New AND existing pods without toleration are evicted
  PreferNoSchedule → Scheduler tries to avoid the node (soft constraint)
```

**Why `pod-no-toleration` stays Pending:**
- `k8s-worker` has `NoSchedule` taint → blocked for pods without toleration
- `k8s-control-plane` has its own `node-role.kubernetes.io/control-plane:NoSchedule` taint
- Result: no schedulable node → pod stays Pending

**Why `pod-tolerant` runs on `k8s-worker`:**
- The toleration unlocks `k8s-worker` (removes the blocking)
- `k8s-control-plane` still has its own taint that `pod-tolerant` does NOT tolerate
- Result: only viable node is `k8s-worker` → scheduled there

---

## Additional Information

```bash
# Check which nodes exist
kubectl get nodes

# Check existing taints on nodes
kubectl describe node k8s-worker | grep -A5 Taints

# Check if namespace exists
kubectl get namespace task21

# Create it if missing
kubectl create namespace task21

# Discover worker node name (if not sure)
kubectl get nodes --no-headers | grep -v "control-plane\|master" | awk '{print $1}'
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Add a taint:**
```bash
kubectl taint node k8s-worker dedicated=blue:NoSchedule
```

**Remove a taint (when resetting):**
```bash
kubectl taint node k8s-worker dedicated=blue:NoSchedule-
```

**Toleration block in pod spec:**
```yaml
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "blue"
    effect: "NoSchedule"
```

**Shorthand — tolerate all taints on a node:**
```yaml
tolerations:
- operator: "Exists"
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Part 1 — Create namespace and taint the worker node
kubectl create namespace task21 --dry-run=client -o yaml | kubectl apply -f -
kubectl taint node k8s-worker dedicated=blue:NoSchedule

# Confirm taint was applied
kubectl describe node k8s-worker | grep Taint

# Part 2 — Pod without toleration (will stay Pending)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-no-toleration
  namespace: task21
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# Confirm it is Pending
kubectl -n task21 get pod pod-no-toleration

# Part 3 — Pod WITH toleration (will schedule on k8s-worker)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-tolerant
  namespace: task21
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "blue"
    effect: "NoSchedule"
  containers:
  - name: nginx
    image: nginx:latest
EOF

# Confirm it is Running on k8s-worker
kubectl -n task21 get pod pod-tolerant -o wide
```
