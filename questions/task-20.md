# Task 20 — Troubleshoot: Service & DNS Debugging (5 Causes)
**Weight: 6%** | **Cluster: k8s**

---

## Task

```bash
kubectl config use-context k8s
```

A client pod **`task20-client`** in namespace **`task20`** cannot reach service **`task20-svc`**.

Investigate why and **fix it** so the client can successfully resolve and connect to the service.

> **Practice mode:** Use `cause <1-5>` in this shell to inject a specific failure scenario.
> Each cause breaks connectivity differently — diagnose from scratch, then run `check` to verify.
> Run `reset` first to restore a clean state before switching causes.

---

## Key Concepts

```
Client Pod  →  DNS lookup (CoreDNS)  →  ClusterIP  →  kube-proxy  →  Pod (targetPort)
```

**Three places connectivity can break:**
1. **DNS** — can't resolve the service name → CoreDNS issue or service doesn't exist in the right namespace
2. **Service → Pod routing** — DNS resolves but connection fails → wrong `selector` (no endpoints) or wrong `targetPort`
3. **Client → Service port** — service exists and has endpoints but client reaches the wrong port → wrong `port` on the Service

---

## Investigation Steps

```bash
# Step 1: Check if the service exists and inspect its config
kubectl -n task20 get svc task20-svc
kubectl -n task20 describe svc task20-svc

# Step 2: Check endpoints — this is the KEY diagnostic command
kubectl -n task20 get endpoints task20-svc
# <none>   → selector mismatch (Cause 1) or wrong targetPort (Cause 2)
# Has IPs  → DNS issue or wrong service port

# Step 3: Check that pod labels match service selector
kubectl -n task20 get pods --show-labels
kubectl -n task20 get pods -l app=task20-server

# Step 4: Test DNS from inside the client pod
kubectl -n task20 exec task20-client -- nslookup task20-svc
kubectl -n task20 exec task20-client -- nslookup task20-svc.task20.svc.cluster.local

# Step 5: Test HTTP connectivity
kubectl -n task20 exec task20-client -- wget -qO- --timeout=5 http://task20-svc/

# Step 6: Check CoreDNS if DNS is failing for ALL names
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get deployment coredns
```

---

## Cause 1 — Selector Mismatch: No Endpoints

**Symptom:**
```bash
kubectl -n task20 get endpoints task20-svc
# NAME          ENDPOINTS   AGE
# task20-svc    <none>      30s   ← no endpoints = selector doesn't match any pod

kubectl -n task20 describe svc task20-svc | grep Selector
# Selector:  app=task20-wrong   ← wrong!

kubectl -n task20 get pods --show-labels | grep task20-server
# task20-server   Running   app=task20-server   ← label is different from selector
```

**Root cause:** Service selector `app: task20-wrong` does not match the pod label `app: task20-server`. Service has no endpoints — kube-proxy cannot forward any traffic.

**Fix:**
```bash
# Patch the service selector to match the pod label
kubectl -n task20 patch svc task20-svc \
  -p '{"spec":{"selector":{"app":"task20-server"}}}'

# Verify endpoints now appear
kubectl -n task20 get endpoints task20-svc
# task20-svc   10.244.x.x:80   ...
```

---

## Cause 2 — Wrong targetPort: Connection Refused Despite Endpoints

**Symptom:**
```bash
kubectl -n task20 get endpoints task20-svc
# task20-svc   10.244.x.x:8080   ← endpoints EXIST but port 8080 is wrong (nginx is on 80)

kubectl -n task20 exec task20-client -- wget -qO- --timeout=5 http://task20-svc/
# wget: can't connect to remote host: Connection refused

kubectl -n task20 describe svc task20-svc | grep TargetPort
# TargetPort:  8080/TCP   ← nginx container listens on 80, not 8080
```

**Root cause:** `targetPort: 8080` does not match the container port. Endpoints exist (kube-proxy tries to forward) but the connection to the pod is refused because nothing listens on port 8080.

