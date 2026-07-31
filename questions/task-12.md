# Task 12 — Troubleshoot: Fix Broken Deployment
**Weight: 7%** | **Cluster: bk8s**

---

## Task

```
kubectl config use-context bk8s
```

A Deployment named **`nginx-deployment`** in namespace **`default`** has **0 available pods** due to a misconfiguration.

Investigate the deployment and fix it so that it has **3 available pods** running.

---

## Additional Information

- Do NOT delete and recreate the deployment — fix the existing one.
- The deployment was intended to run `nginx:latest`.
- Check the deployment description and pod events for clues.

---

## Investigation Steps

```bash
# Check deployment status
kubectl get deployment nginx-deployment -n default

# Check pod status (look for errors)
kubectl get pods -n default

# Describe a failing pod (look at Events section)
kubectl describe pod <pod-name> -n default

# Check deployment spec for issues
kubectl describe deployment nginx-deployment -n default
kubectl get deployment nginx-deployment -o yaml
```

Common issues to look for:
1. Wrong/non-existent image name (ImagePullBackOff / ErrImagePull)
2. Missing ConfigMap or Secret that the pod requires
3. Resource requests exceeding node capacity
4. Wrong image pull policy
5. Wrong container port or probe configuration

---

## Hint

<details>
<summary>Click to expand</summary>

The deployment uses an image name that doesn't exist (e.g., `nginx:does-not-exist`).

```bash
# Fix the image
kubectl set image deployment/nginx-deployment nginx=nginx:latest -n default

# Or edit directly
kubectl edit deployment nginx-deployment -n default
# Change the image field to: nginx:latest
```

</details>

---

## Answer

```bash
kubectl config use-context bk8s

# 1. Diagnose
kubectl get pods -n default
# You'll see pods in ImagePullBackOff or ErrImagePull state

kubectl describe pod -l app=nginx-deployment -n default | grep -A 5 Events

# 2. Find the bad image
kubectl get deployment nginx-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].image}'

# 3. Fix it
kubectl set image deployment/nginx-deployment nginx=nginx:latest -n default

# 4. Wait for rollout
kubectl rollout status deployment/nginx-deployment -n default

# 5. Verify — 3 pods running
kubectl get deployment nginx-deployment -n default
kubectl get pods -n default
```
