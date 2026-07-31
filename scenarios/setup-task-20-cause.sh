#!/bin/bash
# Task 20 — Inject a service/DNS failure cause for practice
# Usage: bash setup-task-20-cause.sh <1-5>

CAUSE="${1:-}"
CTX="k8s"
NS="task20"
COREDNS_ORIGINAL_REPLICAS=2   # saved before scaling down

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }

# ── Create namespace and base workloads (server pod + client pod) ──────────────

deploy_base() {
    kubectl --context="$CTX" create namespace "$NS" \
        --dry-run=client -o yaml 2>/dev/null | kubectl --context="$CTX" apply -f - &>/dev/null || true

    # Server pod — nginx, label: app=task20-server
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task20-server
  namespace: $NS
  labels:
    app: task20-server
spec:
  containers:
  - name: server
    image: nginx:latest
    ports:
    - containerPort: 80
EOF

    # Client pod — busybox with sleep, used for exec/nslookup/wget
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: task20-client
  namespace: $NS
  labels:
    app: task20-client
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "infinity"]
EOF

    # Wait for both pods to be Running
    info "Waiting for task20-server and task20-client to be Running (up to 60s)..."
    kubectl --context="$CTX" wait pod task20-server task20-client \
        -n "$NS" --for=condition=Ready --timeout=60s 2>/dev/null \
        && ok "Pods are Ready" \
        || warn "Pods may still be starting — continuing anyway"
}

# ── Cleanup: remove all task20 resources and restore CoreDNS if needed ─────────

cleanup() {
    info "Cleaning up previous task20 artifacts..."

    # Restore CoreDNS if it was scaled down by a previous cause 3 run
    local current_replicas
    current_replicas=$(kubectl --context="$CTX" get deployment coredns \
        -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "${current_replicas:-2}" -eq 0 ]; then
        info "Restoring CoreDNS to $COREDNS_ORIGINAL_REPLICAS replicas..."
        kubectl --context="$CTX" scale deployment coredns \
            -n kube-system --replicas="$COREDNS_ORIGINAL_REPLICAS" 2>/dev/null || true
        kubectl --context="$CTX" wait pods -n kube-system -l k8s-app=kube-dns \
            --for=condition=Ready --timeout=60s 2>/dev/null || true
    fi

    kubectl --context="$CTX" -n "$NS" delete pod task20-server task20-client \
        --force --grace-period=0 --ignore-not-found 2>/dev/null | grep -v "^$" || true
    kubectl --context="$CTX" -n "$NS" delete svc task20-svc \
        --ignore-not-found 2>/dev/null | grep -v "^$" || true
    kubectl --context="$CTX" -n default delete svc task20-svc \
        --ignore-not-found 2>/dev/null | grep -v "^$" || true

    # Wait for pod deletion
    kubectl --context="$CTX" -n "$NS" wait --for=delete \
        pod/task20-server pod/task20-client --timeout=20s 2>/dev/null || true

    ok "Cleaned up"
}

# ── Cause 1: Service selector mismatch → no endpoints ─────────────────────────

cause_1() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 1: Selector Mismatch (No Endpoints) ━━━━━━━━━${NC}"
    cleanup
    deploy_base

    # Service with wrong selector
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: task20-svc
  namespace: $NS
spec:
  selector:
    app: task20-wrong
  ports:
  - port: 80
    targetPort: 80
EOF

    ok "Created service with selector 'app: task20-wrong' (pod has 'app: task20-server')"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task20 get endpoints task20-svc${NC}"
    echo -e "  → task20-svc   <none>   ← no endpoints"
    echo -e "  ${YELLOW}kubectl -n task20 describe svc task20-svc | grep Selector${NC}"
    echo -e "  → Selector: app=task20-wrong  ← doesn't match pod label app=task20-server"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task20 patch svc task20-svc \\${NC}"
    echo -e "  ${GREEN}  -p '{\"spec\":{\"selector\":{\"app\":\"task20-server\"}}}'${NC}"
    echo ""
}

# ── Cause 2: Wrong targetPort → endpoints exist but connection refused ──────────

cause_2() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 2: Wrong targetPort (Connection Refused) ━━━━${NC}"
    cleanup
    deploy_base

    # Service with correct selector but wrong targetPort
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: task20-svc
  namespace: $NS
spec:
  selector:
    app: task20-server
  ports:
  - port: 80
    targetPort: 8080
EOF

    ok "Created service with targetPort 8080 (nginx listens on 80)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task20 get endpoints task20-svc${NC}"
    echo -e "  → task20-svc   10.x.x.x:8080   ← endpoints exist but port 8080 is wrong"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- wget -qO- http://task20-svc/${NC}"
    echo -e "  → wget: can't connect: Connection refused"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task20 patch svc task20-svc \\${NC}"
    echo -e "  ${GREEN}  --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":80}]'${NC}"
    echo ""
}

# ── Cause 3: CoreDNS scaled to 0 → all DNS resolution fails ───────────────────

cause_3() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 3: CoreDNS Scaled to Zero (DNS Fails) ━━━━━━━${NC}"
    cleanup
    deploy_base

    # Create a healthy service (DNS problem is the issue, not the service config)
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: task20-svc
  namespace: $NS
spec:
  selector:
    app: task20-server
  ports:
  - port: 80
    targetPort: 80
