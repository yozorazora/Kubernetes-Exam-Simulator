# Task 07 — Pod Scheduling: nodeSelector
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Schedule a Pod with the following specification:
- Name: `nginx-kusc00401`
- Namespace: `default`
- Image: `nginx:latest`
- Node selector: `disk=ssd`

The Pod must be scheduled on a node that has the label `disk=ssd`.

---

## Additional Information

- One of the worker nodes in the `k8s` cluster already has the label `disk=ssd` (applied during setup).
- You can verify which node has this label:  
  `kubectl get nodes --show-labels | grep disk=ssd`
- If no node has the label, add it:  
  `kubectl label node <node-name> disk=ssd`

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# Quick way using run + dry-run, then edit
kubectl run nginx-kusc00401 --image=nginx $do > /tmp/pod.yaml
# Add nodeSelector to the yaml, then apply
```

Or create directly with YAML:
```yaml
spec:
  nodeSelector:
    disk: ssd
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# Check which node has the label
kubectl get nodes --show-labels | grep disk

# Apply label if needed (the setup script should have done this)
# kubectl label node k8s-worker disk=ssd

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-kusc00401
  namespace: default
spec:
  nodeSelector:
    disk: ssd
  containers:
  - name: nginx
    image: nginx:latest
EOF

# Verify — pod should be Running on the labeled node
kubectl get pod nginx-kusc00401 -o wide
```
