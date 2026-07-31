#!/bin/bash
# Verify Task 18: Troubleshoot — Pod Not Running
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task18"
POD="task18-pod"
PASS_COUNT=0; FAIL_COUNT=0

STATE_ACTIVE="/tmp/cka18-active"
STATE_DONE="/tmp/cka18-done"

declare -a CAUSE_LABELS
CAUSE_LABELS[1]="Pod Pending — insufficient CPU/memory"
CAUSE_LABELS[2]="ImagePullBackOff — wrong image name (typo)"
CAUSE_LABELS[3]="CrashLoopBackOff — container exits immediately"
CAUSE_LABELS[4]="FailedMount — ConfigMap volume not found"
CAUSE_LABELS[5]="ConfigMap missing (envFrom)"
CAUSE_LABELS[6]="Secret missing (envFrom)"
CAUSE_LABELS[7]="PVC Pending — invalid StorageClass"
CAUSE_LABELS[8]="Readiness probe failing — wrong port"
CAUSE_LABELS[9]="Liveness probe failing — wrong command"
CAUSE_LABELS[10]="Wrong image tag"

is_done() { grep -qx "$1" "$STATE_DONE" 2>/dev/null; }

echo -e "${BOLD}═══ Verifying Task 18: Pod Not Running Fix ══════════════════════${NC}"
use_context "$CTX"

# ── Check pod exists ──────────────────────────────────────────────────────────

POD_JSON=$(kubectl -n "$NS" get pod "$POD" -o json 2>/dev/null)

if [ -z "$POD_JSON" ]; then
    check_fail "Pod '$POD' not found in namespace '$NS'"
    check_fail "Create it: kubectl -n $NS run $POD --image=nginx:latest --restart=Never"
    echo ""
    echo -e "${BOLD}━━━ Verification Result: Task 18 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"
    echo -e "\n  ${BOLD}${RED}✗  Pod not found — fix the issue and run check again${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
fi

# ── Check pod phase (Running) ─────────────────────────────────────────────────

PHASE=$(echo "$POD_JSON" | grep -o '"phase":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$PHASE" = "Running" ]; then
    check_pass "Pod '$POD' phase is Running"
else
    check_fail "Pod '$POD' phase is '${PHASE:-Unknown}' — expected Running"
fi

# ── Check pod Ready condition ─────────────────────────────────────────────────

READY_STATUS=$(kubectl -n "$NS" get pod "$POD" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$READY_STATUS" = "True" ]; then
    check_pass "Pod '$POD' is Ready (1/1)"
else
    check_fail "Pod '$POD' is NOT Ready — readiness probe may be failing"
fi

# ── Check container is not in a restart loop ──────────────────────────────────

RESTARTS=$(kubectl -n "$NS" get pod "$POD" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
RESTARTS=${RESTARTS:-0}
if [ "$RESTARTS" -lt 3 ]; then
    check_pass "Pod '$POD' restart count is acceptable (${RESTARTS})"
else
    check_fail "Pod '$POD' has restarted ${RESTARTS} times — liveness probe or command may be broken"
fi

# ── Per-cause progress tracking ───────────────────────────────────────────────

ACTIVE_CAUSE=""
[ -f "$STATE_ACTIVE" ] && ACTIVE_CAUSE=$(tr -d '[:space:]' < "$STATE_ACTIVE" 2>/dev/null)

# If all checks passed and a cause was active → mark it done
if [ "$FAIL_COUNT" -eq 0 ] && [[ "$ACTIVE_CAUSE" =~ ^(10|[1-9])$ ]]; then
    if ! is_done "$ACTIVE_CAUSE"; then
        echo "$ACTIVE_CAUSE" >> "$STATE_DONE"
    fi
    rm -f "$STATE_ACTIVE"
    ACTIVE_CAUSE=""
fi

DONE_COUNT=0
[ -f "$STATE_DONE" ] && DONE_COUNT=$(sort -u "$STATE_DONE" 2>/dev/null | grep -cE '^(10|[1-9])$' || true)

NEXT_CAUSE=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! is_done "$i"; then NEXT_CAUSE=$i; break; fi
done

# Progress table
echo ""
echo -e "  ${BOLD}Cause Progress — practice all 10 to complete Task 18:${NC}"
echo ""
for i in 1 2 3 4 5 6 7 8 9 10; do
    label="${CAUSE_LABELS[$i]}"
    if is_done "$i"; then
        echo -e "  ${GREEN}✓${NC}  Cause $i  — $label"
    elif [ "$ACTIVE_CAUSE" = "$i" ]; then
        echo -e "  ${YELLOW}→${NC}  Cause $i  — $label  ${YELLOW}← active, not fixed yet${NC}"
    else
        echo -e "  ${CYAN}○${NC}  Cause $i  — $label"
    fi
done
echo ""

# ── Final summary ─────────────────────────────────────────────────────────────

echo -e "${BOLD}━━━ Verification Result: Task 18 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "\n  ${BOLD}${RED}✗  Pod not healthy — fix and run check again${NC}"
elif [ "$DONE_COUNT" -ge 10 ]; then
    echo -e "\n  ${BOLD}${GREEN}✓  TASK 18 — COMPLETE (all 10 causes practiced)${NC}"
else
    echo -e "\n  ${BOLD}${YELLOW}◎  Pod is Running and Ready — Progress: ${DONE_COUNT}/10 causes practiced${NC}"
    [ -n "$NEXT_CAUSE" ] && \
        echo -e "  Run ${CYAN}cause ${NEXT_CAUSE}${NC} to practice: ${CAUSE_LABELS[$NEXT_CAUSE]}"
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[ "$FAIL_COUNT" -eq 0 ]
