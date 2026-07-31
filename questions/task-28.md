# Task 28 — Horizontal Pod Autoscaler (HPA)
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

---

**Part A — Create a Deployment with resource requests:**

Create namespace **`task28`**, then create Deployment **`task28-deploy`** with:
- Image: `nginx:latest`
- Replicas: `1`
- CPU request: `100m` (required for HPA to function)
- Label on pods: `app=task28-deploy`

---

**Part B — Create a Horizontal Pod Autoscaler:**

Create an HPA named **`task28-hpa`** targeting `task28-deploy` in namespace **`task28`** with:
- Minimum replicas: `2`
- Maximum replicas: `5`
- Target CPU utilization: `50%`

---

**Part C — Verify the HPA:**

1. Confirm the HPA was created with the correct min/max/target
2. Show the current number of replicas (the HPA may immediately scale to min=2)
3. Describe the HPA and read the scaling events/conditions

---

## Key Concepts

```
HPA — Horizontal Pod Autoscaler:
  Watches a metric (CPU, memory, or custom)
  Scales Deployment/StatefulSet replicas between min and max
  Requires: metrics-server to be installed and Pod resource requests set

  Without resource requests → HPA shows "unknown" for current CPU
  Without metrics-server    → HPA cannot collect metrics

HPA formula:
  desiredReplicas = ceil(currentReplicas × (currentCPU / targetCPU))

  Example: 1 replica using 100% CPU, target is 50%
  → ceil(1 × 100/50) = ceil(2.0) = 2 replicas

Scale-down cooldown (default 5 min):
  HPA won't scale down faster than every 5 minutes to avoid flapping.
  Scale-up happens quickly.

HPA vs VPA:
  HPA  →  scales the NUMBER of pods (horizontal)
  VPA  →  adjusts resource requests/limits of existing pods (vertical)

API version in v1.35:
  autoscaling/v2  →  current (supports multiple metrics)
  autoscaling/v1  →  legacy (CPU only, still works)
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Imperative (easiest in exam):**
```bash
kubectl autoscale deployment task28-deploy \
  --cpu-percent=50 \
  --min=2 \
  --max=5 \
  -n task28
```

**Declarative (autoscaling/v2):**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: task28-hpa
  namespace: task28
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: task28-deploy
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: Namespace + Deployment ────────────────────────────────────────────

kubectl create namespace task28 --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task28-deploy
  namespace: task28
spec:
  replicas: 1
  selector:
    matchLabels:
      app: task28-deploy
  template:
    metadata:
      labels:
        app: task28-deploy
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
EOF

kubectl rollout status deployment/task28-deploy -n task28

# ── Part B: HPA — imperative (fastest in exam) ────────────────────────────────

kubectl autoscale deployment task28-deploy \
  --cpu-percent=50 \
  --min=2 \
  --max=5 \
  --namespace task28

# Or declarative (autoscaling/v2 for multi-metric support):
# cat <<EOF | kubectl apply -f -
# apiVersion: autoscaling/v2
# kind: HorizontalPodAutoscaler
# ...
# EOF

# ── Part C: Verify ────────────────────────────────────────────────────────────

# Show HPA summary
kubectl get hpa task28-hpa -n task28
# MINPODS  MAXPODS  REPLICAS  CPU(current/target)
# 2        5        2         <unknown>/50%   ← unknown if no metrics-server

# HPA may scale up to min=2 immediately (minReplicas takes effect right away)
kubectl get pods -n task28

# Detailed view including conditions and events
kubectl describe hpa task28-hpa -n task28

# Check using autoscaling/v2 API
kubectl get hpa task28-hpa -n task28 -o yaml
```
