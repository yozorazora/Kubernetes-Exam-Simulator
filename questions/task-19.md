# Task 19 — Troubleshoot: Control Plane Components
**Weight: 10%** | **Cluster: bk8s**

---

## Task

```bash
kubectl config use-context bk8s
```

One or more **control plane components** on `bk8s-control-plane` are **not running**.

Investigate the failure and **fix it** so all control plane components are healthy.

> **Practice mode:** Use `cause <1-4>` in this shell to inject a specific failure scenario.
> Diagnose from scratch each time — then run `check` to verify your fix.
> Run `reset` first to restore a clean state before switching causes.

---

## Key Concept — Static Pods

Control plane components (apiserver, scheduler, controller-manager) are **static pods** managed directly by the kubelet. Their manifests live at:

```
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
```

**Kubelet watches this directory** — any change to a manifest file immediately restarts the corresponding pod. This is both how failures are injected AND how fixes are applied.

---

## Investigation Steps

```bash
# Step 1: Check control plane pod status (if apiserver is UP)
kubectl -n kube-system get pods | grep -E "apiserver|scheduler|controller"

# Step 2: Describe the broken pod for Events
kubectl -n kube-system describe pod kube-scheduler-bk8s-control-plane

# Step 3: Read the failing component's logs
kubectl -n kube-system logs kube-scheduler-bk8s-control-plane

# ── If kube-apiserver is DOWN, kubectl won't work — use crictl instead ────────

# Step 4: SSH into the control plane node
docker exec -it bk8s-control-plane bash

# Step 5: Use crictl to list all containers (including exited/crashed)
crictl ps -a | grep -E "apiserver|scheduler|controller"

# Step 6: Read logs of a specific container via crictl
crictl logs <container-id>

# Step 7: Check kubelet logs for manifest parse errors
journalctl -u kubelet -xe --no-pager | tail -40

# Step 8: Inspect the static pod manifests directly
ls /etc/kubernetes/manifests/
cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

---

## Cause 1 — kube-apiserver CrashLoopBackOff: Bad Flag

**Symptom:**
```bash
# kubectl commands timeout or return connection refused
kubectl --context=bk8s get nodes
# Error: ... connect: connection refused

# SSH into control plane and check with crictl
docker exec -it bk8s-control-plane bash
crictl ps -a | grep apiserver
# <id>  kube-apiserver  Exited  ...

crictl logs <id>
# Error: unknown flag: --this-flag-does-not-exist
```

**Root cause:** An unknown flag `--this-flag-does-not-exist=true` was added to `/etc/kubernetes/manifests/kube-apiserver.yaml`. The apiserver process exits on startup → kubelet restarts it → CrashLoopBackOff.

**Fix (inside bk8s-control-plane):**
```bash
# Remove the bad flag from the manifest
sed -i '/--this-flag-does-not-exist/d' /etc/kubernetes/manifests/kube-apiserver.yaml

# Verify the line is gone
grep "this-flag" /etc/kubernetes/manifests/kube-apiserver.yaml
# (no output — good)

# kubelet detects the change and restarts apiserver automatically
# Exit the node and wait for apiserver to recover (~30-60s)
exit
kubectl --context=bk8s get pods -n kube-system -w
```

---

## Cause 2 — kube-scheduler Cannot Start: Bad kubeconfig Path

**Symptom:**
```bash
# kubectl works — apiserver is fine
kubectl -n kube-system get pods | grep scheduler
# kube-scheduler-bk8s-control-plane    0/1   CrashLoopBackOff   4   3m

kubectl -n kube-system logs kube-scheduler-bk8s-control-plane
# E ... unable to load config: open /etc/kubernetes/scheduler-broken.conf: no such file

# Check the manifest
docker exec -it bk8s-control-plane bash
grep kubeconfig /etc/kubernetes/manifests/kube-scheduler.yaml
# - --kubeconfig=/etc/kubernetes/scheduler-broken.conf   ← wrong!
```

**Root cause:** `--kubeconfig` flag points to `/etc/kubernetes/scheduler-broken.conf` which does not exist.

**Fix (inside bk8s-control-plane):**
```bash
# Fix the kubeconfig path in the manifest
sed -i 's|scheduler-broken.conf|scheduler.conf|' /etc/kubernetes/manifests/kube-scheduler.yaml

