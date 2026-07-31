#!/bin/bash
# Verify Task 10: Node Drain + Uncordon
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="wk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 10: Node Drain + Uncordon ════════════════════${NC}"
use_context "$CTX"

# After draining AND uncordoning, the node should be Ready and schedulable
NODE="wk8s-worker"

# 1. Node exists
if kubectl get node "$NODE" &>/dev/null; then
    check_pass "Node '$NODE' exists"
else
    check_fail "Node '$NODE' not found"
    verify_summary "10"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

# 2. Node is Ready
CONDITION=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$CONDITION" = "True" ]; then
    check_pass "Node '$NODE' is Ready"
else
    check_fail "Node '$NODE' is not Ready" "condition: $CONDITION"
fi

# 3. Node is schedulable (not cordoned) — unschedulable field should be absent or false
UNSCHED=$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
if [ -z "$UNSCHED" ] || [ "$UNSCHED" = "false" ]; then
    check_pass "Node '$NODE' is schedulable (uncordoned)"
else
    check_fail "Node '$NODE' is still cordoned/unschedulable" \
        "Run: kubectl uncordon $NODE"
fi

verify_summary "10"
[ "$FAIL_COUNT" -eq 0 ]
