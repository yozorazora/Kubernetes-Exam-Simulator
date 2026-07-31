# Task 17 — Troubleshoot: Broken Worker Node (NotReady)
**Weight: 14%** | **Cluster: bk8s**

---

## Task

```
kubectl config use-context bk8s
```

A worker node **`bk8s-worker`** is in **`NotReady`** state.

Investigate the issue and **fix it** so the node becomes **`Ready`**.

> **Practice mode:** Use `cause <1-5>` in this shell to inject a specific failure scenario.
> Each cause breaks the node differently — diagnose from scratch, then run `check` to verify.
> Run `reset` first if you need to restore the node to a healthy state before switching causes.

---

## Investigation Steps

```bash
# Step 1: Check node status from control plane
kubectl get nodes
# Expected: bk8s-worker   NotReady   ...

# Step 2: Describe the node — look at Events and Conditions
kubectl describe node bk8s-worker

# Step 3: SSH into the worker node
docker exec -it bk8s-worker bash

# Step 4: Check kubelet status
sudo systemctl status kubelet

# Step 5: Read kubelet logs for the root cause
sudo journalctl -u kubelet -xe --no-pager | tail -40

# Step 6: Check container runtime
sudo systemctl status containerd

# Step 7: Check disk usage
df -h

# Step 8: Check certificate expiry (on control plane)
sudo kubeadm certs check-expiration
```

---

## 原因 1 — kubelet 服务停止 / Cause 1: kubelet service stopped
*(Most common — appears in ~90% of CKA exam scenarios)*

**症状 / Symptom:**
```bash
sudo systemctl status kubelet
# ● kubelet.service - kubelet: The Kubernetes Node Agent
#    Active: inactive (dead)
```

**修复 / Fix:**
```bash
sudo systemctl start kubelet
sudo systemctl enable kubelet
```

---

## 原因 2 — containerd 容器运行时停止 / Cause 2: containerd runtime stopped

**症状 / Symptom:**
```bash
sudo systemctl status containerd
# Active: inactive (dead)

# kubelet logs show:
sudo journalctl -u kubelet -xe | grep -i "rpc\|unavailable\|refused"
# "rpc error: code = Unavailable desc = connection refused"
```

**修复 / Fix:**
```bash
sudo systemctl start containerd
sudo systemctl enable containerd
sudo systemctl restart kubelet   # restart kubelet after containerd is up
```

---

## 原因 3 — 配置文件错误 / Cause 3: Configuration file error

**症状 / Symptom:**
```bash
sudo systemctl status kubelet
# Active: failed (Result: exit-code)

sudo journalctl -u kubelet -xe | grep -i error
# "failed to load config file"
# "invalid YAML"
# "no such file or directory"
```

**配置文件位置 / Config file locations:**
```
/var/lib/kubelet/config.yaml               # kubelet config
/etc/systemd/system/kubelet.service.d/10-kubeadm.conf  # systemd unit config
/var/lib/kubelet/kubeadm-flags.env         # kubelet args
```

**修复 / Fix:**
```bash
# 1. Check syntax
sudo cat /var/lib/kubelet/config.yaml

# 2. Fix any syntax errors (missing colons, wrong indentation, bad paths)
sudo vi /var/lib/kubelet/config.yaml

# 3. Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## 原因 4 — 证书过期 / Cause 4: Certificate expired

> **Only `bk8s-control-plane` goes NotReady** — the kubelet client cert embedded in
> `kubelet.conf` is expired, so kubelet refuses to start.
> **The API server itself stays up** — you can still run `kubectl get nodes` from outside.
> SSH in with: `docker exec -it bk8s-control-plane bash`

**症状 / Symptom:**
```bash
# Inside bk8s-control-plane:
sudo systemctl status kubelet
# Active: activating (auto-restart) (Result: exit-code)

sudo journalctl -u kubelet | grep -i 'expired\|bootstrap'
# "bootstrap client certificate in /etc/kubernetes/kubelet.conf is expired: 2020-12-31"
# "unable to load bootstrap kubeconfig: .../bootstrap-kubelet.conf: no such file"
```

**修复 / Fix:**
```bash
# Still inside bk8s-control-plane:
sudo rm /etc/kubernetes/kubelet.conf              # must delete first — kubeadm won't overwrite
sudo kubeadm init phase kubeconfig kubelet        # regenerates kubelet.conf with new valid cert
sudo systemctl restart kubelet                    # picks up the new cert
```

---

## 原因 5 — 磁盘空间满 / Cause 5: Disk full

**症状 / Symptom:**
```bash
df -h
# tmpfs           200M  200M     0 100%  /var/lib/kubelet   ← full!

sudo systemctl status kubelet
# Active: inactive (dead) (Result: exit-code)

# Try starting it — it crashes again (disk still full):
sudo systemctl start kubelet && sleep 2 && sudo systemctl status kubelet
# Active: activating (auto-restart) (Result: exit-code)

sudo journalctl -u kubelet | grep -i "space"
# "Failed to save checkpoint ... no space left on device"
# "Failed to start ContainerManager"
```

**修复 / Fix:**
```bash
# Step 1: 确认哪个文件系统满了 / Confirm which filesystem is full
df -h
# → tmpfs   200M  200M  0  100%  /var/lib/kubelet

