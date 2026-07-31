#!/bin/bash
# Verify Task 06: PV + PVC
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="wk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 06: PersistentVolume + PVC ═══════════════════${NC}"
use_context "$CTX"

# 1-4. PV checks
if kubectl get pv app-config &>/dev/null; then
    check_pass "PersistentVolume 'app-config' exists"
    PV=$(kubectl get pv app-config -o json 2>/dev/null)

    CAP=$(echo "$PV" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['capacity'].get('storage',''))" 2>/dev/null)
    if [ "$CAP" = "2Gi" ]; then
        check_pass "PV capacity is 2Gi"
    else
        check_fail "PV capacity should be 2Gi" "got: $CAP"
    fi

    AM=$(echo "$PV" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d['spec'].get('accessModes',[])))" 2>/dev/null)
    if echo "$AM" | grep -q "ReadWriteMany"; then
        check_pass "PV access mode is ReadWriteMany"
    else
        check_fail "PV access mode should be ReadWriteMany" "got: $AM"
    fi

    PATH_VAL=$(echo "$PV" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('hostPath',{}).get('path',''))" 2>/dev/null)
    if [ "$PATH_VAL" = "/srv/app-config" ]; then
        check_pass "PV hostPath is /srv/app-config"
    else
        check_fail "PV hostPath should be /srv/app-config" "got: $PATH_VAL"
    fi
else
    check_fail "PersistentVolume 'app-config' not found"
    check_fail "PV capacity cannot be checked" "PV does not exist"
    check_fail "PV access mode cannot be checked" "PV does not exist"
    check_fail "PV hostPath cannot be checked" "PV does not exist"
fi

# 5-7. PVC checks
if kubectl get pvc pvc-app-config -n default &>/dev/null; then
    check_pass "PersistentVolumeClaim 'pvc-app-config' exists in default"
    PVC=$(kubectl get pvc pvc-app-config -n default -o json 2>/dev/null)

    REQ=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['resources']['requests'].get('storage',''))" 2>/dev/null)
    if [ "$REQ" = "2Gi" ]; then
        check_pass "PVC requests 2Gi"
    else
        check_fail "PVC should request 2Gi" "got: $REQ"
    fi

    STATUS=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
    if [ "$STATUS" = "Bound" ]; then
        check_pass "PVC is Bound to PV"
    else
        check_fail "PVC is not Bound" "status: $STATUS (wait a few seconds and retry)"
    fi
else
    check_fail "PersistentVolumeClaim 'pvc-app-config' not found in default"
    check_fail "PVC storage request cannot be checked" "PVC does not exist"
    check_fail "PVC bound status cannot be checked" "PVC does not exist"
fi

verify_summary "06"
[ "$FAIL_COUNT" -eq 0 ]
