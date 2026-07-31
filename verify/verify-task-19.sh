#!/bin/bash
# Verify Task 19: Troubleshoot — Control Plane Components
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="bk8s"
PASS_COUNT=0; FAIL_COUNT=0

STATE_ACTIVE="/tmp/cka19-active"
STATE_DONE="/tmp/cka19-done"

declare -a CAUSE_LABELS
CAUSE_LABELS[1]="kube-apiserver CrashLoopBackOff (bad flag)"
CAUSE_LABELS[2]="kube-scheduler cannot start (bad kubeconfig path)"
CAUSE_LABELS[3]="kube-controller-manager failed (bad kubeconfig path)"
CAUSE_LABELS[4]="static pod manifest YAML syntax error (scheduler disappears)"

is_done() { grep -qx "$1" "$STATE_DONE" 2>/dev/null; }

echo -e "${BOLD}═══ Verifying Task 19: Control Plane Components ════════════════${NC}"

# ── Step 1: Check apiserver reachability ──────────────────────────────────────

echo -e "\n  ${BOLD}Checking API server reachability...${NC}"
if kubectl --context="$CTX" get nodes --request-timeout=10s &>/dev/null 2>&1; then
    check_pass "kube-apiserver is reachable"
else
    check_fail "kube-apiserver is NOT reachable — it may be down or crashing"
    check_fail "SSH in: docker exec -it bk8s-control-plane bash"
    check_fail "Then: crictl ps -a | grep apiserver && crictl logs <id>"
    echo ""
    echo -e "${BOLD}━━━ Verification Result: Task 19 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"
    echo -e "\n  ${BOLD}${RED}✗  API server is down — fix kube-apiserver first, then re-run check${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
fi

# ── Step 2: Use context ───────────────────────────────────────────────────────
use_context "$CTX"

# ── Step 3: Check each control plane component ────────────────────────────────

check_component() {
    local label="$1"    # display name
    local selector="$2" # -l component=<name>

    local pod_name
    pod_name=$(kubectl -n kube-system get pods -l "component=${selector}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod_name" ]; then
        check_fail "${label} pod not found — manifest may have a YAML syntax error"
        return
    fi

    local phase
    phase=$(kubectl -n kube-system get pod "$pod_name" \
        -o jsonpath='{.status.phase}' 2>/dev/null)

    local ready
    ready=$(kubectl -n kube-system get pod "$pod_name" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    local restarts
    restarts=$(kubectl -n kube-system get pod "$pod_name" \
        -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    restarts=${restarts:-0}

    if [ "$phase" = "Running" ] && [ "$ready" = "True" ]; then
        check_pass "${label} (${pod_name}) is Running and Ready"
    elif [ "$phase" = "Running" ] && [ "$ready" != "True" ]; then
        check_fail "${label} is Running but NOT Ready (restarts: ${restarts})"
    else
        check_fail "${label} is in phase '${phase:-Unknown}' (restarts: ${restarts}) — check logs"
    fi
}

check_component "kube-apiserver"          "kube-apiserver"
check_component "kube-scheduler"          "kube-scheduler"
check_component "kube-controller-manager" "kube-controller-manager"

# ── Step 3b: Prune stale exited containers/sandboxes left by the fix ─────────
# Fixing a manifest makes the kubelet recreate the static pod, leaving the
# pre-fix Exited container + NotReady sandbox behind in crictl. Once the
# component is confirmed healthy above, it's safe to prune those now instead
# of waiting for the next `cause` to clean them up.

if [ "$FAIL_COUNT" -eq 0 ]; then
    docker exec -i bk8s-control-plane bash << 'INNER' &>/dev/null
for comp in kube-apiserver kube-scheduler kube-controller-manager; do
    for cid in $(crictl ps -a --name "$comp" --state Exited -q 2>/dev/null); do
        crictl rm "$cid" &>/dev/null
    done
    for pid in $(crictl pods --name "$comp" --state notready -q 2>/dev/null); do
        crictl rmp "$pid" &>/dev/null
    done
done
INNER
fi

# ── Step 4: Per-cause progress tracking ───────────────────────────────────────

ACTIVE_CAUSE=""
[ -f "$STATE_ACTIVE" ] && ACTIVE_CAUSE=$(tr -d '[:space:]' < "$STATE_ACTIVE" 2>/dev/null)

if [ "$FAIL_COUNT" -eq 0 ] && [[ "$ACTIVE_CAUSE" =~ ^[1-4]$ ]]; then
    if ! is_done "$ACTIVE_CAUSE"; then
        echo "$ACTIVE_CAUSE" >> "$STATE_DONE"
    fi
    rm -f "$STATE_ACTIVE"
    ACTIVE_CAUSE=""
fi

DONE_COUNT=0
[ -f "$STATE_DONE" ] && DONE_COUNT=$(sort -u "$STATE_DONE" 2>/dev/null | grep -c '^[1-4]$' || true)

NEXT_CAUSE=""
for i in 1 2 3 4; do
    if ! is_done "$i"; then NEXT_CAUSE=$i; break; fi
done

# Progress table
echo ""
echo -e "  ${BOLD}Cause Progress — practice all 4 to complete Task 19:${NC}"
echo ""
for i in 1 2 3 4; do
    label="${CAUSE_LABELS[$i]}"
    if is_done "$i"; then
        echo -e "  ${GREEN}✓${NC}  Cause $i — $label"
    elif [ "$ACTIVE_CAUSE" = "$i" ]; then
        echo -e "  ${YELLOW}→${NC}  Cause $i — $label  ${YELLOW}← active, not fixed yet${NC}"
    else
        echo -e "  ${CYAN}○${NC}  Cause $i — $label"
    fi
done
echo ""

# ── Final summary ─────────────────────────────────────────────────────────────

echo -e "${BOLD}━━━ Verification Result: Task 19 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "\n  ${BOLD}${RED}✗  One or more control plane components not healthy — fix and re-run check${NC}"
elif [ "$DONE_COUNT" -ge 4 ]; then
    echo -e "\n  ${BOLD}${GREEN}✓  TASK 19 — COMPLETE (all 4 causes practiced)${NC}"
else
    echo -e "\n  ${BOLD}${YELLOW}◎  All components healthy — Progress: ${DONE_COUNT}/4 causes practiced${NC}"
    [ -n "$NEXT_CAUSE" ] && \
        echo -e "  Run ${CYAN}cause ${NEXT_CAUSE}${NC} to practice: ${CAUSE_LABELS[$NEXT_CAUSE]}"
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[ "$FAIL_COUNT" -eq 0 ]
