#!/bin/bash
# Verify Task 16: StorageClass + PVC
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="wk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 16: StorageClass + PVC ═══════════════════════${NC}"
use_context "$CTX"

# 1-3. StorageClass checks
if kubectl get storageclass delayed-volume-sc &>/dev/null; then
    check_pass "StorageClass 'delayed-volume-sc' exists"
    SC=$(kubectl get storageclass delayed-volume-sc -o json 2>/dev/null)

    PROV=$(echo "$SC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('provisioner',''))" 2>/dev/null)
    if [ "$PROV" = "kubernetes.io/no-provisioner" ]; then
        check_pass "StorageClass provisioner = kubernetes.io/no-provisioner"
    else
        check_fail "StorageClass provisioner should be kubernetes.io/no-provisioner" "got: $PROV"
    fi

    VBM=$(echo "$SC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('volumeBindingMode',''))" 2>/dev/null)
    if [ "$VBM" = "WaitForFirstConsumer" ]; then
        check_pass "volumeBindingMode = WaitForFirstConsumer"
    else
        check_fail "volumeBindingMode should be WaitForFirstConsumer" "got: $VBM"
    fi
else
    check_fail "StorageClass 'delayed-volume-sc' not found"
    check_fail "StorageClass provisioner cannot be checked" "StorageClass does not exist"
    check_fail "volumeBindingMode cannot be checked" "StorageClass does not exist"
fi

# 4-8. PVC checks
if kubectl get pvc delayed-volume-pvc -n default &>/dev/null; then
    check_pass "PVC 'delayed-volume-pvc' exists in default"
    PVC=$(kubectl get pvc delayed-volume-pvc -n default -o json 2>/dev/null)

    REQ=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['resources']['requests'].get('storage',''))" 2>/dev/null)
    if [ "$REQ" = "1Gi" ]; then
        check_pass "PVC requests 1Gi"
    else
        check_fail "PVC should request 1Gi" "got: $REQ"
    fi

    AM=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d['spec'].get('accessModes',[])))" 2>/dev/null)
    if echo "$AM" | grep -q "ReadWriteOnce"; then
        check_pass "PVC accessMode = ReadWriteOnce"
    else
        check_fail "PVC accessMode should be ReadWriteOnce" "got: $AM"
    fi

    SC_NAME=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('storageClassName',''))" 2>/dev/null)
    if [ "$SC_NAME" = "delayed-volume-sc" ]; then
        check_pass "PVC uses storageClass 'delayed-volume-sc'"
    else
        check_fail "PVC storageClassName should be delayed-volume-sc" "got: $SC_NAME"
    fi

    STATUS=$(echo "$PVC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
    if [ "$STATUS" = "Pending" ] || [ "$STATUS" = "Bound" ]; then
        check_pass "PVC status is $STATUS (Pending is expected with WaitForFirstConsumer)"
    else
        check_fail "PVC status unexpected" "got: $STATUS"
    fi
else
    check_fail "PVC 'delayed-volume-pvc' not found in default"
    check_fail "PVC storage request cannot be checked" "PVC does not exist"
    check_fail "PVC accessMode cannot be checked" "PVC does not exist"
    check_fail "PVC storageClass reference cannot be checked" "PVC does not exist"
    check_fail "PVC status cannot be checked" "PVC does not exist"
fi

verify_summary "16"
[ "$FAIL_COUNT" -eq 0 ]
