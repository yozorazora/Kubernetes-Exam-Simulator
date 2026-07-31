# Task 05 — etcd Backup and Restore
**Weight: 7%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

### Part A — Create a Snapshot

Create a snapshot of the existing **etcd** instance running at `https://127.0.0.1:2379`.

Save the snapshot to: **`/var/lib/backup/etcd-snapshot.db`**

The following TLS certificates/keys are supplied for connecting to etcd:
- CA certificate:     `/etc/kubernetes/pki/etcd/ca.crt`
- Client certificate: `/etc/kubernetes/pki/etcd/server.crt`
- Client key:         `/etc/kubernetes/pki/etcd/server.key`

### Part B — Restore from Snapshot

Restore an existing, previous snapshot located at:  
**`/var/lib/backup/etcd-snapshot-previous.db`**

---

## Additional Information

- `etcdctl` must be used with API version 3:  
  `export ETCDCTL_API=3`
- The backup must be performed **from inside the control-plane node** since that is where etcd runs.
- In kind: `docker exec -it k8s-control-plane bash`
- After restore, you may need to update the etcd static pod manifest to point to the new data directory, then restart the static pod.

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
export ETCDCTL_API=3

# Backup
etcdctl snapshot save /var/lib/backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify snapshot
etcdctl snapshot status /var/lib/backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key -w table

# Restore
etcdctl snapshot restore /var/lib/backup/etcd-snapshot-previous.db \
  --data-dir=/var/lib/etcd-restored
```

After restore, update `/etc/kubernetes/manifests/etcd.yaml`:
- Change `--data-dir` to `/var/lib/etcd-restored`
- Update the `hostPath` volume to `/var/lib/etcd-restored`

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Enter the control-plane node
docker exec -it k8s-control-plane bash

# Inside the node:
export ETCDCTL_API=3

# Create backup directory
mkdir -p /var/lib/backup

# === PART A: Create snapshot ===
etcdctl snapshot save /var/lib/backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Confirm snapshot created
etcdctl snapshot status /var/lib/backup/etcd-snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key -w table

# === PART B: Restore from previous snapshot ===
# Create a previous snapshot to practice restore (in exam it already exists)
cp /var/lib/backup/etcd-snapshot.db /var/lib/backup/etcd-snapshot-previous.db

etcdctl snapshot restore /var/lib/backup/etcd-snapshot-previous.db \
  --data-dir=/var/lib/etcd-restored

# Update etcd static pod manifest
cp /etc/kubernetes/manifests/etcd.yaml /tmp/etcd-backup.yaml
sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-restored|g' /etc/kubernetes/manifests/etcd.yaml
sed -i 's|/var/lib/etcd|/var/lib/etcd-restored|g' /etc/kubernetes/manifests/etcd.yaml

# Wait for etcd to restart (may take 30-60 seconds)
sleep 30
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
```