# Verify
grep kubeconfig /etc/kubernetes/manifests/kube-scheduler.yaml
# - --kubeconfig=/etc/kubernetes/scheduler.conf   ← correct

exit
kubectl -n kube-system get pods -w
```

---

## Cause 3 — kube-controller-manager Failed: Bad kubeconfig Path

**Symptom:**
```bash
# kubectl works — apiserver is fine
kubectl -n kube-system get pods | grep controller-manager
# kube-controller-manager-bk8s-control-plane   0/1   CrashLoopBackOff   4   3m

kubectl -n kube-system logs kube-controller-manager-bk8s-control-plane
# E ... unable to load config: open /etc/kubernetes/controller-manager-broken.conf: no such file

# Check the manifest
docker exec -it bk8s-control-plane bash
grep kubeconfig /etc/kubernetes/manifests/kube-controller-manager.yaml
# - --kubeconfig=/etc/kubernetes/controller-manager-broken.conf   ← wrong!
```

**Root cause:** `--kubeconfig` flag points to `/etc/kubernetes/controller-manager-broken.conf` which does not exist.

**Fix (inside bk8s-control-plane):**
```bash
sed -i 's|controller-manager-broken.conf|controller-manager.conf|' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml

grep kubeconfig /etc/kubernetes/manifests/kube-controller-manager.yaml
# - --kubeconfig=/etc/kubernetes/controller-manager.conf   ← correct

exit
kubectl -n kube-system get pods -w
```

---

## Cause 4 — Static Pod Manifest Has YAML Syntax Error

**Symptom:**
```bash
# kubectl works — apiserver is fine, BUT scheduler pod is MISSING
kubectl -n kube-system get pods | grep scheduler
# (no output — pod does not exist at all)

# kubelet logs show a manifest parse error
docker exec -it bk8s-control-plane bash
journalctl -u kubelet -xe --no-pager | grep -i "scheduler\|yaml\|error\|parse" | tail -10
# E ... failed to process config ... error parsing manifest ...
# OR: couldn't parse as pod ...

# The last lines of the scheduler manifest are invalid
tail -5 /etc/kubernetes/manifests/kube-scheduler.yaml
# INVALID_YAML: [this is not valid yaml
```

**Root cause:** An invalid YAML line was appended to `kube-scheduler.yaml`. The kubelet cannot parse the manifest, so no pod is created — it silently disappears.

**Fix (inside bk8s-control-plane):**
```bash
# Remove the invalid YAML line
sed -i '/INVALID_YAML/d' /etc/kubernetes/manifests/kube-scheduler.yaml

# Verify the manifest is now valid
tail -5 /etc/kubernetes/manifests/kube-scheduler.yaml
# (should end with valid YAML — no INVALID_YAML line)

# kubelet parses the fixed manifest and creates the scheduler pod
exit
kubectl -n kube-system get pods | grep scheduler
# kube-scheduler-bk8s-control-plane   1/1   Running   0   ...
```

---

## Quick Root Cause Reference Table

| Symptom | Root Cause | Where to look | Fix |
|---------|-----------|---------------|-----|
| kubectl times out / "connection refused" | kube-apiserver crashing | `crictl logs <apiserver-id>` | Remove bad flag from kube-apiserver.yaml |
| scheduler `CrashLoopBackOff` + "no such file" | Bad kubeconfig path | `kubectl logs <scheduler-pod>` | Fix `--kubeconfig` path in kube-scheduler.yaml |
| controller-manager `CrashLoopBackOff` + "no such file" | Bad kubeconfig path | `kubectl logs <cm-pod>` | Fix `--kubeconfig` path in kube-controller-manager.yaml |
| scheduler pod MISSING entirely | YAML syntax error in manifest | `journalctl -u kubelet` | Remove invalid YAML line from kube-scheduler.yaml |

---

## Key Commands Cheatsheet

```bash
# From outside (when apiserver is UP):
kubectl -n kube-system get pods
kubectl -n kube-system logs <pod-name>
kubectl -n kube-system describe pod <pod-name>

# From inside the control plane node:
docker exec -it bk8s-control-plane bash

# When apiserver is DOWN — use crictl:
crictl ps -a                         # list all containers including exited
crictl logs <container-id>           # read container logs

