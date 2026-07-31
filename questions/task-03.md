# Task 03 — Logging Sidecar
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

An existing Pod named **`legacy-app`** is running in namespace **`audit`**.

**Without changing its existing containers**, add a sidecar container named **`sidecar`** to the Pod using image **`busybox:1.36`**.

The sidecar container must run the following command:
```
/bin/sh -c 'tail -f /var/log/legacy-app.log'
```

The sidecar container must mount the **same volume** that the existing container already uses, at `mountPath: /var/log`.

---

## Additional Information

- The existing Pod `legacy-app` already has a volume defined — find its name using `kubectl get pod legacy-app -n audit -o yaml`
- You cannot modify a running Pod in place (containers are immutable). The approach is:
  1. Export the Pod spec to a YAML file
  2. Add the sidecar container
  3. Delete the old Pod
  4. Apply the new YAML

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# Step 1: Get the existing pod YAML
kubectl get pod legacy-app -n audit -o yaml > /tmp/legacy-app.yaml

# Step 2: Find the volume name (look under spec.volumes)
# Usually something like: name: varlog

# Step 3: Edit the file — add sidecar under spec.containers
# - name: sidecar
#   image: busybox:1.36
#   command: ["/bin/sh", "-c", "tail -f /var/log/legacy-app.log"]
#   volumeMounts:
#   - name: <volume-name>
#     mountPath: /var/log

# Step 4: Delete the old pod and apply new one
kubectl delete pod legacy-app -n audit
kubectl apply -f /tmp/legacy-app.yaml
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Export current pod spec
kubectl get pod legacy-app -n audit -o yaml > /tmp/legacy-app.yaml

# Edit — remove managedFields, status, and add the sidecar container
# The file should have the sidecar added under spec.containers:
# - name: sidecar
#   image: busybox:1.36
#   command: ["/bin/sh", "-c", "tail -f /var/log/legacy-app.log"]
#   volumeMounts:
#   - name: varlog    # <-- use the volume name from spec.volumes
#     mountPath: /var/log

# Delete old pod and re-apply
kubectl delete pod legacy-app -n audit --force --grace-period=0
kubectl apply -f /tmp/legacy-app.yaml

# Verify both containers are running
kubectl get pod legacy-app -n audit
kubectl logs legacy-app -n audit -c sidecar
```
