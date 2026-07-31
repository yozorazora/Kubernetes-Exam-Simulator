# CKA Exam Simulator

A local Kubernetes CKA (Certified Kubernetes Administrator) exam simulator that closely mirrors the [Linux Foundation CKA exam](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) environment.

- **28 performance-based tasks** covering all 5 CKA exam domains
- **4 clusters** — same context names as the real exam (`k8s`, `hk8s`, `bk8s`, `wk8s`)
- **Timed exam mode** — 2-hour countdown with terminal title bar timer
- **Practice mode** — work individual tasks at your own pace with hints and reference answers
- **Multi-cause troubleshooting** — Tasks 17–20 each inject specific failures for you to diagnose and fix
- **Answer verification** — per-task scripts check your actual cluster state
- **Kubernetes v1.35** — aligned with 2026 CKA exam curriculum

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **WSL2** (Ubuntu 22.04+) | CKA exam uses Linux — practice in Linux |
| **Docker Desktop** | Enable WSL2 integration in Settings → Resources → WSL Integration |
| **8 GB+ RAM** | 4 clusters with multiple nodes |
| **Python 3** | Used by verification scripts |
| **Helm v3** | Required for Task 24 — install from https://helm.sh/docs/intro/install/ |

> **First time here?** See **[INSTALL.md](INSTALL.md)** for full step-by-step setup on Windows (WSL2) or macOS, including required Homebrew packages for Mac.

---

## Quick Start

```bash
# 1. Navigate to the simulator directory (in WSL2 terminal)
cd /mnt/c/Users/yozor/Desktop/cka-simulator

# 2. Run setup (installs kind, kubectl, etcdctl; creates 4 clusters)
bash setup.sh

# 3. Load the exam environment (aliases, KUBECONFIG)
source .exam-env

# 4a. Start a timed 2-hour exam (28 tasks)
bash start-exam.sh

# 4b. OR: Practice individual tasks (no timer)
bash practice.sh
```

---

## Clusters

| Context | Description | Used For |
|---------|-------------|----------|
| `k8s` | Main cluster (1 CP + 2 workers) | Most tasks |
| `hk8s` | HA cluster (3 CPs + 1 worker) | NetworkPolicy |
| `bk8s` | Broken cluster (1 CP + 1 worker) | Troubleshooting tasks |
| `wk8s` | Worker cluster (1 CP + 2 workers) | Storage, networking, drain |

Always set the context before starting each task:
```bash
kubectl config use-context k8s
```

---

## All 28 Tasks

### Domain: Cluster Architecture, Installation & Configuration (25%)

| Task | Weight | Cluster | Topic |
|------|--------|---------|-------|
| 01 | 4% | k8s | RBAC — ClusterRole + RoleBinding |
| 04 | 8% | wk8s | Cluster Upgrade v1.34 → v1.35 via kubeadm |
| 05 | 5% | k8s | etcd Backup and Restore |
| 10 | 4% | wk8s | Node Drain and Uncordon |
| 14 | 4% | k8s | ServiceAccount with ClusterRoleBinding |
| 24 | 4% | k8s | Helm Fundamentals |
| 25 | 4% | k8s | Custom Resource Definitions (CRDs) |

### Domain: Workloads & Scheduling (15%)

| Task | Weight | Cluster | Topic |
|------|--------|---------|-------|
| 03 | 4% | k8s | Logging Sidecar — add sidecar to existing pod |
| 07 | 4% | k8s | Pod Scheduling — nodeSelector |
| 09 | 5% | k8s | Deployment — Scale, Resources, Rollout & Rollback |
| 11 | 8% | k8s | Multi-container Pod with Init Container |
| 13 | 4% | k8s | ResourceQuota |
| 15 | 6% | k8s | ConfigMaps and Secrets (env vars + volume mount) |
| 21 | 4% | k8s | Taints and Tolerations |
| 22 | 4% | k8s | Job and CronJob |
| 26 | 3% | k8s | DaemonSet |
| 28 | 4% | k8s | Horizontal Pod Autoscaler (HPA) |

### Domain: Services & Networking (20%)

