#!/bin/bash
# Verify Task 12: Troubleshoot — Fix Broken Deployment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="bk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 12: Broken Deployment Fix ════════════════════${NC}"
use_context "$CTX"

# 1. Deployment exists
if kubectl get deployment nginx-deployment -n default &>/dev/null; then
    check_pass "Deployment 'nginx-deployment' exists"
else
    check_fail "Deployment 'nginx-deployment' not found"
    verify_summary "12"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

DEPLOY=$(kubectl get deployment nginx-deployment -n default -o json 2>/dev/null)

# 2. Desired replicas is 3
REPLICAS=$(echo "$DEPLOY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('replicas',0))" 2>/dev/null)
if [ "$REPLICAS" = "3" ]; then
    check_pass "Deployment has 3 desired replicas"
else
    check_fail "Deployment should have 3 replicas" "got: $REPLICAS"
fi

# 3. Available replicas = 3
AVAIL=$(echo "$DEPLOY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'].get('availableReplicas',0))" 2>/dev/null)
if [ "$AVAIL" = "3" ]; then
    check_pass "3 pods are available and running"
else
    check_fail "Not all 3 pods are available" "availableReplicas: $AVAIL — pods may still be starting"
fi

# 4. Image is valid (not using a broken image)
IMAGE=$(echo "$DEPLOY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
containers = d['spec']['template']['spec']['containers']
print(containers[0].get('image','')) if containers else print('')
" 2>/dev/null)
if echo "$IMAGE" | grep -qvE "does-not-exist|broken|bad|invalid|notfound"; then
    check_pass "Container image looks valid: $IMAGE"
else
    check_fail "Container image still appears broken: $IMAGE"
fi

# 5. No pods in ImagePullBackOff state
BAD_PODS=$(kubectl get pods -n default -l app=nginx-deployment \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null)
if echo "$BAD_PODS" | grep -qE "ImagePullBackOff|ErrImagePull"; then
    check_fail "Pods are still in ImagePullBackOff" "fix the image name first"
else
    check_pass "No pods in ImagePullBackOff state"
fi

verify_summary "12"
[ "$FAIL_COUNT" -eq 0 ]