# Step 2: 找到占用空间的大文件 / Find the large file
sudo du -sh /var/lib/kubelet/* 2>/dev/null | sort -rh | head

# Step 3: 清理 2 天前的旧日志 / Remove journal logs older than 2 days
sudo journalctl --vacuum-time=2d

# Step 4: 删除未使用的容器镜像 / Remove unused container images
sudo crictl rmi --prune

# Step 5: 删除填充文件 (本场景关键修复) / Remove the fill file (key fix for this scenario)
sudo rm /var/lib/kubelet/disk-fill.img

# Step 6: 重启 kubelet / Restart kubelet
sudo systemctl restart kubelet
```

> **Note:** `journalctl --vacuum-time=2d` frees journal space and `crictl rmi --prune` frees image
> storage — both are standard CKA disk-cleanup steps. In this simulator they work on the main
> filesystem; `rm disk-fill.img` is what clears the `/var/lib/kubelet` tmpfs.

---

## Quick Root Cause Reference Table

| Symptom in logs/status | Root Cause | Fix command |
|------------------------|-----------|-------------|
| `Active: inactive (dead)` | kubelet stopped | `systemctl start kubelet` |
| `rpc error: connection refused` | containerd stopped | `systemctl start containerd && systemctl restart kubelet` |
| `failed to load config file` / `invalid YAML` | Config file error | fix YAML, `daemon-reload`, `restart kubelet` |
| `kubelet.conf is expired` / `unable to load bootstrap` | Expired kubelet.conf cert | `kubeadm init phase kubeconfig kubelet` + `restart kubelet` |
| `no space left on device` + `/var/lib/kubelet` 100% | Disk full | `du -sh /var/lib/kubelet/*`, `rm` large file, `restart kubelet` |

---

## Hint

<details>
<summary>Click to expand</summary>

**Diagnostic flow — always start here:**

```bash
# 1. SSH into the broken node
docker exec -it bk8s-worker bash   # causes 1-3, 5  (worker)
docker exec -it bk8s-control-plane bash   # cause 4  (control-plane)

# 2. Check kubelet first
sudo systemctl status kubelet

# 3. If failed or dead — read the logs
sudo journalctl -u kubelet -xe --no-pager | tail -40

# 4. Match log keywords to root cause:
#    "inactive (dead)"             → Cause 1: systemctl start kubelet
#    "connection refused" (rpc)    → Cause 2: systemctl start containerd
#    "failed to load config"       → Cause 3: fix config.yaml, daemon-reload, restart kubelet
#    "kubelet.conf is expired"     → Cause 4: rm kubelet.conf + kubeadm init phase kubeconfig kubelet
#    "no space left on device"     → Cause 5: clean disk + restart kubelet

# 5. For Cause 5 (disk full) — standard disk cleanup steps:
df -h                                    # 磁盘使用情况 / check which filesystem is full
du -sh /var/lib/kubelet/* | sort -rh     # 找大文件 / find large files

sudo journalctl --vacuum-time=2d         # 清理 2 天前的日志 / remove journal logs older than 2 days
sudo crictl rmi --prune                  # 删除未使用的镜像 / remove unused container images
sudo rm /var/lib/kubelet/disk-fill.img   # 删除填充文件 / remove the fill file (key fix)
sudo systemctl restart kubelet

# 6. After fix — exit and verify
exit
kubectl get nodes -w
```

</details>

---

## Answer

```bash
kubectl config use-context bk8s

# ── Step 1: Confirm the node is NotReady ──────────────────────────────────
kubectl get nodes
# bk8s-worker   NotReady   ...

# ── Step 2: Enter the worker node ─────────────────────────────────────────
docker exec -it bk8s-worker bash

# ── Step 3: Diagnose ──────────────────────────────────────────────────────
sudo systemctl status kubelet
sudo journalctl -u kubelet -xe --no-pager | tail -40
sudo systemctl status containerd
df -h

# ── Step 4: Apply the right fix ───────────────────────────────────────────

# [Cause 1] kubelet stopped:
sudo systemctl start kubelet
sudo systemctl enable kubelet

# [Cause 2] containerd stopped:
sudo systemctl start containerd
sudo systemctl enable containerd
sudo systemctl restart kubelet

# [Cause 3] Config file error:
sudo vi /var/lib/kubelet/config.yaml   # fix YAML syntax
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# [Cause 4] Expired kubelet.conf cert (run on bk8s-control-plane):
sudo journalctl -u kubelet | grep -i 'expired\|bootstrap'  # confirm: kubelet.conf cert expired
sudo rm /etc/kubernetes/kubelet.conf              # delete first — kubeadm won't overwrite
sudo kubeadm init phase kubeconfig kubelet        # regenerate with new valid cert
sudo systemctl restart kubelet                    # picks up the new cert

# [Cause 5] Disk full (run on bk8s-worker):
sudo df -h                                          # 确认 /var/lib/kubelet 100% 满
sudo du -sh /var/lib/kubelet/* | sort -rh | head   # 找大文件
sudo journalctl --vacuum-time=2d                   # 清理 2 天前的日志 / keep last 2 days
sudo crictl rmi --prune                            # 删除未使用的镜像 / remove unused images
sudo rm /var/lib/kubelet/disk-fill.img             # 删除填充文件 (关键修复)
sudo systemctl restart kubelet

# ── Step 5: Exit and verify (takes 30–60 seconds) ─────────────────────────
exit
kubectl get nodes -w
# bk8s-worker   Ready   ...
```
