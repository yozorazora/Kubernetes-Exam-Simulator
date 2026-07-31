# Task 10 — Node Drain and Uncordon
**Weight: 4%** | **Cluster: wk8s**

---

## Task

```
kubectl config use-context wk8s
```

A maintenance window has been scheduled for the worker node **`wk8s-worker`**.

**Step 1:** Mark the node `wk8s-worker` as **unschedulable** and **evict all running pods** from it.

**Step 2:** After completing the above, make the node **schedulable** again.

---

## Additional Information

- You must use `kubectl drain` — it both cordons AND evicts pods.
- DaemonSet-managed pods cannot be evicted; use `--ignore-daemonsets`.
- Pods using `emptyDir` volumes may need `--delete-emptydir-data` to force eviction.
- After drain, uncordon the node using `kubectl uncordon`.

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# Drain (evict all pods + cordon)
kubectl drain wk8s-worker --ignore-daemonsets --delete-emptydir-data

# Later — make schedulable again
kubectl uncordon wk8s-worker
```

</details>

---

## Answer

```bash
kubectl config use-context wk8s

# Check current node status
kubectl get nodes

# Step 1: Drain the node
kubectl drain wk8s-worker \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force

# Verify — node should show SchedulingDisabled
kubectl get nodes

# Check no regular pods are running on the drained node
kubectl get pods -A -o wide | grep wk8s-worker

# Step 2: Uncordon — make it schedulable again
kubectl uncordon wk8s-worker

# Verify — node should show Ready
kubectl get nodes
```

> **Difference between cordon and drain:**
> - `kubectl cordon <node>` — marks node unschedulable (new pods won't be scheduled here), but existing pods keep running
> - `kubectl drain <node>` — cordons the node AND evicts all pods (except DaemonSet pods)