| Task | Weight | Cluster | Topic |
|------|--------|---------|-------|
| 02 | 8% | hk8s | NetworkPolicy — restrict ingress by namespace |
| 08 | 6% | k8s | Ingress — expose service via Ingress resource |
| 27 | 6% | k8s | Gateway API — GatewayClass, Gateway, HTTPRoute |

### Domain: Storage (10%)

| Task | Weight | Cluster | Topic |
|------|--------|---------|-------|
| 06 | 4% | wk8s | PersistentVolume + PersistentVolumeClaim |
| 16 | 6% | wk8s | StorageClass + PVC |

### Domain: Troubleshooting (30%)

| Task | Weight | Cluster | Topic | Causes |
|------|--------|---------|-------|--------|
| 12 | 7% | bk8s | Troubleshoot — fix broken Deployment | — |
| 17 | 14% | bk8s | Troubleshoot — worker node NotReady | 5 causes |
| 18 | 10% | k8s | Troubleshoot — Pod Not Running | 10 causes |
| 19 | 10% | bk8s | Troubleshoot — Control Plane Components | 4 causes |
| 20 | 6% | k8s | Troubleshoot — Service & DNS Debugging | 5 causes |

### Cross-Cutting Skills

| Task | Weight | Cluster | Topic |
|------|--------|---------|-------|
| 23 | 3% | k8s | kubectl JSONPath and Custom Columns |

---

## Multi-Cause Troubleshooting Tasks

Tasks 17–20 use a `cause <N>` command to inject a specific failure. Practice each cause independently then run `check` to verify your fix.

### Task 17 — Node NotReady (5 causes)

| Cause | Failure | Key Command |
|-------|---------|-------------|
| 1 | kubelet service stopped | `systemctl start kubelet` |
| 2 | containerd stopped | `systemctl start containerd` |
| 3 | kubelet config file corrupt | `systemctl restart kubelet` after fixing config |
| 4 | TLS certificate expired | regenerate or restore cert |
| 5 | Disk full (2 GB fill file) | remove the fill file |

### Task 18 — Pod Not Running (10 causes)

| Cause | Failure | Symptom |
|-------|---------|---------|
| 1 | CPU request = 99 | Pod Pending |
| 2 | Image typo `ngiinx:latest` | ImagePullBackOff |
| 3 | Container exits immediately | CrashLoopBackOff |
| 4 | ConfigMap volume doesn't exist | FailedMount |
| 5 | envFrom ConfigMap missing | CreateContainerConfigError |
| 6 | envFrom Secret missing | CreateContainerConfigError |
| 7 | PVC on invalid StorageClass | PVC Pending → Pod Pending |
| 8 | Readiness probe on wrong port | Running but 0/1 Ready |
| 9 | Liveness probe always fails | Restart loop, Exit Code 137 |
| 10 | Image tag `nginx:9999` | ErrImagePull |

### Task 19 — Control Plane (4 causes)

| Cause | Failure | Investigation |
|-------|---------|---------------|
| 1 | kube-apiserver bad flag | kubectl stops working — use `crictl` |
| 2 | kube-scheduler bad kubeconfig | scheduler pod CrashLoops |
| 3 | controller-manager bad kubeconfig | controller-manager CrashLoops |
| 4 | YAML error in scheduler manifest | scheduler pod disappears entirely |

### Task 20 — Service & DNS (5 causes)

| Cause | Failure | Key Diagnostic |
|-------|---------|----------------|
| 1 | Selector mismatch | `kubectl get endpoints` → `<none>` |
| 2 | Wrong targetPort | Endpoints exist but connection refused |
| 3 | CoreDNS scaled to 0 | All DNS fails cluster-wide |
| 4 | Wrong service port | Client connects to wrong port |
| 5 | Service in wrong namespace | Short DNS name unresolvable |

---

## Practice Mode Commands

```bash
bash practice.sh

# Inside the practice menu:
[1-28]       Open a task
v <N>        Verify task N
hint <N>     Show hint for task N
ans <N>      Show reference answer for task N
r <N>        Reset task N to its original state
q            Quit

# Inside a task shell (tasks 17-20 only):
cause <N>    Inject failure cause N
check        Run the verify script
hint         Show hint
answer       Show reference answer
reset        Reset the scenario
task         Redisplay the task description
back         Exit task shell
```

---

## Verifying Your Work

