#!/bin/bash
# Task 19 — Inject a control plane failure cause for practice
# Usage: bash setup-task-19-cause.sh <1-4>

CAUSE="${1:-}"
CP="bk8s-control-plane"
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }

if ! docker inspect "$CP" &>/dev/null; then
    fail "Container '$CP' not found — is the bk8s cluster running?"
    exit 1
fi

# ── Prune exited containers / stale sandboxes left behind by manifest edits ──
# Every manifest edit makes the kubelet recreate the static pod (new sandbox +
# container), so crictl accumulates Exited containers and NotReady sandboxes
# from previous cause cycles. Clean those up, keeping only the live one.

cleanup_stale_containers() {
    docker exec -i "$CP" bash << 'INNER'
for comp in kube-apiserver kube-scheduler kube-controller-manager; do
    for cid in $(crictl ps -a --name "$comp" --state Exited -q 2>/dev/null); do
        crictl rm "$cid" &>/dev/null
    done
    for pid in $(crictl pods --name "$comp" --state notready -q 2>/dev/null); do
        crictl rmp "$pid" &>/dev/null
    done
done
INNER
}

# ── Restore all manifests to a clean, healthy state ───────────────────────────

restore_clean() {
    info "Restoring control plane manifests to clean state..."

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

# Restore any manifest backed up by a previous cause
for bak_file in "$PKI_DIR"/kube-*.yaml.bak19c*; do
    [ -f "$bak_file" ] || continue
    # Strip the .bak19cN suffix to get the original manifest filename
    base=$(basename "$bak_file")
    orig_name="${base%.bak19c*}"
    cp "$bak_file" "$MANIFEST_DIR/$orig_name"
    rm -f "$bak_file"
    echo "  Restored $orig_name"
done
INNER

    ok "Manifests restored (any .bak19c* backups applied)"

    # Wait for the apiserver to be reachable — needed when cause 1 was active
    info "Waiting for kube-apiserver to be reachable (up to 90s)..."
    local waited=0
    while [ $waited -lt 90 ]; do
        if kubectl --context=bk8s get nodes --request-timeout=5s &>/dev/null 2>&1; then
            ok "kube-apiserver is accessible"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        printf "  . %ds elapsed\n" "$waited"
    done
    [ $waited -ge 90 ] && warn "API server may still be starting — wait a moment before proceeding"

    # Wait for scheduler and controller-manager to be Running
    local waited2=0
    while [ $waited2 -lt 60 ]; do
        SCHED=$(kubectl --context=bk8s get pods -n kube-system -l component=kube-scheduler \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        CM=$(kubectl --context=bk8s get pods -n kube-system -l component=kube-controller-manager \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [ "$SCHED" = "Running" ] && [ "$CM" = "Running" ]; then
            ok "All control plane components are Running"
            break
        fi
        sleep 5
        waited2=$((waited2 + 5))
    done
    [ $waited2 -ge 60 ] && warn "Some components may still be starting"

    cleanup_stale_containers
}

# ── Cause 1: kube-apiserver — bad flag ────────────────────────────────────────

cause_1() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 1: kube-apiserver CrashLoopBackOff ━━━━━━━━━━${NC}"
    restore_clean

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

# Backup current apiserver manifest
cp "$MANIFEST_DIR/kube-apiserver.yaml" "$PKI_DIR/kube-apiserver.yaml.bak19c1"

# Insert an unknown flag after the etcd-servers line (always present in apiserver manifest)
sed -i '/--etcd-servers/a\    - --this-flag-does-not-exist=true' \
    "$MANIFEST_DIR/kube-apiserver.yaml"

echo "Injected bad flag into kube-apiserver.yaml"
INNER

    ok "Inserted unknown flag into kube-apiserver.yaml"
    warn "Waiting for apiserver to go down (up to 60s)..."

    local waited=0
    while [ $waited -lt 60 ]; do
        if ! kubectl --context=bk8s get nodes --request-timeout=3s &>/dev/null 2>&1; then
            ok "kube-apiserver is down — scenario is live"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        printf "  . %ds elapsed\n" "$waited"
    done
    [ $waited -ge 60 ] && warn "Apiserver may still be running — the bad flag may take a moment to restart"

    echo ""
    echo -e "  ${BOLD}Node:${NC} $CP"
    echo -e "  ${BOLD}SSH in:${NC} ${CYAN}docker exec -it $CP bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl --context=bk8s get nodes${NC}  →  connection refused / timeout"
    echo -e "  ${YELLOW}crictl ps -a | grep apiserver${NC}  →  container in Exited state"
    echo -e "  ${YELLOW}crictl logs <id>${NC}  →  \"unknown flag: --this-flag-does-not-exist\""
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sed -i '/--this-flag-does-not-exist/d' $MANIFEST_DIR/kube-apiserver.yaml${NC}"
    echo ""
}

# ── Cause 2: kube-scheduler — bad kubeconfig path ─────────────────────────────

cause_2() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 2: kube-scheduler Cannot Start ━━━━━━━━━━━━━━${NC}"
    restore_clean

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

# Backup scheduler manifest
cp "$MANIFEST_DIR/kube-scheduler.yaml" "$PKI_DIR/kube-scheduler.yaml.bak19c2"

# Change kubeconfig path to a non-existent file
sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.conf|--kubeconfig=/etc/kubernetes/scheduler-broken.conf|' \
    "$MANIFEST_DIR/kube-scheduler.yaml"

echo "Broke kubeconfig path in kube-scheduler.yaml"
INNER

    ok "kube-scheduler.yaml now points to a non-existent kubeconfig"
    info "Waiting ~15s for scheduler to enter CrashLoopBackOff..."
    sleep 15

    echo ""
    echo -e "  ${BOLD}Node:${NC} $CP"
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n kube-system get pods | grep scheduler${NC}  →  CrashLoopBackOff"
    echo -e "  ${YELLOW}kubectl -n kube-system logs kube-scheduler-bk8s-control-plane${NC}"
    echo -e "  → \"unable to load config: open /etc/kubernetes/scheduler-broken.conf: no such file\""
    echo -e "  ${YELLOW}grep kubeconfig $MANIFEST_DIR/kube-scheduler.yaml${NC}"
    echo -e "  →   - --kubeconfig=/etc/kubernetes/scheduler-broken.conf"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sed -i 's|scheduler-broken.conf|scheduler.conf|' $MANIFEST_DIR/kube-scheduler.yaml${NC}"
    echo ""
}

