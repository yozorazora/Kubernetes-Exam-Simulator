# Task 09 — Deployment: Scale, Resource Limits, and Rollout
**Weight: 5%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Work with the existing Deployment **`presentation`** in namespace **`ckad`**:

---

**Part A — Scale and set resource limits:**

- Scale the Deployment to **`3`** replicas
- Set the following resource configuration on the container:
  - CPU request: `100m` | Memory request: `128Mi`
  - CPU limit: `200m` | Memory limit: `256Mi`

---

**Part B — Perform a rolling update:**

Update the container image to **`nginx:1.27.2-alpine`**.

- The update must use a rolling strategy (default — do not change it)
- Verify the rollout completes successfully

---

**Part C — Roll back to the previous version:**

Roll the Deployment back to the **previous revision** (the one before the image update).

- Use `kubectl rollout undo`
- Verify the image has been restored to `nginx:latest`

---

## Key Concepts

```
Deployment Rollout Lifecycle:
  kubectl set image  →  new ReplicaSet created  →  pods gradually replaced
  kubectl rollout status  →  watch progress
  kubectl rollout history  →  show all revisions
  kubectl rollout undo    →  revert to previous revision
  kubectl rollout undo --to-revision=N  →  revert to specific revision

  Revisions are only tracked if the deployment has:
    spec.revisionHistoryLimit > 0  (default: 10)
```

---

## Additional Information

- The Deployment `presentation` is pre-created in namespace `ckad`.
- You can check rollout history at any time:
  ```bash
  kubectl rollout history deployment presentation -n ckad
  ```
- After `undo`, the revision that was undone becomes the latest revision in history.

---

## Hint

<details>
<summary>Click to expand</summary>

**Part A:**
```bash
kubectl scale deployment presentation -n ckad --replicas=3
kubectl set resources deployment presentation -n ckad \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi
```

**Part B:**
```bash
kubectl set image deployment/presentation nginx=nginx:1.27.2-alpine -n ckad
kubectl rollout status deployment/presentation -n ckad
```

**Part C:**
```bash
kubectl rollout history deployment/presentation -n ckad   # see revisions
kubectl rollout undo deployment/presentation -n ckad       # revert to previous
kubectl rollout status deployment/presentation -n ckad    # wait for completion
kubectl get deployment presentation -n ckad -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should show nginx:latest
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Part A: Scale + resource limits ──────────────────────────────────────────

kubectl scale deployment presentation -n ckad --replicas=3

kubectl set resources deployment presentation -n ckad \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi

# Verify
kubectl get deployment presentation -n ckad
kubectl describe deployment presentation -n ckad | grep -A8 Resources

# ── Part B: Rolling update (new image) ───────────────────────────────────────

kubectl set image deployment/presentation \
  nginx=nginx:1.27.2-alpine -n ckad

# Watch the rollout
kubectl rollout status deployment/presentation -n ckad

# Check history — should show revision 2
kubectl rollout history deployment/presentation -n ckad

# ── Part C: Roll back to previous revision ────────────────────────────────────

kubectl rollout undo deployment/presentation -n ckad

# Wait for rollback to complete
kubectl rollout status deployment/presentation -n ckad

# Verify — image should be back to nginx:latest
kubectl get deployment presentation -n ckad \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
