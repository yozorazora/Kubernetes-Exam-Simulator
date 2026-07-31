# Task 13 — ResourceQuota
**Weight: 4%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Create a **ResourceQuota** named **`rq-test`** in the existing namespace **`myspace`** with the following limits:

| Resource | Limit |
|----------|-------|
| Pods     | `5`   |
| CPU      | `300m` |
| Memory   | `600Mi` |

---

## Hint

<details>
<summary>Click to expand</summary>

```bash
kubectl create resourcequota rq-test \
  --hard=pods=5,requests.cpu=300m,requests.memory=600Mi \
  -n myspace
```

Or via YAML:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: rq-test
  namespace: myspace
spec:
  hard:
    pods: "5"
    requests.cpu: "300m"
    requests.memory: "600Mi"
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

kubectl create resourcequota rq-test \
  --hard=pods=5,requests.cpu=300m,requests.memory=600Mi \
  -n myspace

# Verify
kubectl get resourcequota rq-test -n myspace
kubectl describe resourcequota rq-test -n myspace
```

Expected output:
```
Name:            rq-test
Namespace:       myspace
Resource         Used  Hard
--------         ----  ----
pods             0     5
requests.cpu     0     300m
requests.memory  0     600Mi
```