```bash
# Verify a specific task directly
bash verify/verify-task-07.sh

# Verify all tasks and get a score estimate (exam mode)
bash start-exam.sh   # then type: va

# Reset a task scenario
bash scenarios/reset.sh 17
```

---

## Exam Tips

### Speed shortcuts — set at the start of every session
```bash
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# Enable tab completion
source <(kubectl completion bash)
complete -F __start_kubectl k
```

### Generate YAML instead of typing from scratch
```bash
# Pod
kubectl run mypod --image=nginx $do > pod.yaml

# Deployment
kubectl create deployment mydeploy --image=nginx --replicas=3 $do > deploy.yaml

# Job
kubectl create job myjob --image=busybox $do -- sh -c "echo done" > job.yaml

# CronJob
kubectl create cronjob mycron --image=busybox --schedule="*/1 * * * *" $do > cron.yaml

# ConfigMap
kubectl create configmap myconfig --from-literal=KEY=VALUE $do > cm.yaml

# Secret
kubectl create secret generic mysecret --from-literal=PASS=s3cr3t $do > secret.yaml

# HPA
kubectl autoscale deployment mydeploy --cpu-percent=50 --min=2 --max=5
```

### Rollout commands
```bash
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp
kubectl rollout undo deployment/myapp --to-revision=1
```

### Helm quick reference
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install myrelease bitnami/nginx -n mynamespace --create-namespace
helm upgrade myrelease bitnami/nginx -n mynamespace --set replicaCount=2
helm rollback myrelease 1 -n mynamespace
helm list -n mynamespace
helm history myrelease -n mynamespace
helm uninstall myrelease -n mynamespace
```

### JSONPath output
```bash
# Get all node InternalIPs
kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Get pod image
kubectl get pod mypod -o jsonpath='{.spec.containers[0].image}'

# Custom columns
kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
```

### Troubleshooting cheatsheet
```bash
# Node not ready
kubectl describe node <node>         # check Conditions and Events
docker exec -it <node> bash          # enter the node (kind)
systemctl status kubelet             # check kubelet
journalctl -u kubelet -n 50          # kubelet logs
crictl ps                            # check containers (when apiserver is down)

# Pod issues
kubectl describe pod <pod>           # check Events section
kubectl logs <pod>                   # container logs
kubectl logs <pod> --previous        # logs from crashed container

# Service/DNS issues
kubectl get endpoints <svc>          # check if endpoints are populated
kubectl exec <pod> -- nslookup <svc> # DNS resolution test
kubectl exec <pod> -- wget -qO- http://<svc>/  # HTTP connectivity test
```

### Allowed documentation during real exam
You may use **https://kubernetes.io/docs** and its sub-pages. Bookmark these:
- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [CRDs](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [Helm docs](https://helm.sh/docs/)

### Vim settings (YAML-friendly)
```vim
:set paste
:set nu
:set expandtab
:set tabstop=2
:set shiftwidth=2
```

---

## Resetting Scenarios

```bash
# Reset a single task to its original broken state
bash scenarios/reset.sh 17