# ── Cause 3: kube-controller-manager — bad kubeconfig path ────────────────────

cause_3() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 3: kube-controller-manager Failed ━━━━━━━━━━━${NC}"
    restore_clean

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

# Backup controller-manager manifest
cp "$MANIFEST_DIR/kube-controller-manager.yaml" "$PKI_DIR/kube-controller-manager.yaml.bak19c3"

# Change kubeconfig path to a non-existent file
sed -i 's|--kubeconfig=/etc/kubernetes/controller-manager.conf|--kubeconfig=/etc/kubernetes/controller-manager-broken.conf|' \
    "$MANIFEST_DIR/kube-controller-manager.yaml"

echo "Broke kubeconfig path in kube-controller-manager.yaml"
INNER

    ok "kube-controller-manager.yaml now points to a non-existent kubeconfig"
    info "Waiting ~15s for controller-manager to enter CrashLoopBackOff..."
    sleep 15

    echo ""
    echo -e "  ${BOLD}Node:${NC} $CP"
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n kube-system get pods | grep controller-manager${NC}  →  CrashLoopBackOff"
    echo -e "  ${YELLOW}kubectl -n kube-system logs kube-controller-manager-bk8s-control-plane${NC}"
    echo -e "  → \"unable to load config: open /etc/kubernetes/controller-manager-broken.conf: no such file\""
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sed -i 's|controller-manager-broken.conf|controller-manager.conf|' \\${NC}"
    echo -e "  ${GREEN}    $MANIFEST_DIR/kube-controller-manager.yaml${NC}"
    echo ""
}

# ── Cause 4: kube-scheduler — YAML syntax error in manifest ───────────────────

cause_4() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 4: Static Pod Manifest YAML Syntax Error ━━━━${NC}"
    restore_clean

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

# Backup scheduler manifest
cp "$MANIFEST_DIR/kube-scheduler.yaml" "$PKI_DIR/kube-scheduler.yaml.bak19c4"

# Append an invalid YAML line — kubelet will fail to parse the manifest
echo 'INVALID_YAML: [this is not valid yaml' >> "$MANIFEST_DIR/kube-scheduler.yaml"

echo "Appended invalid YAML to kube-scheduler.yaml"
INNER

    ok "Corrupted kube-scheduler.yaml with invalid YAML (pod will disappear)"
    info "Waiting ~15s for kubelet to notice and remove the scheduler pod..."
    sleep 15

    echo ""
    echo -e "  ${BOLD}Node:${NC} $CP"
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}kubectl -n kube-system get pods | grep scheduler${NC}  →  (no output — pod is MISSING)"
    echo -e "  ${YELLOW}docker exec -it bk8s-control-plane journalctl -u kubelet -xe | tail -20${NC}"
    echo -e "  → \"failed to process config\" / \"error parsing manifest\""
    echo -e "  ${YELLOW}tail -5 $MANIFEST_DIR/kube-scheduler.yaml${NC}"
    echo -e "  → INVALID_YAML: [this is not valid yaml"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sed -i '/INVALID_YAML/d' $MANIFEST_DIR/kube-scheduler.yaml${NC}"
    echo ""
}

# ── Main dispatch ──────────────────────────────────────────────────────────────

case "$CAUSE" in
    1) cause_1 ;;
    2) cause_2 ;;
    3) cause_3 ;;
    4) cause_4 ;;
    *)
        echo ""
        echo -e "${BOLD}Task 19 — Choose a root cause to practice:${NC}"
        echo ""
        echo -e "  ${CYAN}cause 1${NC}  kube-apiserver CrashLoopBackOff   ${YELLOW}(bad flag — kubectl stops working)${NC}"
        echo -e "  ${CYAN}cause 2${NC}  kube-scheduler cannot start        ${YELLOW}(bad kubeconfig path)${NC}"
        echo -e "  ${CYAN}cause 3${NC}  kube-controller-manager failed     ${YELLOW}(bad kubeconfig path)${NC}"
        echo -e "  ${CYAN}cause 4${NC}  static pod manifest YAML error     ${YELLOW}(scheduler pod disappears)${NC}"
        echo ""
        echo -e "  Usage: ${YELLOW}cause <1-4>${NC}  inside the task-19 shell"
        echo ""
        exit 1
        ;;
esac

# Record active cause for progress tracking in verify-task-19.sh
echo "$CAUSE" > /tmp/cka19-active

echo -e "${BOLD}${YELLOW}  Scenario is live. Run check to verify after you fix it.${NC}"
echo -e "  Diagnose → fix → ${CYAN}check${NC} → ${CYAN}cause <N>${NC} for next scenario."
echo ""
