#!/bin/bash
# Verify Task 07: Pod Scheduling with nodeSelector
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 07: Pod nodeSelector ════════════════════════${NC}"
use_context "$CTX"

# 1. Pod exists
if kubectl get pod nginx-kusc00401 -n default &>/dev/null; then
    check_pass "Pod 'nginx-kusc00401' exists"
    POD=$(kubectl get pod nginx-kusc00401 -n default -o json 2>/dev/null)

    IMAGE=$(echo "$POD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['containers'][0].get('image',''))" 2>/dev/null)
    if echo "$IMAGE" | grep -q "nginx"; then
        check_pass "Pod uses nginx image: $IMAGE"
    else
        check_fail "Pod image should be nginx" "got: $IMAGE"
    fi

    NS=$(echo "$POD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('nodeSelector',{}).get('disk',''))" 2>/dev/null)
    if [ "$NS" = "ssd" ]; then
        check_pass "nodeSelector disk=ssd is set"
    else
        check_fail "nodeSelector disk=ssd not found" "got disk=$NS"
    fi

    STATUS=$(echo "$POD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
    if [ "$STATUS" = "Running" ]; then
        check_pass "Pod is Running"
    else
        check_fail "Pod is not Running" "status: $STATUS — check that a node has label disk=ssd"
    fi

    NODE=$(echo "$POD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('nodeName',''))" 2>/dev/null)
    if [ -n "$NODE" ]; then
        LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.disk}' 2>/dev/null)
        if [ "$LABEL" = "ssd" ]; then
            check_pass "Pod scheduled on node '$NODE' which has label disk=ssd"
        else
            check_fail "Pod scheduled on node '$NODE' which does NOT have disk=ssd" "node labels: $(kubectl get node $NODE --show-labels 2>/dev/null | tail -1)"
        fi
    fi
else
    check_fail "Pod 'nginx-kusc00401' not found in default namespace"
    check_fail "Pod image cannot be checked" "Pod does not exist"
    check_fail "nodeSelector disk=ssd cannot be checked" "Pod does not exist"
    check_fail "Pod running status cannot be checked" "Pod does not exist"
    check_fail "Node label disk=ssd cannot be checked" "Pod does not exist"
fi

verify_summary "07"
[ "$FAIL_COUNT" -eq 0 ]
