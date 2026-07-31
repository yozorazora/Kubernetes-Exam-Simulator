#!/bin/bash
# Verify Task 05: etcd Backup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 05: etcd Backup ══════════════════════════════${NC}"
use_context "$CTX"

CPNODE="k8s-control-plane"

# Check the snapshot file inside the control-plane container
SNAPSHOT_EXISTS=$(docker exec "$CPNODE" test -f /var/lib/backup/etcd-snapshot.db 2>/dev/null && echo "yes" || echo "no")

if [ "$SNAPSHOT_EXISTS" = "yes" ]; then
    check_pass "etcd snapshot file exists: /var/lib/backup/etcd-snapshot.db"
    SIZE=$(docker exec "$CPNODE" stat -c%s /var/lib/backup/etcd-snapshot.db 2>/dev/null || echo "0")
    if [ "${SIZE:-0}" -gt 1000 ]; then
        check_pass "Snapshot file size looks valid (${SIZE} bytes)"
    else
        check_fail "Snapshot file seems too small or empty" "size: $SIZE bytes"
    fi
else
    check_fail "etcd snapshot not found at /var/lib/backup/etcd-snapshot.db" \
        "Run the etcdctl snapshot save command inside the control-plane node"
    check_fail "Snapshot size cannot be verified — snapshot file missing" \
        "Complete Part A first: etcdctl snapshot save /var/lib/backup/etcd-snapshot.db"
fi

# Check etcd is still running
ETCD_RUNNING=$(kubectl --context=k8s get pod -n kube-system -l component=etcd \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$ETCD_RUNNING" = "Running" ]; then
    check_pass "etcd pod is still Running after backup"
else
    check_fail "etcd pod is not Running" "status: $ETCD_RUNNING"
fi

# Check cluster is still accessible
if kubectl --context=k8s get nodes &>/dev/null; then
    check_pass "Cluster is still accessible (API server responding)"
else
    check_fail "Cluster not accessible — etcd may have issues"
fi

echo ""
echo -e "  ${YELLOW}Note:${NC} Restore verification requires checking /var/lib/etcd-restored"
echo -e "  ${YELLOW}Note:${NC} Enter the node with: docker exec -it k8s-control-plane bash"

verify_summary "05"
[ "$FAIL_COUNT" -eq 0 ]
