# Task 01 — RBAC: ClusterRole + RoleBinding
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Create a new **ClusterRole** named `deployment-clusterrole` that only allows **create** operations on the following resource types:
- `Deployment`
- `StatefulSet`
- `DaemonSet`

Create a new **ServiceAccount** named `cicd-token` in the existing namespace `app-team`.

Bind the new ClusterRole `deployment-clusterrole` to the new ServiceAccount `cicd-token`, **limited to the namespace `app-team`** (use a RoleBinding, not a ClusterRoleBinding).

---

## Additional Information

- The namespace `app-team` already exists.
- Use a **RoleBinding** (not ClusterRoleBinding) so the permissions are scoped to `app-team` only.
- The ClusterRole itself is cluster-scoped (which is normal — it can be bound in any namespace).

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
# Create the ClusterRole
kubectl create clusterrole deployment-clusterrole \
  --verb=create \
  --resource=deployments,statefulsets,daemonsets

# Create the ServiceAccount
kubectl create serviceaccount cicd-token -n app-team

# Create a RoleBinding (namespace-scoped, binds the ClusterRole in app-team)
kubectl create rolebinding cicd-token-binding \
  --clusterrole=deployment-clusterrole \
  --serviceaccount=app-team:cicd-token \
  -n app-team
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

kubectl create clusterrole deployment-clusterrole \
  --verb=create \
  --resource=deployments,statefulsets,daemonsets

kubectl create serviceaccount cicd-token -n app-team

kubectl create rolebinding deploy-rb \
  --clusterrole=deployment-clusterrole \
  --serviceaccount=app-team:cicd-token \
  --namespace=app-team

# Verify
kubectl auth can-i create deployments \
  --as=system:serviceaccount:app-team:cicd-token \
  --namespace=app-team
# Expected: yes

kubectl auth can-i delete deployments \
  --as=system:serviceaccount:app-team:cicd-token \
  --namespace=app-team
# Expected: no
```
