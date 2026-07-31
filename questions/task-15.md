# Task 15 — ConfigMaps and Secrets
**Weight: 6%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

---

**Part A — Create a ConfigMap:**

Create a ConfigMap named **`ckad-config`** in namespace **`default`** with:
- `EXAM_MODE=CKA`
- `CLUSTER_TYPE=production`

**Part B — Pod using ConfigMap as env vars:**

Create a Pod named **`configmap-pod`** (image: `nginx:latest`, namespace: `default`).  
Inject **all** keys from `ckad-config` as environment variables using `envFrom`.

---

**Part C — Create a Secret:**

Create a Secret named **`ckad-secret`** in namespace **`default`** with:
- `DB_USER=admin`
- `DB_PASSWORD=s3cr3t`

Use type `Opaque` (generic secret).

**Part D — Pod using Secret as env vars AND as a volume:**

Create a Pod named **`secret-pod`** (image: `nginx:latest`, namespace: `default`) that:
1. Injects all keys from `ckad-secret` as environment variables using `envFrom`
2. Mounts `ckad-secret` as a **volume** at path `/etc/secret-data` inside the container

---

## Key Concepts

```
ConfigMap vs Secret:
  ConfigMap  →  plain text, base64-NOT encoded in etcd, for config data
  Secret     →  base64-encoded at rest, for passwords/tokens/keys

Two ways to use each in a Pod:
  envFrom  →  all keys become env vars (bulk load)
  env[].valueFrom.{configMapKeyRef|secretKeyRef}  →  individual key selection

  volumes + volumeMounts  →  each key becomes a FILE at the mount path
    /etc/secret-data/DB_USER     ← file content: admin
    /etc/secret-data/DB_PASSWORD ← file content: s3cr3t
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Parts A + B:**
```bash
kubectl create configmap ckad-config \
  --from-literal=EXAM_MODE=CKA \
  --from-literal=CLUSTER_TYPE=production

# Pod spec uses envFrom:
#   envFrom:
#   - configMapRef:
#       name: ckad-config
```

**Part C:**
```bash
# Method 1 — imperative
kubectl create secret generic ckad-secret \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD=s3cr3t

# Verify values (they are base64-encoded in storage)
kubectl get secret ckad-secret -o jsonpath='{.data.DB_USER}' | base64 -d
```

**Part D — Secret as both env and volume:**
```yaml
spec:
  containers:
  - name: nginx
    image: nginx:latest
    envFrom:
    - secretRef:
        name: ckad-secret
    volumeMounts:
    - name: secret-vol
      mountPath: /etc/secret-data
      readOnly: true
  volumes:
  - name: secret-vol
    secret:
      secretName: ckad-secret
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: ConfigMap ─────────────────────────────────────────────────────────

kubectl create configmap ckad-config \
  --from-literal=EXAM_MODE=CKA \
  --from-literal=CLUSTER_TYPE=production \
  -n default

# ── Part B: Pod using ConfigMap ───────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
    envFrom:
    - configMapRef:
        name: ckad-config
EOF

# Verify
kubectl exec configmap-pod -- env | grep -E "EXAM_MODE|CLUSTER_TYPE"

# ── Part C: Secret ────────────────────────────────────────────────────────────

kubectl create secret generic ckad-secret \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD=s3cr3t \
  -n default

# Verify secret stored correctly
kubectl get secret ckad-secret -o jsonpath='{.data.DB_USER}' | base64 -d
# Expected: admin

# ── Part D: Pod using Secret as env + volume ──────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-pod
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
    envFrom:
    - secretRef:
        name: ckad-secret
    volumeMounts:
    - name: secret-vol
      mountPath: /etc/secret-data
      readOnly: true
  volumes:
  - name: secret-vol
    secret:
      secretName: ckad-secret
EOF

# Verify env vars visible inside pod
kubectl exec secret-pod -- env | grep -E "DB_USER|DB_PASSWORD"
# Expected:
# DB_USER=admin
# DB_PASSWORD=s3cr3t

# Verify volume files
kubectl exec secret-pod -- ls /etc/secret-data
# Expected: DB_PASSWORD  DB_USER

kubectl exec secret-pod -- cat /etc/secret-data/DB_USER
# Expected: admin
```