EOF

    warn "Scaling CoreDNS to 0 — all DNS resolution in the cluster will fail..."
    # Save current replica count first
    COREDNS_ORIGINAL_REPLICAS=$(kubectl --context="$CTX" get deployment coredns \
        -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null)
    COREDNS_ORIGINAL_REPLICAS=${COREDNS_ORIGINAL_REPLICAS:-2}
    echo "$COREDNS_ORIGINAL_REPLICAS" > /tmp/cka20-coredns-replicas

    kubectl --context="$CTX" scale deployment coredns \
        -n kube-system --replicas=0 2>/dev/null \
        && ok "CoreDNS scaled to 0 replicas"

    sleep 5   # give CoreDNS pods time to terminate

    ok "Service task20-svc is correctly configured (service/endpoints are fine)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- nslookup task20-svc${NC}"
    echo -e "  → nslookup: can't resolve 'task20-svc'"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- nslookup kubernetes.default${NC}"
    echo -e "  → nslookup: can't resolve 'kubernetes.default'   ← ALL DNS fails"
    echo -e "  ${YELLOW}kubectl -n kube-system get deployment coredns${NC}"
    echo -e "  → READY: 0/0  AVAILABLE: 0   ← scaled to zero!"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n kube-system scale deployment coredns --replicas=2${NC}"
    echo -e "  ${GREEN}kubectl -n kube-system get pods -l k8s-app=kube-dns -w${NC}  ${DIM}# wait for Ready${NC}"
    echo ""
}

# ── Cause 4: Wrong service port → client connects to wrong port ─────────────────

cause_4() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 4: Wrong Service Port (Port 9090 vs 80) ━━━━━${NC}"
    cleanup
    deploy_base

    # Service with correct selector + targetPort, but wrong exposed port
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: task20-svc
  namespace: $NS
spec:
  selector:
    app: task20-server
  ports:
  - port: 9090
    targetPort: 80
EOF

    ok "Created service with port 9090 (client expects port 80)"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task20 get endpoints task20-svc${NC}"
    echo -e "  → task20-svc   10.x.x.x:80   ← endpoints look correct!"
    echo -e "  ${YELLOW}kubectl -n task20 describe svc task20-svc | grep -E 'Port:|TargetPort:'${NC}"
    echo -e "  → Port:       9090/TCP    ← service exposed on 9090, NOT 80"
    echo -e "  → TargetPort: 80/TCP      ← container port is correct"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- wget -qO- http://task20-svc/${NC}"
    echo -e "  → Connection refused   ← client tries :80, service listens on :9090"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- wget -qO- http://task20-svc:9090/${NC}"
    echo -e "  → <!DOCTYPE html>...   ← works on :9090"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n task20 patch svc task20-svc \\${NC}"
    echo -e "  ${GREEN}  --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/port\",\"value\":80}]'${NC}"
    echo ""
}

# ── Cause 5: Service in wrong namespace → short DNS name fails ─────────────────

cause_5() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 5: Service in Wrong Namespace ━━━━━━━━━━━━━━━${NC}"
    cleanup
    deploy_base

    # Create service in the DEFAULT namespace instead of task20
    kubectl --context="$CTX" apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: task20-svc
  namespace: default
spec:
  selector:
    app: task20-server
  ports:
  - port: 80
    targetPort: 80
EOF

    ok "Created service task20-svc in 'default' namespace (should be in 'task20')"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n task20 get svc${NC}  →  (no service in task20!)"
    echo -e "  ${YELLOW}kubectl -n task20 exec task20-client -- nslookup task20-svc${NC}"
    echo -e "  → nslookup: can't resolve 'task20-svc'"
    echo -e "  ${YELLOW}kubectl get svc -A | grep task20-svc${NC}"
    echo -e "  → default   task20-svc ...   ← wrong namespace!"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}kubectl -n default delete svc task20-svc${NC}"
    echo -e "  ${GREEN}kubectl -n task20 expose pod task20-server \\${NC}"
    echo -e "  ${GREEN}  --name=task20-svc --port=80 --target-port=80${NC}"
    echo ""
}

# ── Main dispatch ──────────────────────────────────────────────────────────────

case "$CAUSE" in
    1) cause_1 ;;
    2) cause_2 ;;
    3) cause_3 ;;
    4) cause_4 ;;
    5) cause_5 ;;
    *)
        echo ""
        echo -e "${BOLD}Task 20 — Choose a root cause to practice:${NC}"
        echo ""
        echo -e "  ${CYAN}cause 1${NC}  Selector mismatch → no endpoints"
        echo -e "  ${CYAN}cause 2${NC}  Wrong targetPort → connection refused despite endpoints"
        echo -e "  ${CYAN}cause 3${NC}  CoreDNS scaled to 0 → all DNS fails"
        echo -e "  ${CYAN}cause 4${NC}  Wrong service port → client reaches wrong port"
        echo -e "  ${CYAN}cause 5${NC}  Service in wrong namespace → short name fails"
        echo ""
        echo -e "  Usage: ${YELLOW}cause <1-5>${NC}  inside the task-20 shell"
        echo ""
        exit 1
        ;;
esac

# Record active cause for progress tracking
echo "$CAUSE" > /tmp/cka20-active

echo -e "${BOLD}${YELLOW}  Scenario is live. Diagnose → fix → run check to verify.${NC}"
echo -e "  Then: ${CYAN}cause <N>${NC} for the next scenario."
echo ""
