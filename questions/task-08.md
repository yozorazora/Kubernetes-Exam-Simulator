# Task 08 — Ingress: Expose Service via Ingress Resource
**Weight: 6%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

In the namespace **`ing-internal`**, create an **Ingress** resource named **`pong`** with the following specification:

- Expose the existing Service **`hi`** on port **`5678`**
- Only when requests use path **`/hello`**
- Path type: **`Prefix`**

---

## Additional Information

- The namespace `ing-internal` already exists.
- A Service named `hi` on port `5678` has been pre-created in `ing-internal`.
- No IngressClass name is required — use the default.
- Verify with: `curl -kL http://<node-ip>/hello`

---

## Hint

<details>
<summary>Click to expand</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pong
  namespace: ing-internal
spec:
  rules:
  - http:
      paths:
      - path: /hello
        pathType: Prefix
        backend:
          service:
            name: hi
            port:
              number: 5678
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# First, check the service exists
kubectl get svc hi -n ing-internal

# Create the Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pong
  namespace: ing-internal
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - http:
      paths:
      - path: /hello
        pathType: Prefix
        backend:
          service:
            name: hi
            port:
              number: 5678
EOF

# Verify
kubectl get ingress pong -n ing-internal
kubectl describe ingress pong -n ing-internal
```

> **Note:** For full end-to-end testing in kind, install the NGINX ingress controller:
> ```bash
> kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
> kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
> ```
