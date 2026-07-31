# Task 06 — PersistentVolume + PersistentVolumeClaim
**Weight: 4%** | **Cluster: wk8s**

---

## Task

```
kubectl config use-context wk8s
```

### Part A — Create a PersistentVolume

Create a **PersistentVolume** with the following specification:
- Name: `app-config`
- Capacity: `2Gi`
- Access mode: `ReadWriteMany`
- Reclaim policy: `Retain`
- Storage class: `""` (empty string — no StorageClass)
- Volume type: `hostPath`
- Path: `/srv/app-config`

### Part B — Create a PersistentVolumeClaim

Create a **PersistentVolumeClaim** with the following specification:
- Name: `pvc-app-config`
- Namespace: `default`
- Access mode: `ReadWriteMany`
- Storage request: `2Gi`
- Storage class: `""` (empty string — disables dynamic provisioning)

---

## Additional Information

- Setting `storageClassName: ""` forces static binding — the PVC will only bind to a PV that has `storageClassName: ""`.
- The PVC should bind to your PV once both are created (status: Bound).

---

## Hint

<details>
<summary>Click to expand</summary>

```yaml
# PersistentVolume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: app-config
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /srv/app-config

---
# PersistentVolumeClaim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-app-config
  namespace: default
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
  storageClassName: ""
```

</details>

---

## Answer

```bash
kubectl config use-context wk8s

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: app-config
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /srv/app-config
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-app-config
  namespace: default
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
  storageClassName: ""
EOF

# Verify — both should show Bound
kubectl get pv app-config
kubectl get pvc pvc-app-config
```