**Fix:**
```bash
kubectl -n task20 patch svc task20-svc \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'

# Verify endpoints now show port 80
kubectl -n task20 get endpoints task20-svc
# task20-svc   10.244.x.x:80   ...
```

---

## Cause 3 — CoreDNS Scaled to Zero: All DNS Resolution Fails

**Symptom:**
```bash
kubectl -n task20 exec task20-client -- nslookup task20-svc
# nslookup: can't resolve 'task20-svc'

kubectl -n task20 exec task20-client -- nslookup kubernetes.default
# nslookup: can't resolve 'kubernetes.default'   ← ALL DNS fails, not just one service

kubectl -n kube-system get pods -l k8s-app=kube-dns
# (no output — CoreDNS pods are gone)

kubectl -n kube-system get deployment coredns
# NAME      READY   UP-TO-DATE   AVAILABLE
# coredns   0/0     0            0          ← scaled to 0!
```

**Root cause:** The CoreDNS Deployment was scaled to 0 replicas. No DNS server is running in the cluster, so all service name resolution fails.

**Fix:**
```bash
kubectl -n kube-system scale deployment coredns --replicas=2

# Wait for CoreDNS pods to be Running
kubectl -n kube-system get pods -l k8s-app=kube-dns -w

# Verify DNS works again
kubectl -n task20 exec task20-client -- nslookup task20-svc
```

---

## Cause 4 — Wrong Service Port: Client Reaches Wrong Port

**Symptom:**
```bash
kubectl -n task20 get endpoints task20-svc
# task20-svc   10.244.x.x:80   ← endpoints look correct (targetPort 80 is right)

kubectl -n task20 describe svc task20-svc | grep -E "Port:|TargetPort:"
# Port:        9090/TCP    ← service is exposed on port 9090, not 80!
# TargetPort:  80/TCP      ← container port is correct

kubectl -n task20 exec task20-client -- wget -qO- --timeout=5 http://task20-svc/
# wget: can't connect: Connection refused   ← client tries :80 but service listens on :9090

kubectl -n task20 exec task20-client -- wget -qO- --timeout=5 http://task20-svc:9090/
# <!DOCTYPE html>...  ← works on port 9090
```

**Root cause:** Service `port: 9090` — the service ClusterIP is accessible on port 9090, but the standard HTTP client connects to port 80. Endpoints and targetPort are fine; only the exposed service port is wrong.

**Fix:**
```bash
kubectl -n task20 patch svc task20-svc \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/port","value":80}]'

kubectl -n task20 describe svc task20-svc | grep "Port:"
# Port:  80/TCP   ← correct
```

---

## Cause 5 — Service in Wrong Namespace: Short DNS Name Fails

**Symptom:**
```bash
kubectl -n task20 get svc
# (no output — no service in task20 namespace!)

kubectl -n task20 exec task20-client -- nslookup task20-svc
# nslookup: can't resolve 'task20-svc'   ← no service in this namespace

# But it exists elsewhere:
kubectl get svc -A | grep task20-svc
# default     task20-svc   ClusterIP   10.x.x.x   80/TCP   ← wrong namespace!
```

**Root cause:** Service `task20-svc` was created in the `default` namespace instead of `task20`. DNS short names only resolve within the same namespace — `task20-svc` resolves to `task20-svc.task20.svc.cluster.local`, which doesn't exist.

**Fix:**
```bash
# Delete the misplaced service
kubectl -n default delete svc task20-svc

# Recreate in the correct namespace
kubectl -n task20 expose pod task20-server \
  --name=task20-svc --port=80 --target-port=80

# Verify
kubectl -n task20 get svc task20-svc
kubectl -n task20 exec task20-client -- nslookup task20-svc
```

---

## Quick Root Cause Reference Table

