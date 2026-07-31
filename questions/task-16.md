# Task 16 — StorageClass + PVC
**Weight: 6%** | **Cluster: wk8s**

---

## Task

```
kubectl config use-context wk8s
```

### Part A — Create a StorageClass

Create a **StorageClass** named **`delayed-volume-sc`** with:
- Provisioner: `kubernetes.io/no-provisioner`
- Volume binding mode: `WaitForFirstConsumer`

### Part B — Create a PersistentVolumeClaim

Create a **PersistentVolumeClaim** named **`delayed-volume-pvc`** in namespace **`default`** with:
- Storage request: `1Gi`
- Access mode: `ReadWriteOnce`
- StorageClass: `delayed-volume-sc`

---

## Additional Information

- `WaitForFirstConsumer` means the PVC will remain in `Pending` state until a Pod that uses it is scheduled — this is normal behavior.
- The PVC will show `Pending` after creation (not `Bound`) — that is correct.

---

## Hint

<details>
<summary>Click to expand</summary>

```yaml
# StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: delayed-volume-sc
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer

---
# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: delayed-volume-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: delayed-volume-sc
  resources:
    requests:
      storage: 1Gi
```

</details>

---

## Answer

```bash
kubectl config use-context wk8s

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: delayed-volume-sc
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: delayed-volume-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: delayed-volume-sc
  resources:
    requests:
      storage: 1Gi
EOF

# Verify
kubectl get storageclass delayed-volume-sc
kubectl get pvc delayed-volume-pvc
# PVC status will be "Pending" — this is EXPECTED with WaitForFirstConsumer
```
