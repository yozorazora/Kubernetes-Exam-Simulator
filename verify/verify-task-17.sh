#!/bin/bash
# Verify Task 17: Troubleshoot — Worker Node NotReady
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="bk8s"
PASS_COUNT=0; FAIL_COUNT=0

STATE_ACTIVE="/tmp/cka17-active"
STATE_DONE="/tmp/cka17-done"

declare -a CAUSE_LABELS
CAUSE_LABELS[1]="kubelet service stopped       (Most common, ~90% of exams)"
CAUSE_LABELS[2]="containerd runtime stopped"
CAUSE_LABELS[3]="kubelet config file error"
CAUSE_LABELS[4]="Certificate expired           (real x509 expiry error)"
CAUSE_LABELS[5]="Disk full"

is_done() { grep -qx "$1" "$STATE_DONE" 2>/dev/null; }

echo -e "${BOLD}═══ Verifying Task 17: Node NotReady Fix ════════════════════════${NC}"
use_context "$CTX"

# ── Check every node in the bk8s cluster ─────────────────────────────────────
# Cause 1-3, 5 break bk8s-worker; cause 4 breaks bk8s-control-plane.
# Checking all nodes covers every scenario.

NODE_LIST=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
NOW_EPOCH=$(date +%s)

if [ -z "$NODE_LIST" ]; then
    check_fail "Cannot reach API server — kubectl get nodes returned no output"
    check_fail "API server may be down or serving an expired/invalid TLS certificate"
fi

for NODE in $NODE_LIST; do

    # Ready condition
    CONDITION=$(kubectl get node "$NODE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$CONDITION" = "True" ]; then
        check_pass "Node '$NODE' is Ready"
    else
        check_fail "Node '$NODE' is NOT Ready — fix kubelet on that node then re-run check"
    fi

    # Schedulable
    UNSCHED=$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
    if [ -z "$UNSCHED" ] || [ "$UNSCHED" = "false" ]; then
        check_pass "Node '$NODE' is schedulable"
    else
        check_fail "Node '$NODE' is unschedulable (cordoned)"
    fi

    # Fresh heartbeat via node lease
    LEASE_TIME=$(kubectl get lease "$NODE" -n kube-node-lease \
        -o jsonpath='{.spec.renewTime}' 2>/dev/null)
    if [ -n "$LEASE_TIME" ]; then
        HB_EPOCH=$(date -d "$LEASE_TIME" +%s 2>/dev/null || \
                   date -j -f "%Y-%m-%dT%H:%M:%S" "${LEASE_TIME%.*}" +%s 2>/dev/null)
        AGE=$(( NOW_EPOCH - ${HB_EPOCH:-0} ))
        if [ -n "$HB_EPOCH" ] && [ "$AGE" -lt 90 ]; then
            check_pass "Node '$NODE' lease heartbeat is fresh (${AGE}s ago)"
        else
            check_fail "Node '$NODE' lease is stale (${AGE}s ago) — kubelet may not be running"
        fi
    else
        LAST_HB=$(kubectl get node "$NODE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastHeartbeatTime}' 2>/dev/null)
        if [ -n "$LAST_HB" ]; then
            HB_EPOCH=$(date -d "$LAST_HB" +%s 2>/dev/null || \
                       date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_HB" +%s 2>/dev/null)
            AGE=$(( NOW_EPOCH - ${HB_EPOCH:-0} ))
            if [ -n "$HB_EPOCH" ] && [ "$AGE" -lt 300 ]; then
                check_pass "Node '$NODE' heartbeat is fresh (${AGE}s ago)"
            else
                check_fail "Node '$NODE' heartbeat is stale (${AGE}s ago)"
            fi
        else
            check_fail "Node '$NODE': cannot determine heartbeat time"
        fi
    fi

done

# ── Per-cause progress tracking ───────────────────────────────────────────────

ACTIVE_CAUSE=""
[ -f "$STATE_ACTIVE" ] && ACTIVE_CAUSE=$(tr -d '[:space:]' < "$STATE_ACTIVE" 2>/dev/null)

# If all checks passed and a cause was active → mark it done
if [ "$FAIL_COUNT" -eq 0 ] && [[ "$ACTIVE_CAUSE" =~ ^[1-5]$ ]]; then
    if ! is_done "$ACTIVE_CAUSE"; then
        echo "$ACTIVE_CAUSE" >> "$STATE_DONE"
    fi
    rm -f "$STATE_ACTIVE"
    ACTIVE_CAUSE=""
fi

DONE_COUNT=0
[ -f "$STATE_DONE" ] && DONE_COUNT=$(sort -u "$STATE_DONE" 2>/dev/null | grep -c '^[1-5]$' || true)

NEXT_CAUSE=""
for i in 1 2 3 4 5; do
    if ! is_done "$i"; then NEXT_CAUSE=$i; break; fi
done

# Progress table
echo ""
echo -e "  ${BOLD}Cause Progress — practice all 5 to complete Task 17:${NC}"
echo ""
for i in 1 2 3 4 5; do
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

echo -e "${BOLD}━━━ Verification Result: Task 17 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "\n  ${BOLD}${RED}✗  Node(s) not Ready — fix and run check again${NC}"
elif [ "$DONE_COUNT" -ge 5 ]; then
    echo -e "\n  ${BOLD}${GREEN}✓  TASK 17 — COMPLETE (all 5 root causes practiced)${NC}"
else
    echo -e "\n  ${BOLD}${YELLOW}◎  All nodes Ready — Progress: ${DONE_COUNT}/5 causes practiced${NC}"
    [ -n "$NEXT_CAUSE" ] && \
        echo -e "  Run ${CYAN}cause ${NEXT_CAUSE}${NC} to practice: ${CAUSE_LABELS[$NEXT_CAUSE]}"
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[ "$FAIL_COUNT" -eq 0 ]
