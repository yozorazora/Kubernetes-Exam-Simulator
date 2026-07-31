#!/bin/bash
# Verify Task 04: Cluster Upgrade
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="wk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 04: Cluster Upgrade ══════════════════════════${NC}"
use_context "$CTX"

CPNODE=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# 1. Control-plane node exists
if [ -n "$CPNODE" ]; then
    check_pass "Control-plane node found: $CPNODE"
else
    check_fail "No control-plane node found"
    verify_summary "04"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

# 2. Control-plane is Ready
CONDITION=$(kubectl get node "$CPNODE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$CONDITION" = "True" ]; then
    check_pass "Control-plane node is Ready"
else
    check_fail "Control-plane node is not Ready" "uncordon after upgrade?"
fi

# 3. Control-plane is schedulable (uncordoned after upgrade)
UNSCHED=$(kubectl get node "$CPNODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
if [ -z "$UNSCHED" ] || [ "$UNSCHED" = "false" ]; then
    check_pass "Control-plane is schedulable (uncordoned)"
else
    check_fail "Control-plane is still cordoned" "run: kubectl uncordon $CPNODE"
fi

# 4. kubelet version on control-plane
K_VER=$(kubectl get node "$CPNODE" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
if echo "$K_VER" | grep -q "v1.32"; then
    check_pass "Control-plane kubelet is v1.32.x: $K_VER"
else
    check_fail "Control-plane kubelet should be v1.32.x" \
        "current: $K_VER — note: kind clusters may not support in-place upgrade"
fi

echo ""
echo -e "  ${YELLOW}Note:${NC} Target is v1.32.x (the worker's version) — the task's kind cluster"
echo -e "  ${YELLOW}Note:${NC} has the real pkgs.k8s.io v1.32 apt repo configured, so genuine"
echo -e "  ${YELLOW}Note:${NC} apt-mark/apt-get/kubeadm upgrade commands work as shown in the task."

verify_summary "04"
[ "$FAIL_COUNT" -eq 0 ]
