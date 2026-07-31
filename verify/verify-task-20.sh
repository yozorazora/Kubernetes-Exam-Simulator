#!/bin/bash
# Verify Task 20: Troubleshoot — Service & DNS Debugging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task20"
PASS_COUNT=0; FAIL_COUNT=0

STATE_ACTIVE="/tmp/cka20-active"
STATE_DONE="/tmp/cka20-done"

declare -a CAUSE_LABELS
CAUSE_LABELS[1]="Selector mismatch — no endpoints"
CAUSE_LABELS[2]="Wrong targetPort — connection refused despite endpoints"
CAUSE_LABELS[3]="CoreDNS scaled to zero — all DNS fails"
CAUSE_LABELS[4]="Wrong service port — client reaches wrong port"
CAUSE_LABELS[5]="Service in wrong namespace — short DNS name fails"

is_done() { grep -qx "$1" "$STATE_DONE" 2>/dev/null; }

echo -e "${BOLD}═══ Verifying Task 20: Service & DNS Debugging ══════════════════${NC}"
use_context "$CTX"

# ── Check pods are present ────────────────────────────────────────────────────

SERVER_PHASE=$(kubectl -n "$NS" get pod task20-server \
    -o jsonpath='{.status.phase}' 2>/dev/null)
CLIENT_PHASE=$(kubectl -n "$NS" get pod task20-client \
    -o jsonpath='{.status.phase}' 2>/dev/null)

[ "$SERVER_PHASE" = "Running" ] \
    && check_pass "Pod task20-server is Running" \
    || check_fail "Pod task20-server is '${SERVER_PHASE:-not found}' — run cause <N> first"

[ "$CLIENT_PHASE" = "Running" ] \
    && check_pass "Pod task20-client is Running" \
    || check_fail "Pod task20-client is '${CLIENT_PHASE:-not found}' — run cause <N> first"

# ── Check CoreDNS is healthy ───────────────────────────────────────────────────

COREDNS_READY=$(kubectl -n kube-system get deployment coredns \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "${COREDNS_READY:-0}" -ge 1 ]; then
    check_pass "CoreDNS has ${COREDNS_READY} ready replica(s)"
else
    check_fail "CoreDNS has 0 ready replicas — run: kubectl -n kube-system scale deploy coredns --replicas=2"
fi

# ── Check service exists in the correct namespace ─────────────────────────────

SVC_EXISTS=$(kubectl -n "$NS" get svc task20-svc --no-headers 2>/dev/null | wc -l)
if [ "${SVC_EXISTS}" -ge 1 ]; then
    check_pass "Service task20-svc exists in namespace $NS"
else
    check_fail "Service task20-svc not found in namespace $NS"
    # Check if it's in the wrong namespace
    WRONG_NS=$(kubectl get svc -A --no-headers 2>/dev/null | grep task20-svc | awk '{print $1}')
    [ -n "$WRONG_NS" ] && \
        echo -e "     ${YELLOW}Found in namespace '${WRONG_NS}' — delete it and recreate in ${NS}${NC}"
fi

# ── Check endpoints are populated ─────────────────────────────────────────────

EP_ADDRS=$(kubectl -n "$NS" get endpoints task20-svc \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
if [ -n "$EP_ADDRS" ]; then
    EP_PORT=$(kubectl -n "$NS" get endpoints task20-svc \
        -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null)
    check_pass "Service task20-svc has endpoints (${EP_ADDRS}:${EP_PORT})"
else
    check_fail "Service task20-svc has no endpoints — check selector matches pod labels"
    echo -e "     ${YELLOW}kubectl -n $NS get pods --show-labels${NC}"
    echo -e "     ${YELLOW}kubectl -n $NS describe svc task20-svc | grep Selector${NC}"
fi

# ── DNS resolution test ────────────────────────────────────────────────────────

if [ "$CLIENT_PHASE" = "Running" ] && [ "${COREDNS_READY:-0}" -ge 1 ]; then
    DNS_RESULT=$(kubectl -n "$NS" exec task20-client -- nslookup task20-svc 2>/dev/null)
    if echo "$DNS_RESULT" | grep -q "Address"; then
        check_pass "DNS: task20-svc resolves from task20-client"
    else
        check_fail "DNS: task20-svc cannot be resolved — check CoreDNS and service namespace"
    fi
else
    echo -e "  ${YELLOW}  ~${NC} Skipping DNS test (client pod not ready or CoreDNS down)"
fi

# ── End-to-end HTTP connectivity test ─────────────────────────────────────────

if [ "$CLIENT_PHASE" = "Running" ] && [ "${SVC_EXISTS}" -ge 1 ]; then
    HTTP_RESULT=$(kubectl -n "$NS" exec task20-client -- \
        wget -qO- --timeout=5 http://task20-svc/ 2>/dev/null)
    if echo "$HTTP_RESULT" | grep -qi "nginx\|html\|DOCTYPE"; then
        check_pass "HTTP: task20-client successfully reached task20-svc (nginx response)"
    else
        check_fail "HTTP: Cannot reach task20-svc — check targetPort and service port"
        echo -e "     ${YELLOW}kubectl -n $NS describe svc task20-svc | grep -E 'Port:|TargetPort:'${NC}"
    fi
else
    echo -e "  ${YELLOW}  ~${NC} Skipping HTTP test (client pod not ready)"
fi

# ── Per-cause progress tracking ───────────────────────────────────────────────

ACTIVE_CAUSE=""
[ -f "$STATE_ACTIVE" ] && ACTIVE_CAUSE=$(tr -d '[:space:]' < "$STATE_ACTIVE" 2>/dev/null)

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
echo -e "  ${BOLD}Cause Progress — practice all 5 to complete Task 20:${NC}"
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

echo -e "${BOLD}━━━ Verification Result: Task 20 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "\n  ${BOLD}${RED}✗  Service connectivity not restored — fix and run check again${NC}"
elif [ "$DONE_COUNT" -ge 5 ]; then
    echo -e "\n  ${BOLD}${GREEN}✓  TASK 20 — COMPLETE (all 5 causes practiced)${NC}"
else
    echo -e "\n  ${BOLD}${YELLOW}◎  All checks passed — Progress: ${DONE_COUNT}/5 causes practiced${NC}"
    [ -n "$NEXT_CAUSE" ] && \
        echo -e "  Run ${CYAN}cause ${NEXT_CAUSE}${NC} to practice: ${CAUSE_LABELS[$NEXT_CAUSE]}"
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[ "$FAIL_COUNT" -eq 0 ]
