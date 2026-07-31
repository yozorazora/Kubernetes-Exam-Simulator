#!/bin/bash
# Task 18 — Inject a pod failure cause for practice
# Usage: bash setup-task-18-cause.sh <1-10>

CAUSE="${1:-}"
CTX="k8s"
NS="task18"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }

# ── Ensure namespace exists and clean up all previous cause artifacts ──────────

cleanup() {
    info "Cleaning up previous task18 artifacts..."

    kubectl --context="$CTX" create namespace "$NS" \
        --dry-run=client -o yaml 2>/dev/null | kubectl --context="$CTX" apply -f - &>/dev/null || true

    kubectl --context="$CTX" -n "$NS" delete pod task18-pod \
        --force --grace-period=0 --ignore-not-found 2>/dev/null | grep -v "^$" || true
    kubectl --context="$CTX" -n "$NS" delete pvc task18-pvc \
        --ignore-not-found 2>/dev/null | grep -v "^$" || true
    kubectl --context="$CTX" -n "$NS" delete configmap task18-config-vol task18-env-config \
        --ignore-not-found 2>/dev/null | grep -v "^$" || true
    kubectl --context="$CTX" -n "$NS" delete secret task18-env-secret \
        --ignore-not-found 2>/dev/null | grep -v "^$" || true

    # Brief wait for pod to fully terminate
    kubectl --context="$CTX" -n "$NS" wait --for=delete pod/task18-pod \
        --timeout=15s 2>/dev/null || true

    ok "Namespace $NS is clean"
}

# ── Cause 1: Pod Pending — resource requests too high ─────────────────────────

cause_1() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 1: Pod Pending (Insufficient CPU) ━━━━━━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      requests:
        cpu: "99"
        memory: "1Mi"
EOF
    ok "Created pod with cpu request of 99 cores (unschedulable)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: Pending"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | tail -5${NC}"
    echo -e "  → Warning FailedScheduling: 0/1 nodes available: 1 Insufficient cpu"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never${NC}"
    echo ""
}

# ── Cause 2: ImagePullBackOff — wrong image name ──────────────────────────────

cause_2() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 2: ImagePullBackOff (Wrong Image Name) ━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: ngiinx:latest
EOF
    ok "Created pod with typo image 'ngiinx:latest'"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: ImagePullBackOff"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep -A 5 Events${NC}"
    echo -e "  → Failed to pull image \"ngiinx:latest\": ... not found"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never${NC}"
    echo ""
}

# ── Cause 3: CrashLoopBackOff — container exits immediately ───────────────────

cause_3() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 3: CrashLoopBackOff (Container Exits) ━━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    command: ["sh", "-c", "echo 'Starting...' && exit 1"]
EOF
    ok "Created pod with command that exits with code 1"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: CrashLoopBackOff"
    echo -e "  ${YELLOW}kubectl -n task18 logs task18-pod${NC}  →  Starting..."
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep 'Exit Code'${NC}  →  1"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never${NC}"
    echo ""
}

# ── Cause 4: FailedMount — ConfigMap volume does not exist ────────────────────

cause_4() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 4: FailedMount (ConfigMap Volume Missing) ━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    volumeMounts:
    - name: config-vol
      mountPath: /etc/config
  volumes:
  - name: config-vol
    configMap:
      name: task18-config-vol
EOF
    ok "Created pod referencing ConfigMap 'task18-config-vol' (does not exist)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: Pending"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | tail -8${NC}"
    echo -e "  → Warning FailedMount: configmap \"task18-config-vol\" not found"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 create configmap task18-config-vol --from-literal=key=value${NC}"
    echo -e "  ${DIM}(Pod auto-retries the mount — no need to delete and recreate)${NC}"
    echo ""
}

# ── Cause 5: ConfigMap missing — envFrom reference ────────────────────────────

cause_5() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 5: ConfigMap Missing (envFrom) ━━━━━━━━━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    envFrom:
    - configMapRef:
        name: task18-env-config
EOF
    ok "Created pod with envFrom referencing ConfigMap 'task18-env-config' (does not exist)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: CreateContainerConfigError"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep -A 3 Events${NC}"
    echo -e "  → Error: configmap \"task18-env-config\" not found"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 create configmap task18-env-config \\${NC}"
    echo -e "  ${GREEN}  --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=info${NC}"
    echo ""
}

# ── Cause 6: Secret missing — envFrom reference ───────────────────────────────

cause_6() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 6: Secret Missing (envFrom) ━━━━━━━━━━━━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    envFrom:
    - secretRef:
        name: task18-env-secret
EOF
    ok "Created pod with envFrom referencing Secret 'task18-env-secret' (does not exist)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: CreateContainerConfigError"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep -A 3 Events${NC}"
    echo -e "  → Error: secret \"task18-env-secret\" not found"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 create secret generic task18-env-secret \\${NC}"
    echo -e "  ${GREEN}  --from-literal=DB_PASSWORD=secret123 --from-literal=API_KEY=abc123${NC}"
    echo ""
}

# ── Cause 7: PVC Pending — invalid StorageClass ───────────────────────────────

cause_7() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 7: PVC Pending (Invalid StorageClass) ━━━━━━━━${NC}"
    cleanup

    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task18-pvc
  namespace: $NS
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
  storageClassName: fake-sc
