# Task 27 — Gateway API
**Weight: 6%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

> **Note:** The Gateway API CRDs must be installed before starting. Run the setup command below if they are not present:
> ```bash
> kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || \
>   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
> ```

---

**Part A — Create a backend application:**

Create namespace `task27`, then deploy:
- Pod **`task27-server`** (image: `nginx:latest`, label: `app=task27-server`)
- Service **`task27-svc`** (ClusterIP, port 80 → targetPort 80, selector: `app=task27-server`)

---

**Part B — Create a GatewayClass:**

Create a `GatewayClass` named **`task27-gwc`** with:
- `controllerName: example.com/task27-controller`

---

**Part C — Create a Gateway:**

Create a `Gateway` named **`task27-gateway`** in namespace **`task27`** with:
- `gatewayClassName: task27-gwc`
- One listener named `http` on port `80` with protocol `HTTP`
- `allowedRoutes.namespaces.from: Same` (only allow HTTPRoutes from the same namespace)

---

**Part D — Create an HTTPRoute:**

Create an `HTTPRoute` named **`task27-route`** in namespace **`task27`** that:
- Attaches to `task27-gateway` (parentRef)
- Routes ALL traffic (no path filter) to Service `task27-svc` on port `80`

---

## Key Concepts

```
Gateway API hierarchy:
  GatewayClass (cluster-scoped)
     ↓  defines the controller type (who implements the gateway)
  Gateway (namespaced)
     ↓  defines listeners (protocol, port, TLS)
  HTTPRoute / TLSRoute / TCPRoute (namespaced)
     ↓  defines routing rules → which backend Service to send to

Gateway API vs Ingress:
  Ingress          →  older, limited to HTTP/HTTPS, one resource does it all
  Gateway API      →  richer role separation, supports TCP/UDP/gRPC,
                      multi-team (infra team manages GatewayClass+Gateway,
                      app team manages HTTPRoute)

  Gateway API is the intended long-term replacement for Ingress.
  Ingress is NOT removed — both co-exist.

API versions (v1.35):
  GatewayClass  →  gateway.networking.k8s.io/v1
  Gateway       →  gateway.networking.k8s.io/v1
  HTTPRoute     →  gateway.networking.k8s.io/v1

Status note:
  Without a real gateway controller installed, the Gateway will show
  status Condition: Programmed=False.
  This is expected in the simulator — resource creation is what's tested.
```

---

## Hint

<details>
<summary>Click to expand</summary>

**GatewayClass:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: task27-gwc
spec:
  controllerName: example.com/task27-controller
```

**Gateway listener block:**
```yaml
spec:
  gatewayClassName: task27-gwc
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
```

**HTTPRoute parentRef + backend:**
```yaml
spec:
  parentRefs:
  - name: task27-gateway
    namespace: task27
  rules:
  - backendRefs:
    - name: task27-svc
      port: 80
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Ensure Gateway API CRDs are installed
kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || \
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# ── Part A: Backend application ───────────────────────────────────────────────

kubectl create namespace task27 --dry-run=client -o yaml | kubectl apply -f -

kubectl run task27-server \
  --image=nginx:latest \
  --labels="app=task27-server" \
  -n task27

kubectl expose pod task27-server \
  --name=task27-svc \
  --port=80 \
  --target-port=80 \
  -n task27

# ── Part B: GatewayClass ──────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: task27-gwc
spec:
  controllerName: example.com/task27-controller
  description: "Task 27 gateway class"
EOF

# ── Part C: Gateway ───────────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: task27-gateway
  namespace: task27
spec:
  gatewayClassName: task27-gwc
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
EOF

# ── Part D: HTTPRoute ─────────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: task27-route
  namespace: task27
spec:
  parentRefs:
  - name: task27-gateway
    namespace: task27
  rules:
  - backendRefs:
    - name: task27-svc
      port: 80
EOF

# ── Verify all resources ──────────────────────────────────────────────────────

kubectl get gatewayclass task27-gwc
kubectl get gateway task27-gateway -n task27
kubectl get httproute task27-route -n task27
kubectl get svc task27-svc -n task27
kubectl get pod task27-server -n task27
```
