# Task 18 — Troubleshoot: Pod Not Running (10 Failure Causes)
**Weight: 10%** | **Cluster: k8s**

---

## Task

```bash
kubectl config use-context k8s
```

A pod **`task18-pod`** in namespace **`task18`** is **not healthy** — it may be Pending, crashing, failing to pull its image, or stuck not Ready.

Investigate the root cause and **fix the pod** so it is **Running** with **1/1 Ready** containers.

> **Practice mode:** Use `cause <1-10>` in this shell to inject a specific failure scenario.
> Diagnose from scratch each time — then run `check` to verify your fix.
> Run `reset` first to clean up before switching to a different cause.

---

## Investigation Steps

```bash
# Step 1: Check pod status and READY column
kubectl -n task18 get pods

# Step 2: Describe the pod — Events section reveals the root cause
kubectl -n task18 describe pod task18-pod

# Step 3: Check pod logs (if status is Running or CrashLoopBackOff)
kubectl -n task18 logs task18-pod

# Step 4: Check previous container logs (if container is restarting)
kubectl -n task18 logs task18-pod --previous

# Step 5: Check all events sorted by time
kubectl -n task18 get events --sort-by=.lastTimestamp

# Step 6: Check related resources (PVC, ConfigMap, Secret)
kubectl -n task18 get pod,pvc,configmap,secret

# Step 7: Check node resources (for Pending due to insufficient CPU/memory)
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

## Cause 1 — Pod Pending: Insufficient CPU/Memory

**Symptom:**
```bash
kubectl -n task18 get pods
# NAME          READY   STATUS    RESTARTS   AGE
# task18-pod    0/1     Pending   0          30s

kubectl -n task18 describe pod task18-pod | tail -10
# Events:
#   Warning  FailedScheduling  ... 0/1 nodes available: 1 Insufficient cpu.
```

**Root cause:** `resources.requests.cpu: "99"` — no node has 99 CPUs to allocate.

**Fix:**
```bash
# Pod resource requests are immutable — delete and recreate with sensible limits
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never
```

---

## Cause 2 — ImagePullBackOff: Wrong Image Name (Typo)

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     ImagePullBackOff   0   45s

kubectl -n task18 describe pod task18-pod | grep -A 5 Events
# Warning  Failed  ... Failed to pull image "ngiinx:latest": ... not found
```

**Root cause:** Image name is `ngiinx:latest` (typo — should be `nginx:latest`).

**Fix:**
```bash
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never
```

---

## Cause 3 — CrashLoopBackOff: Container Exits Immediately

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     CrashLoopBackOff   4   3m

kubectl -n task18 logs task18-pod
# (empty or shows only the error)

kubectl -n task18 describe pod task18-pod | grep "Exit Code"
# Exit Code:    1
```

**Root cause:** Container command is `sh -c "exit 1"` — exits with code 1 immediately every time.

**Fix:**
```bash
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never
```

---

## Cause 4 — FailedMount: ConfigMap Volume Not Found

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     Pending   0   45s

kubectl -n task18 describe pod task18-pod | tail -10
# Warning  FailedMount  ... configmap "task18-config-vol" not found
```

**Root cause:** Pod mounts a volume from ConfigMap `task18-config-vol` which does not exist.

**Fix:**
```bash
# Create the missing ConfigMap — pod auto-retries and mounts it
kubectl -n task18 create configmap task18-config-vol --from-literal=key=value
```

---

## Cause 5 — ConfigMap Missing: envFrom Reference

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     CreateContainerConfigError   0   30s

kubectl -n task18 describe pod task18-pod | grep -A 3 Events
# Error: configmap "task18-env-config" not found
```

**Root cause:** Pod uses `envFrom: configMapRef: task18-env-config` but ConfigMap does not exist.

**Fix:**
```bash
kubectl -n task18 create configmap task18-env-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info
```

---

## Cause 6 — Secret Missing: envFrom Reference

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     CreateContainerConfigError   0   30s

kubectl -n task18 describe pod task18-pod | grep -A 3 Events
# Error: secret "task18-env-secret" not found
```

**Root cause:** Pod uses `envFrom: secretRef: task18-env-secret` but Secret does not exist.

