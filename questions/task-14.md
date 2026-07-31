# Task 14 — ServiceAccount with ClusterRoleBinding
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Complete the following steps:

1. Create a **ServiceAccount** named **`pvviewer`** in namespace **`default`**.

2. Create a **ClusterRole** named **`pvviewer-role`** that allows `list` operations on `PersistentVolumes`.

3. Create a **ClusterRoleBinding** named **`pvviewer-role-binding`** that binds the ClusterRole `pvviewer-role` to the ServiceAccount `pvviewer`.

4. Create a **Pod** named **`pvviewer`** in namespace `default` using image **`redis:latest`**, configured to use the ServiceAccount `pvviewer`.

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
kubectl create serviceaccount pvviewer

kubectl create clusterrole pvviewer-role \
  --verb=list --resource=persistentvolumes

kubectl create clusterrolebinding pvviewer-role-binding \
  --clusterrole=pvviewer-role \
  --serviceaccount=default:pvviewer

kubectl run pvviewer \
  --image=redis:latest \
  --serviceaccount=pvviewer
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# 1. Create ServiceAccount
kubectl create serviceaccount pvviewer -n default

# 2. Create ClusterRole
kubectl create clusterrole pvviewer-role \
  --verb=list \
  --resource=persistentvolumes

# 3. Create ClusterRoleBinding
kubectl create clusterrolebinding pvviewer-role-binding \
  --clusterrole=pvviewer-role \
  --serviceaccount=default:pvviewer

# 4. Create Pod with the ServiceAccount
kubectl run pvviewer \
  --image=redis:latest \
  --serviceaccount=pvviewer \
  -n default

# Verify
kubectl get pod pvviewer -n default
kubectl get pod pvviewer -o jsonpath='{.spec.serviceAccountName}'

# Test permissions
kubectl auth can-i list persistentvolumes \
  --as=system:serviceaccount:default:pvviewer
# Expected: yes
```
