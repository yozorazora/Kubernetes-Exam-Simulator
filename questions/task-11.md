# Task 11 — Multi-container Pod with Init Container
**Weight: 8%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Create a Pod named **`kucc8`** in the **`default`** namespace with the following specification:

**Init container:**
- Name: `init-cont`
- Image: `busybox:1.36`
- Command: `/bin/sh -c "echo Initializing... > /workdir/data.txt"`
- Volume mount: name `workdir`, mountPath `/workdir`

**Container 1:**
- Name: `c1`
- Image: `nginx:latest`
- Volume mount: name `workdir`, mountPath `/workdir`

**Container 2:**
- Name: `c2`
- Image: `memcached:latest`

**Shared volume:**
- Name: `workdir`
- Type: `emptyDir`

---

## Additional Information

- Init containers run to completion **before** the main containers start.
- All three containers (init + 2 main) must share access to the `workdir` volume.
- The pod should reach `Running` state (init container will complete first, then both c1 and c2 start).

---

## Hint

<details>
<summary>Click to expand</summary>

```yaml
spec:
  initContainers:
  - name: init-cont
    image: busybox:1.36
    command: ["/bin/sh", "-c", "echo Initializing... > /workdir/data.txt"]
    volumeMounts:
    - name: workdir
      mountPath: /workdir
  containers:
  - name: c1
    image: nginx:latest
    volumeMounts:
    - name: workdir
      mountPath: /workdir
  - name: c2
    image: memcached:latest
  volumes:
  - name: workdir
    emptyDir: {}
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: kucc8
  namespace: default
spec:
  initContainers:
  - name: init-cont
    image: busybox:1.36
    command: ["/bin/sh", "-c", "echo Initializing... > /workdir/data.txt"]
    volumeMounts:
    - name: workdir
      mountPath: /workdir
  containers:
  - name: c1
    image: nginx:latest
    volumeMounts:
    - name: workdir
      mountPath: /workdir
  - name: c2
    image: memcached:latest
  volumes:
  - name: workdir
    emptyDir: {}
EOF

# Verify
kubectl get pod kucc8
kubectl describe pod kucc8

# Check init ran and file exists
kubectl exec kucc8 -c c1 -- cat /workdir/data.txt
```
