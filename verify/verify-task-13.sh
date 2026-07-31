#!/bin/bash
# Verify Task 13: ResourceQuota
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 13: ResourceQuota ════════════════════════════${NC}"
use_context "$CTX"

# 1. ResourceQuota exists
if ! kubectl get resourcequota rq-test -n myspace &>/dev/null; then
    check_fail "ResourceQuota 'rq-test' not found in namespace 'myspace'"
    check_fail "pods limit cannot be checked" "ResourceQuota does not exist"
    check_fail "CPU quota cannot be checked" "ResourceQuota does not exist"
    check_fail "Memory quota cannot be checked" "ResourceQuota does not exist"
    verify_summary "13"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

check_pass "ResourceQuota 'rq-test' exists in namespace 'myspace'"
RQ=$(kubectl get resourcequota rq-test -n myspace -o json 2>/dev/null)

# 2. pods limit = 5
PODS=$(echo "$RQ" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['hard'].get('pods',''))" 2>/dev/null)
if [ "$PODS" = "5" ]; then
    check_pass "pods limit = 5"
else
    check_fail "pods limit should be 5" "got: $PODS"
fi

# 3. CPU request/limit = 300m
CPU=$(echo "$RQ" | python3 -c "
import sys,json
d=json.load(sys.stdin)
hard = d['spec']['hard']
# Check both requests.cpu and cpu
val = hard.get('requests.cpu', hard.get('cpu', ''))
print(val)
" 2>/dev/null)
if [ "$CPU" = "300m" ]; then
    check_pass "CPU quota = 300m"
else
    check_fail "CPU quota should be 300m" "got: $CPU"
fi

# 4. Memory request/limit = 600Mi
MEM=$(echo "$RQ" | python3 -c "
import sys,json
d=json.load(sys.stdin)
hard = d['spec']['hard']
val = hard.get('requests.memory', hard.get('memory', ''))
print(val)
" 2>/dev/null)
if [ "$MEM" = "600Mi" ]; then
    check_pass "Memory quota = 600Mi"
else
    check_fail "Memory quota should be 600Mi" "got: $MEM"
fi

verify_summary "13"
[ "$FAIL_COUNT" -eq 0 ]
