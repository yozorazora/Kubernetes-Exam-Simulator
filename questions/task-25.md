# Task 25 — Custom Resource Definitions (CRDs)
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

---

**Part A — Create a Custom Resource Definition:**

Create a CRD that defines a new resource type with the following specification:

- **Group:** `storage.example.com`
- **Resource (plural):** `backups`
- **Kind:** `Backup`
- **Scope:** `Namespaced`
- **Version:** `v1`
- **Schema fields in `spec`:**
  - `source` (string) — the source path to back up
  - `retention` (integer) — number of days to retain

---

**Part B — Create a custom resource:**

Create a `Backup` resource named **`daily-backup`** in namespace **`task25`** with:
- `source: /data/postgres`
- `retention: 7`

---

**Part C — List and describe custom resources:**

1. List all `backups` in namespace `task25`
2. Describe `daily-backup`
3. Confirm the CRD is registered cluster-wide with `kubectl get crd`

---

## Key Concepts

```
CRD → Custom Resource Definition
  Extends the Kubernetes API to add your own resource types.
  Once a CRD is registered, your custom resources are treated like
  built-in resources (get, describe, apply, delete all work).

Resource hierarchy:
  CRD (cluster-scoped)         →  defines the type
  Custom Resource (namespaced) →  an instance of that type

API structure:
  apiVersion: <group>/<version>       e.g. storage.example.com/v1
  kind: <Kind>                        e.g. Backup

Why CRDs matter in real clusters:
  - Operators use CRDs to extend Kubernetes with domain logic
  - Prometheus, cert-manager, Istio all register their own CRDs
  - The CKA tests basic CRD creation and custom resource CRUD

Operator pattern (read-only concept for CKA):
  CRD   →  defines schema (what to store)
  Operator/Controller  →  watches CRs and acts on them (the logic)
  For CKA you only need to CREATE and MANAGE CRDs and CRs,
  not build operators.
```

---

## Hint

<details>
<summary>Click to expand</summary>

**CRD YAML structure:**
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: <plural>.<group>      # e.g. backups.storage.example.com
spec:
  group: <group>
  names:
    kind: <Kind>
    plural: <plural>
    singular: <singular>
  scope: Namespaced            # or Cluster
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              <field>:
                type: <string|integer|boolean>
```

**Verify CRD is available:**
```bash
kubectl get crd backups.storage.example.com
kubectl api-resources | grep backup
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: Create the CRD ────────────────────────────────────────────────────

cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.storage.example.com
spec:
  group: storage.example.com
  names:
    kind: Backup
    listKind: BackupList
    plural: backups
    singular: backup
    shortNames:
    - bk
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              source:
                type: string
              retention:
                type: integer
EOF

# Verify CRD is Established
kubectl get crd backups.storage.example.com
kubectl wait crd backups.storage.example.com \
  --for=condition=Established --timeout=30s

# ── Part B: Create a custom resource ─────────────────────────────────────────

kubectl create namespace task25 --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: storage.example.com/v1
kind: Backup
metadata:
  name: daily-backup
  namespace: task25
spec:
  source: /data/postgres
  retention: 7
EOF

# ── Part C: List and verify ───────────────────────────────────────────────────

# List the custom resource
kubectl get backups -n task25
kubectl get bk -n task25     # using short name

# Describe it
kubectl describe backup daily-backup -n task25

# Confirm CRD appears in the cluster-wide list
kubectl get crd | grep storage.example.com

# Check it's in api-resources
kubectl api-resources | grep backup
```