**Fix:**
```bash
kubectl -n task18 create secret generic task18-env-secret \
  --from-literal=DB_PASSWORD=secret123 \
  --from-literal=API_KEY=abc123
```

---

## Cause 7 — PVC Pending: StorageClass Not Found

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     Pending   0   45s

kubectl -n task18 get pvc
# NAME          STATUS    STORAGECLASS   AGE
# task18-pvc    Pending   fake-sc        45s

kubectl -n task18 describe pvc task18-pvc
# Warning  ProvisioningFailed  ... storageclass.storage.k8s.io "fake-sc" not found
```

**Root cause:** PVC uses StorageClass `fake-sc` which does not exist. Pod cannot start until PVC is Bound.

**Fix:**
```bash
# Find a valid StorageClass
kubectl get storageclass

# Delete the broken PVC and recreate with a valid StorageClass
kubectl -n task18 delete pvc task18-pvc
kubectl -n task18 apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task18-pvc
  namespace: task18
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
  storageClassName: standard
EOF

# Confirm PVC is Bound, then pod auto-schedules
kubectl -n task18 get pvc task18-pvc
```

---

## Cause 8 — Readiness Probe Failing: Wrong Port

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     Running   0   60s
#              ↑ READY is 0/1 — pod runs but never becomes Ready

kubectl -n task18 describe pod task18-pod | grep -A 8 Readiness
# Readiness:   http-get http://:9999/ ...
# Warning  Unhealthy  Readiness probe failed: Get "http://:9999/": connection refused
```

**Root cause:** readinessProbe checks port `9999` but nginx listens on port `80`.

**Fix:**
```bash
# Probe config is immutable — delete and recreate with the correct port
kubectl -n task18 delete pod task18-pod
kubectl -n task18 apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: task18
spec:
  containers:
  - name: app
    image: nginx:latest
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
EOF
```

---

## Cause 9 — Liveness Probe Failing: Wrong Command

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     Running   4   3m    ← restarting repeatedly

kubectl -n task18 describe pod task18-pod | grep -A 8 Liveness
# Liveness:   exec [sh -c exit 1] ...
# Warning  Unhealthy  Liveness probe failed: ...

kubectl -n task18 describe pod task18-pod | grep "Exit Code"
# Exit Code:    137   ← killed by liveness probe (SIGKILL = 128+9)
```

**Root cause:** livenessProbe runs `sh -c "exit 1"` — always fails, killing the container repeatedly.

**Fix:**
```bash
# Probe config is immutable — delete and recreate without the bad probe
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never
```

---

## Cause 10 — Wrong Image Tag

**Symptom:**
```bash
kubectl -n task18 get pods
# task18-pod    0/1     ErrImagePull   0   15s
# (becomes ImagePullBackOff after a few retries)

kubectl -n task18 describe pod task18-pod | grep -A 5 Events
# Warning  Failed  ... Failed to pull image "nginx:9999": ... tag does not exist
```

**Root cause:** Image tag `9999` does not exist in the nginx registry.

**Fix:**
```bash
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never
```

---

## Quick Root Cause Reference Table

| Status / Event keyword | Root cause | Fix |
|------------------------|-----------|-----|
| `Pending` + "Insufficient cpu/memory" | Resource requests too high | Delete pod, recreate with lower requests |
| `ImagePullBackOff` + image name not found | Wrong image name (typo) | Delete pod, fix image name |
| `CrashLoopBackOff` + Exit Code 1 | Container command exits immediately | Delete pod, fix command |
| `Pending` + FailedMount + "configmap not found" | ConfigMap missing (volume) | Create the ConfigMap |
| `CreateContainerConfigError` + "configmap not found" | ConfigMap missing (envFrom) | Create the ConfigMap |
| `CreateContainerConfigError` + "secret not found" | Secret missing (envFrom) | Create the Secret |
| `Pending` + PVC Pending + "storageclass not found" | PVC uses invalid StorageClass | Recreate PVC with valid StorageClass |
| `Running` but `0/1 Ready` + "connection refused" probe | Readiness probe wrong port/path | Delete pod, fix readiness probe |
| `Running` + restarts + Exit Code 137 | Liveness probe kills container | Delete pod, fix/remove liveness probe |
| `ErrImagePull` + "tag does not exist" | Wrong image tag | Delete pod, fix image tag |

---

## Hint

<details>
<summary>Click to expand</summary>

**Diagnostic flow — always start here:**

```bash
# 1. Check STATUS and READY columns
kubectl -n task18 get pods