# Reset from inside practice mode
bash practice.sh
# → r 17
```

> **Note:** For Tasks 17–20 (multi-cause tasks), reset clears both the active cause and all progress tracking. Use `cause <N>` again to re-inject a failure.

---

## File Structure

```
cka-simulator/
├── setup.sh                        # Install tools + create 4 Kind clusters
├── start-exam.sh                   # Timed exam mode (2 hours, 28 tasks, scored)
├── practice.sh                     # Practice mode (no timer, any task)
├── teardown.sh                     # Delete all clusters and kubeconfig
├── .exam-env                       # Shell aliases + KUBECONFIG (source this)
├── INSTALL.md                      # First-time setup guide (Windows/WSL2 + macOS)
│
├── clusters/
│   ├── k8s.yaml                    # Kind config — main cluster
│   ├── hk8s.yaml                   # Kind config — HA cluster
│   ├── bk8s.yaml                   # Kind config — broken/troubleshoot cluster
│   └── wk8s.yaml                   # Kind config — worker/networking cluster
│
├── lib/
│   └── common.sh                   # Shared: check_pass, check_fail, use_context, verify_summary
│
├── questions/
│   ├── task-01.md                  # RBAC
│   ├── task-02.md                  # NetworkPolicy
│   ├── task-03.md                  # Logging Sidecar
│   ├── task-04.md                  # Cluster Upgrade (v1.34 → v1.35)
│   ├── task-05.md                  # etcd Backup and Restore
│   ├── task-06.md                  # PersistentVolume + PVC
│   ├── task-07.md                  # Pod Scheduling (nodeSelector)
│   ├── task-08.md                  # Ingress
│   ├── task-09.md                  # Deployment — Scale, Resources, Rollout
│   ├── task-10.md                  # Node Drain
│   ├── task-11.md                  # Multi-container + Init Container
│   ├── task-12.md                  # Troubleshoot: broken Deployment
│   ├── task-13.md                  # ResourceQuota
│   ├── task-14.md                  # ServiceAccount + ClusterRoleBinding
│   ├── task-15.md                  # ConfigMaps and Secrets
│   ├── task-16.md                  # StorageClass + PVC
│   ├── task-17.md                  # Troubleshoot: Node NotReady (5 causes)
│   ├── task-18.md                  # Troubleshoot: Pod Not Running (10 causes)
│   ├── task-19.md                  # Troubleshoot: Control Plane (4 causes)
│   ├── task-20.md                  # Troubleshoot: Service & DNS (5 causes)
│   ├── task-21.md                  # Taints and Tolerations
│   ├── task-22.md                  # Job and CronJob
│   ├── task-23.md                  # kubectl JSONPath and Custom Columns
│   ├── task-24.md                  # Helm Fundamentals
│   ├── task-25.md                  # Custom Resource Definitions
│   ├── task-26.md                  # DaemonSet
│   ├── task-27.md                  # Gateway API
│   └── task-28.md                  # Horizontal Pod Autoscaler (HPA)
│
├── verify/
│   ├── verify-task-01.sh ... verify-task-28.sh   # Per-task answer checkers
│
└── scenarios/
    ├── reset.sh                    # Reset any task: bash reset.sh <N>
    ├── init-scenarios.sh           # Pre-load all scenario initial states
    ├── setup-task-17-cause.sh      # Inject Node NotReady failure (5 causes)
    ├── setup-task-18-cause.sh      # Inject Pod failure (10 causes)
    ├── setup-task-19-cause.sh      # Inject Control Plane failure (4 causes)
    └── setup-task-20-cause.sh      # Inject Service/DNS failure (5 causes)
```

---

## Known Limitations vs Real Exam

| Feature | Real Exam | This Simulator |
|---------|-----------|----------------|
| Cluster upgrade (Task 04) | Full `apt` package upgrade | Commands practice only — Kind images are fixed |
| etcd restore (Task 05) | Full etcd restart on bare metal | Requires entering control-plane container |
| PSI browser environment | Remote desktop UI in browser | WSL2 terminal |
| Node access | SSH to exam nodes | `docker exec -it <node> bash` |
| Gateway API routing | Requires a controller running | Resource creation only — controller not installed |
| HPA actual scaling | Requires metrics-server | Spec is verified; scaling behavior not tested |
| Kubernetes version | Exact exam version | v1.35 via Kind (may differ from actual exam at time of sitting) |

For full kubeadm upgrade practice (Task 04), use a Vagrant + VirtualBox setup with real Ubuntu VMs.

---

## 2026 CKA Coverage

| Domain | Exam Weight | Simulator Coverage |
|--------|------------|-------------------|
| Troubleshooting | 30% | ~98% — 27 distinct failure scenarios across 5 tasks |
| Cluster Architecture | 25% | ~90% — RBAC, upgrade, etcd, Helm, CRDs |
| Services & Networking | 20% | ~90% — NetworkPolicy, Ingress, Gateway API, Service debugging |
| Workloads & Scheduling | 15% | ~90% — Deployments, Secrets, Jobs, DaemonSet, HPA, Taints |
| Storage | 10% | ~95% — PV, PVC, StorageClass |
| **Overall** | **100%** | **~92%** |

**Passing score on the real exam: 66%**. Completing all 28 tasks confidently is more than sufficient to pass.

---

## Teardown

```bash
bash teardown.sh
```

Deletes all 4 Kind clusters and removes kubeconfig files.
