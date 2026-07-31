# Task 23 — kubectl JSONPath and Custom Columns
**Weight: 3%** | **Cluster: k8s**

---

## Task

```
kubectl config use-context k8s
```

Use `kubectl` with JSONPath and custom-columns to extract information and save it to files. Complete all four queries:

---

**Query 1 — Node Internal IPs:**

Get the `InternalIP` address of **every node** in the cluster.  
Save one IP per line to: `/tmp/task23-node-ips.txt`

---

**Query 2 — Pod names in kube-system:**

Get the **name** of every pod running in the `kube-system` namespace.  
Save space-separated names to: `/tmp/task23-kube-system-pods.txt`

---

**Query 3 — kube-apiserver image:**

Get the **full container image** (including tag) used by the `kube-apiserver` static pod in namespace `kube-system`.  
Save to: `/tmp/task23-apiserver-image.txt`

> Tip: the pod name is `kube-apiserver-k8s-control-plane`

---

**Query 4 — Pod name + status table:**

Using `custom-columns`, output a table with two columns — `NAME` and `STATUS` — for all pods in the `kube-system` namespace.  
Save to: `/tmp/task23-pod-status.txt`

---

## JSONPath Reference

```
┌────────────────────────────────────────────────────────────────────────┐
│  Syntax                          │  Meaning                           │
│  ──────────────────────────────  │  ────────────────────────────────  │
│  .metadata.name                  │  field access                      │
│  .items[*].metadata.name         │  all items in list                 │
│  .items[0].spec.containers[0]    │  first element                     │
│  ?(@.type=="InternalIP")         │  filter expression                 │
│  {range .items[*]}{.field}{"\n"}{end}  │  range with newline         │
└────────────────────────────────────────────────────────────────────────┘

Object structure for a pod:
  .metadata.name                  → pod name
  .metadata.namespace             → namespace
  .status.phase                   → Running / Pending / Failed
  .spec.containers[0].image       → first container image
  .status.podIP                   → pod IP
  .spec.nodeName                  → which node it runs on

Object structure for a node:
  .metadata.name                  → node name
  .status.addresses               → array: [{type, address}, ...]
  .status.conditions              → array: [{type, status}, ...]
  .status.nodeInfo.kubeletVersion → kubelet version
```

**Two ways to use JSONPath:**

```bash
# -o jsonpath    →  prints raw output, no headers
kubectl get pods -o jsonpath='{.items[*].metadata.name}'

# -o jsonpath-template with range → one item per line
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

# -o custom-columns  →  tabular output with headers
kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'

# -o go-template (alternate)
kubectl get pod mypod -o go-template='{{.spec.containers | len}}'
```

**Filter by field value (JSONPath filter):**
```bash
# Get only InternalIP (not Hostname or ExternalIP)
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
```

---

## Hint

<details>
<summary>Click to expand</summary>

**Query 1 — InternalIP with filter + newlines:**
```bash
kubectl get nodes \
  -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' \
  > /tmp/task23-node-ips.txt
```

**Query 2 — Pod names:**
```bash
kubectl -n kube-system get pods \
  -o jsonpath='{.items[*].metadata.name}' \
  > /tmp/task23-kube-system-pods.txt
```

**Query 3 — Image:**
```bash
kubectl -n kube-system get pod kube-apiserver-k8s-control-plane \
  -o jsonpath='{.spec.containers[0].image}' \
  > /tmp/task23-apiserver-image.txt
```

**Query 4 — Custom columns:**
```bash
kubectl -n kube-system get pods \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' \
  > /tmp/task23-pod-status.txt
```

</details>

---

## Answer

```bash
kubectl config use-context k8s

# ── Query 1: InternalIP of all nodes ─────────────────────────────────────────
kubectl get nodes \
  -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' \
  > /tmp/task23-node-ips.txt

cat /tmp/task23-node-ips.txt
# Expected: one IP address per line (e.g. 172.18.0.2, 172.18.0.3)

# ── Query 2: Pod names in kube-system ────────────────────────────────────────
kubectl -n kube-system get pods \
  -o jsonpath='{.items[*].metadata.name}' \
  > /tmp/task23-kube-system-pods.txt

cat /tmp/task23-kube-system-pods.txt

# ── Query 3: kube-apiserver image ────────────────────────────────────────────
kubectl -n kube-system get pod kube-apiserver-k8s-control-plane \
  -o jsonpath='{.spec.containers[0].image}' \
  > /tmp/task23-apiserver-image.txt

cat /tmp/task23-apiserver-image.txt
# Expected: registry.k8s.io/kube-apiserver:v1.32.x

# ── Query 4: Custom columns table ────────────────────────────────────────────
kubectl -n kube-system get pods \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' \
  > /tmp/task23-pod-status.txt

cat /tmp/task23-pod-status.txt
# Expected: table with NAME and STATUS columns

# ── Bonus: useful combinations ────────────────────────────────────────────────

# Sort nodes by name with their IPs
kubectl get nodes -o custom-columns='NODE:.metadata.name,IP:.status.addresses[0].address,VERSION:.status.nodeInfo.kubeletVersion'

# Get all Running pods across all namespaces
kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}'

# Get a specific field from a named resource
kubectl get pod kube-apiserver-k8s-control-plane -n kube-system \
  -o jsonpath='{.metadata.creationTimestamp}'
```