# 2. Describe for Events (most diagnostic — always check this)
kubectl -n task18 describe pod task18-pod | tail -20

# 3. Map symptom to cause:
#   Pending + "Insufficient cpu"              → Cause 1:  lower resource requests
#   ImagePullBackOff + image name not found   → Cause 2:  fix image name typo
#   CrashLoopBackOff + Exit Code 1            → Cause 3:  fix container command
#   Pending + FailedMount + configmap         → Cause 4:  create ConfigMap (volume mount)
#   CreateContainerConfigError + configmap    → Cause 5:  create ConfigMap (envFrom)
#   CreateContainerConfigError + secret       → Cause 6:  create Secret (envFrom)
#   Pending + PVC Pending + storageclass      → Cause 7:  fix PVC StorageClass
#   Running 0/1 + readiness probe failure     → Cause 8:  fix readiness probe port/path
#   Running + restarts + Exit Code 137        → Cause 9:  fix liveness probe
#   ErrImagePull + "tag does not exist"       → Cause 10: fix image tag

# 4. After fix — watch pod recover
kubectl -n task18 get pods -w
```

**Key distinctions to remember:**

ConfigMap/Secret issues come in two forms:
- **Volume mount** (`volumes: configMap:`) → pod stays `Pending` with **FailedMount** event
- **envFrom** (`envFrom: configMapRef/secretRef:`) → pod shows **CreateContainerConfigError**

Image pull issues differ by what's wrong:
- **Wrong name** (e.g., `ngiinx`) → "repository does not exist" or "not found"
- **Wrong tag** (e.g., `nginx:9999`) → "tag does not exist"

Probe issues differ by effect:
- **Readiness probe** fails → pod stays `Running` but **0/1 Ready** (no restarts)
- **Liveness probe** fails → pod **restarts** repeatedly → CrashLoopBackOff, Exit Code 137

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Common diagnostic commands ──────────────────────────────────────────────────
kubectl -n task18 get pods
kubectl -n task18 describe pod task18-pod
kubectl -n task18 logs task18-pod
kubectl -n task18 get events --sort-by=.lastTimestamp

# ── Cause 1: Pending — lower resource requests ─────────────────────────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never

# ── Cause 2: ImagePullBackOff — fix image name typo ───────────────────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never

# ── Cause 3: CrashLoopBackOff — fix container command ─────────────────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never

# ── Cause 4: FailedMount — create the missing ConfigMap (volume) ───────────────
kubectl -n task18 create configmap task18-config-vol --from-literal=key=value

# ── Cause 5: ConfigMap missing (envFrom) — create it ──────────────────────────
kubectl -n task18 create configmap task18-env-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info

# ── Cause 6: Secret missing (envFrom) — create it ─────────────────────────────
kubectl -n task18 create secret generic task18-env-secret \
  --from-literal=DB_PASSWORD=secret123 \
  --from-literal=API_KEY=abc123

# ── Cause 7: PVC Pending — fix StorageClass ────────────────────────────────────
kubectl get storageclass                      # find a valid StorageClass name
kubectl -n task18 delete pvc task18-pvc
kubectl -n task18 apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task18-pvc
  namespace: task18
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
  storageClassName: standard
EOF

# ── Cause 8: Readiness probe wrong port — delete and recreate ─────────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: task18
spec:
  containers:
  - name: app
    image: nginx:latest
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
EOF

# ── Cause 9: Liveness probe wrong command — delete and recreate ───────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never

# ── Cause 10: Wrong image tag — delete and recreate ───────────────────────────
kubectl -n task18 delete pod task18-pod
kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never

# ── Verify (all causes) ────────────────────────────────────────────────────────
kubectl -n task18 get pods
# task18-pod   1/1   Running   0   ...
```