# Manifests directory:
ls /etc/kubernetes/manifests/
vi /etc/kubernetes/manifests/<component>.yaml    # edit to fix
# OR: sed -i '...' /etc/kubernetes/manifests/<component>.yaml

# Kubelet logs (useful for YAML parse errors):
journalctl -u kubelet -xe --no-pager | tail -40
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Diagnostic decision tree:**

```bash
# Question 1: Does kubectl work?
kubectl --context=bk8s get pods -n kube-system --request-timeout=5s
# → timeout / refused → Cause 1 (apiserver down)
# → works →  Check which pod is broken:

# Question 2: What is the broken pod's status?
kubectl -n kube-system get pods | grep -E "apiserver|scheduler|controller"
# → CrashLoopBackOff → read logs to find the error
# → pod MISSING       → Cause 4 (YAML error — kubelet can't parse manifest)

# For CrashLoopBackOff: read the logs first
kubectl -n kube-system logs <broken-pod>
# → "no such file or directory" + kubeconfig path → Cause 2 or 3
#    Fix: sed to correct the --kubeconfig path in the manifest

# For Cause 1 (apiserver down): SSH in and use crictl
docker exec -it bk8s-control-plane bash
crictl ps -a | grep apiserver
crictl logs <id>
# → "unknown flag" → find and remove the bad flag from kube-apiserver.yaml

# For Cause 4 (pod missing): check kubelet logs and manifest tail
journalctl -u kubelet | grep -i "error\|yaml" | tail -10
tail -5 /etc/kubernetes/manifests/kube-scheduler.yaml
# → find the bad YAML line → sed -i '/INVALID_YAML/d' ...
```

**After every fix:** kubelet detects the manifest change automatically. Wait 15-30s for the pod to restart, then verify with `kubectl -n kube-system get pods`.

</details>

---

## Answer

```bash
kubectl config use-context bk8s

# ── Common diagnostic flow ─────────────────────────────────────────────────────
kubectl -n kube-system get pods | grep -E "apiserver|scheduler|controller"
kubectl -n kube-system logs <broken-pod>
kubectl -n kube-system describe pod <broken-pod>

# ── Cause 1: kube-apiserver CrashLoopBackOff ──────────────────────────────────
# kubectl doesn't work → SSH in and use crictl
docker exec -it bk8s-control-plane bash
crictl ps -a | grep apiserver
crictl logs $(crictl ps -a | grep apiserver | awk '{print $1}' | head -1)
# → "unknown flag: --this-flag-does-not-exist"
sed -i '/--this-flag-does-not-exist/d' /etc/kubernetes/manifests/kube-apiserver.yaml
exit
# Wait ~30-60s for apiserver to recover
kubectl --context=bk8s get pods -n kube-system -w

# ── Cause 2: kube-scheduler Cannot Start ──────────────────────────────────────
kubectl -n kube-system logs kube-scheduler-bk8s-control-plane
# → "unable to load config: .../scheduler-broken.conf: no such file"
docker exec -it bk8s-control-plane bash
sed -i 's|scheduler-broken.conf|scheduler.conf|' \
    /etc/kubernetes/manifests/kube-scheduler.yaml
exit
kubectl -n kube-system get pods -w

# ── Cause 3: kube-controller-manager Failed ───────────────────────────────────
kubectl -n kube-system logs kube-controller-manager-bk8s-control-plane
# → "unable to load config: .../controller-manager-broken.conf: no such file"
docker exec -it bk8s-control-plane bash
sed -i 's|controller-manager-broken.conf|controller-manager.conf|' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
exit
kubectl -n kube-system get pods -w

# ── Cause 4: Static pod manifest YAML syntax error ────────────────────────────
# Scheduler pod is MISSING entirely
kubectl -n kube-system get pods | grep scheduler   # no output
docker exec -it bk8s-control-plane bash
journalctl -u kubelet -xe --no-pager | grep -i "yaml\|parse\|scheduler" | tail -10
tail -5 /etc/kubernetes/manifests/kube-scheduler.yaml
# → INVALID_YAML: [this is not valid yaml
sed -i '/INVALID_YAML/d' /etc/kubernetes/manifests/kube-scheduler.yaml
exit
kubectl -n kube-system get pods | grep scheduler
# kube-scheduler-bk8s-control-plane   1/1   Running   0   ...
```