| Key observation | Root cause | Fix |
|----------------|-----------|-----|
| `get endpoints` shows `<none>` | Selector mismatch | Patch service selector to match pod labels |
| `get endpoints` shows pod IP with wrong port | Wrong `targetPort` | Patch targetPort to match container port |
| ALL DNS fails (`nslookup kubernetes.default` also fails) | CoreDNS down | `kubectl scale deploy coredns -n kube-system --replicas=2` |
| Endpoints correct, but only reachable on unexpected port | Wrong service `port` | Patch service port to 80 |
| `get svc -n task20` shows no service, but service exists in another namespace | Service in wrong namespace | Delete and recreate in correct namespace |

---

## DNS Name Format Cheatsheet

```bash
# From a pod in the SAME namespace as the service:
nslookup task20-svc                              # short name — works

# From a pod in a DIFFERENT namespace:
nslookup task20-svc.task20                       # <svc>.<namespace>
nslookup task20-svc.task20.svc.cluster.local     # fully qualified — always works

# Test HTTP with full URL:
wget -qO- http://task20-svc.task20.svc.cluster.local/
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Diagnostic decision tree:**

```bash
# 1. Does the service exist in the right namespace?
kubectl -n task20 get svc task20-svc
# → not found → check other namespaces: kubectl get svc -A | grep task20
#   → Cause 5: recreate service in task20 namespace

# 2. Does DNS resolve?
kubectl -n task20 exec task20-client -- nslookup task20-svc
# → fails AND kubernetes.default also fails → CoreDNS is down → Cause 3
# → fails BUT kubernetes.default works     → service not in namespace → Cause 5

# 3. Do endpoints exist?
kubectl -n task20 get endpoints task20-svc
# → <none>              → selector mismatch → Cause 1
# → has IPs, wrong port → targetPort wrong  → Cause 2
# → has IPs, right port → service port wrong → Cause 4

# 4. After identifying the cause, patch the service:
kubectl -n task20 patch svc task20-svc -p '{"spec":{...}}'

# 5. Verify end-to-end:
kubectl -n task20 exec task20-client -- wget -qO- http://task20-svc/
# → Should return nginx welcome page
```

**Key insight:** `kubectl get endpoints <svc>` is the single most important command for service debugging. It tells you immediately whether the selector works AND which port traffic is forwarded to.

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Common diagnostic commands ──────────────────────────────────────────────────
kubectl -n task20 get svc task20-svc
kubectl -n task20 get endpoints task20-svc
kubectl -n task20 get pods --show-labels
kubectl -n task20 exec task20-client -- nslookup task20-svc
kubectl -n task20 exec task20-client -- wget -qO- --timeout=5 http://task20-svc/

# ── Cause 1: Selector mismatch → patch selector ────────────────────────────────
kubectl -n task20 patch svc task20-svc \
  -p '{"spec":{"selector":{"app":"task20-server"}}}'

# ── Cause 2: Wrong targetPort → patch targetPort ───────────────────────────────
kubectl -n task20 patch svc task20-svc \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'

# ── Cause 3: CoreDNS down → scale back up ─────────────────────────────────────
kubectl -n kube-system scale deployment coredns --replicas=2
kubectl -n kube-system get pods -l k8s-app=kube-dns -w    # wait for Ready

# ── Cause 4: Wrong service port → patch port ───────────────────────────────────
kubectl -n task20 patch svc task20-svc \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/port","value":80}]'

# ── Cause 5: Service in wrong namespace → move it ─────────────────────────────
kubectl -n default delete svc task20-svc
kubectl -n task20 expose pod task20-server \
  --name=task20-svc --port=80 --target-port=80

# ── Verify (all causes) ────────────────────────────────────────────────────────
kubectl -n task20 get endpoints task20-svc
kubectl -n task20 exec task20-client -- nslookup task20-svc
kubectl -n task20 exec task20-client -- wget -qO- http://task20-svc/
# → nginx welcome page output = success
```
