# Task 02 — NetworkPolicy: Restrict Ingress by Namespace
**Weight: 8%** | **Cluster: hk8s**

---

## Task

```
kubectl config use-context hk8s
```

Create a new **NetworkPolicy** named `allow-port-from-namespace` in the existing namespace `fubar`.

Ensure that the new NetworkPolicy allows Pods in namespace `internal` to connect to **port 9000** of Pods in namespace `fubar`.

Further ensure that the new NetworkPolicy:
- Does **NOT** allow access to Pods in `fubar` that are not listening on port **9000**
- Does **NOT** allow access from Pods that are **not** in namespace `internal`

---

## Additional Information

- The namespace `fubar` already exists.
- The namespace `internal` already exists.
- The NetworkPolicy should use a `namespaceSelector` matching the namespace label `kubernetes.io/metadata.name: internal`.

---

## Hint

<details>
<summary>Click to expand</summary>

NetworkPolicy with `namespaceSelector` to allow only pods from a specific namespace.
The key fields: `podSelector` (empty = all pods in fubar), `namespaceSelector` (label match internal), `ports` (TCP 9000).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-port-from-namespace
  namespace: fubar
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: internal
    ports:
    - protocol: TCP
      port: 9000
```

</details>

---

## Answer

```bash
kubectl config use-context hk8s

# Create namespaces if they don't exist
kubectl create namespace fubar 2>/dev/null || true
kubectl create namespace internal 2>/dev/null || true

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-port-from-namespace
  namespace: fubar
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: internal
    ports:
    - protocol: TCP
      port: 9000
EOF

# Verify
kubectl get networkpolicy allow-port-from-namespace -n fubar -o yaml
```

**Important note:** `podSelector: {}` means the policy applies to ALL pods in the `fubar` namespace. The ingress rule only allows traffic from pods in namespace `internal` on port `9000` — all other traffic is implicitly denied.