EOF

    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: task18-pvc
EOF

    ok "Created PVC with StorageClass 'fake-sc' (does not exist) + pod referencing it"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: Pending"
    echo -e "  ${YELLOW}kubectl -n task18 get pvc${NC}  →  STATUS: Pending  STORAGECLASS: fake-sc"
    echo -e "  ${YELLOW}kubectl -n task18 describe pvc task18-pvc${NC}"
    echo -e "  → ProvisioningFailed: storageclass.storage.k8s.io \"fake-sc\" not found"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl get storageclass${NC}   ${YELLOW}# find a valid StorageClass${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pvc task18-pvc${NC}"
    echo -e "  ${GREEN}# Recreate PVC with storageClassName: standard  (or whichever SC exists)${NC}"
    echo ""
}

# ── Cause 8: Readiness probe — wrong port ─────────────────────────────────────

cause_8() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 8: Readiness Probe Failing (Wrong Port) ━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    readinessProbe:
      httpGet:
        path: /
        port: 9999
      initialDelaySeconds: 3
      periodSeconds: 5
      failureThreshold: 3
EOF
    ok "Created pod with readinessProbe on port 9999 (nginx listens on 80)"
    warn "Pod will show Running but 0/1 Ready — wait ~15s for probe to fire"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}"
    echo -e "  → task18-pod   0/1   Running   0   ...   (READY is 0/1)"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep -A 5 Readiness${NC}"
    echo -e "  → Readiness probe failed: Get \"http://:9999/\": connection refused"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}# Recreate with readinessProbe.httpGet.port: 80${NC}"
    echo ""
}

# ── Cause 9: Liveness probe — wrong command (always fails) ────────────────────

cause_9() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 9: Liveness Probe Failing (Wrong Command) ━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:latest
    livenessProbe:
      exec:
        command: ["sh", "-c", "exit 1"]
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 1
EOF
    ok "Created pod with livenessProbe command 'exit 1' (always fails)"
    warn "Pod starts, then liveness kills it — restarts begin after ~10s"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}"
    echo -e "  → task18-pod   0/1   Running   3   ...   (RESTARTS incrementing)"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep 'Exit Code'${NC}  →  137"
    echo -e "  ${DIM}Exit code 137 = container was killed by liveness probe (SIGKILL)${NC}"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never${NC}"
    echo ""
}

# ── Cause 10: Wrong image tag ─────────────────────────────────────────────────

cause_10() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 10: Wrong Image Tag ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cleanup
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task18-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: nginx:9999
EOF
    ok "Created pod with non-existent image tag 'nginx:9999'"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task18 get pods${NC}  →  STATUS: ErrImagePull / ImagePullBackOff"
    echo -e "  ${YELLOW}kubectl -n task18 describe pod task18-pod | grep -A 5 Events${NC}"
    echo -e "  → Failed to pull image \"nginx:9999\": ... tag does not exist"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task18 delete pod task18-pod${NC}"
    echo -e "  ${GREEN}kubectl -n task18 run task18-pod --image=nginx:latest --restart=Never${NC}"
    echo ""
}

# ── Main dispatch ──────────────────────────────────────────────────────────────

case "$CAUSE" in
    1)  cause_1  ;;
    2)  cause_2  ;;
    3)  cause_3  ;;
    4)  cause_4  ;;
    5)  cause_5  ;;
    6)  cause_6  ;;
    7)  cause_7  ;;
    8)  cause_8  ;;
    9)  cause_9  ;;
    10) cause_10 ;;
    *)
        echo ""
        echo -e "${BOLD}Task 18 — Choose a root cause to practice:${NC}"
        echo ""
        echo -e "  ${CYAN}cause 1${NC}   Pod Pending — insufficient CPU/memory"
        echo -e "  ${CYAN}cause 2${NC}   ImagePullBackOff — wrong image name (typo)"
        echo -e "  ${CYAN}cause 3${NC}   CrashLoopBackOff — container exits with code 1"
        echo -e "  ${CYAN}cause 4${NC}   FailedMount — ConfigMap volume not found"
        echo -e "  ${CYAN}cause 5${NC}   CreateContainerConfigError — ConfigMap missing (envFrom)"
        echo -e "  ${CYAN}cause 6${NC}   CreateContainerConfigError — Secret missing (envFrom)"
        echo -e "  ${CYAN}cause 7${NC}   PVC Pending — StorageClass not found"
        echo -e "  ${CYAN}cause 8${NC}   Readiness probe failing — wrong port"
        echo -e "  ${CYAN}cause 9${NC}   Liveness probe failing — always-fail command"
        echo -e "  ${CYAN}cause 10${NC}  ErrImagePull — wrong image tag"
        echo ""
        echo -e "  Usage: ${YELLOW}cause <1-10>${NC}  inside the task-18 shell"
        echo ""
        exit 1
        ;;
esac

# Record active cause for progress tracking in verify-task-18.sh
echo "$CAUSE" > /tmp/cka18-active

echo -e "${BOLD}${YELLOW}  Scenario is live. Run: kubectl -n task18 get pods${NC}"
echo -e "  Diagnose → fix → run ${CYAN}check${NC} to verify → ${CYAN}cause <N>${NC} for next scenario."
echo ""
