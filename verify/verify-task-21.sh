#!/bin/bash
# Verify Task 21: Taints and Tolerations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task21"
PASS_COUNT=0; FAIL_COUNT=0

TAINT_KEY="dedicated"
TAINT_VALUE="blue"
TAINT_EFFECT="NoSchedule"

echo -e "${BOLD}═══ Verifying Task 21: Taints and Tolerations ══════════════════${NC}"
use_context "$CTX"

# ── Find the worker node ───────────────────────────────────────────────────────

WORKER_NODE=$(kubectl get nodes --no-headers 2>/dev/null \
    | grep -v "control-plane\|master" \
    | head -1 | awk '{print $1}')

if [ -z "$WORKER_NODE" ]; then
    check_fail "No worker node found in the k8s cluster"
    verify_summary "21"
    exit 1
fi

# ── Part 1: Taint on worker node ──────────────────────────────────────────────

TAINT_FOUND=$(kubectl get node "$WORKER_NODE" \
    -o jsonpath='{.spec.taints}' 2>/dev/null \
    | grep -o "\"${TAINT_KEY}\"" | head -1)

TAINT_DETAIL=$(kubectl get node "$WORKER_NODE" \
    -o jsonpath='{.spec.taints[*]}' 2>/dev/null)

if echo "$TAINT_DETAIL" | grep -q "${TAINT_KEY}"; then
    # Check the exact value and effect
    ACTUAL_VALUE=$(kubectl get node "$WORKER_NODE" \
        -o jsonpath="{.spec.taints[?(@.key==\"${TAINT_KEY}\")].value}" 2>/dev/null)
    ACTUAL_EFFECT=$(kubectl get node "$WORKER_NODE" \
        -o jsonpath="{.spec.taints[?(@.key==\"${TAINT_KEY}\")].effect}" 2>/dev/null)

    if [ "$ACTUAL_VALUE" = "$TAINT_VALUE" ] && [ "$ACTUAL_EFFECT" = "$TAINT_EFFECT" ]; then
        check_pass "Node '$WORKER_NODE' has taint ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}"
    else
        check_fail "Node '$WORKER_NODE' has taint key '${TAINT_KEY}' but wrong value/effect" \
            "got value='${ACTUAL_VALUE}' effect='${ACTUAL_EFFECT}', want value='${TAINT_VALUE}' effect='${TAINT_EFFECT}'"
    fi
else
    check_fail "Node '$WORKER_NODE' does NOT have the required taint '${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}'"
    echo -e "     ${YELLOW}Run: kubectl taint node $WORKER_NODE ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}${NC}"
fi

# ── Part 2: pod-no-toleration must be Pending ─────────────────────────────────

NO_TOL_PHASE=$(kubectl -n "$NS" get pod pod-no-toleration \
    -o jsonpath='{.status.phase}' 2>/dev/null)

if [ -z "$NO_TOL_PHASE" ]; then
    check_fail "Pod 'pod-no-toleration' not found in namespace $NS"
    echo -e "     ${YELLOW}Create it without tolerations and it should stay Pending${NC}"
elif [ "$NO_TOL_PHASE" = "Pending" ]; then
    check_pass "Pod 'pod-no-toleration' is Pending (taint is blocking it correctly)"
else
    # Pod might have scheduled on control-plane — check which node it's on
    POD_NODE=$(kubectl -n "$NS" get pod pod-no-toleration \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    if echo "$POD_NODE" | grep -q "control-plane\|master"; then
        check_fail "Pod 'pod-no-toleration' scheduled on control-plane node (${POD_NODE}) — it should be Pending" \
            "Ensure the pod has NO toleration for ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}"
    else
        check_fail "Pod 'pod-no-toleration' is ${NO_TOL_PHASE} on node '${POD_NODE:-unknown}' — expected Pending" \
            "Check that the pod has no tolerations: kubectl -n $NS get pod pod-no-toleration -o yaml | grep -A5 tolerations"
    fi
fi

# ── Part 3: pod-tolerant must be Running on the tainted worker node ───────────

TOL_PHASE=$(kubectl -n "$NS" get pod pod-tolerant \
    -o jsonpath='{.status.phase}' 2>/dev/null)

if [ -z "$TOL_PHASE" ]; then
    check_fail "Pod 'pod-tolerant' not found in namespace $NS"
    echo -e "     ${YELLOW}Create it with a toleration for ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}${NC}"
elif [ "$TOL_PHASE" = "Running" ]; then
    check_pass "Pod 'pod-tolerant' is Running"

    # Confirm it scheduled on the tainted worker node
    TOL_NODE=$(kubectl -n "$NS" get pod pod-tolerant \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    if [ "$TOL_NODE" = "$WORKER_NODE" ]; then
        check_pass "Pod 'pod-tolerant' is running on tainted node '$WORKER_NODE'"
    else
        check_fail "Pod 'pod-tolerant' is running on '${TOL_NODE}' — expected '$WORKER_NODE'" \
            "The toleration should allow it to land on the tainted worker node"
    fi

    # Confirm toleration is actually set
    TOL_KEY=$(kubectl -n "$NS" get pod pod-tolerant \
        -o jsonpath="{.spec.tolerations[?(@.key==\"${TAINT_KEY}\")].key}" 2>/dev/null)
    if [ -n "$TOL_KEY" ]; then
        check_pass "Pod 'pod-tolerant' has toleration for key '${TAINT_KEY}'"
    else
        # Pod might be running due to a global toleration (operator: Exists with no key)
        TOL_EXISTS=$(kubectl -n "$NS" get pod pod-tolerant \
            -o jsonpath='{.spec.tolerations}' 2>/dev/null)
        [ -n "$TOL_EXISTS" ] \
            && check_pass "Pod 'pod-tolerant' has toleration (broad match)" \
            || check_fail "Pod 'pod-tolerant' has no tolerations set"
    fi
else
    check_fail "Pod 'pod-tolerant' is ${TOL_PHASE} — expected Running" \
        "Check toleration is correctly set: kubectl -n $NS describe pod pod-tolerant | grep -A5 Tolerations"
    check_fail "Cannot verify pod node placement — pod is not Running"
    check_fail "Cannot verify toleration key — pod is not Running"
fi

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "21"
[ "$FAIL_COUNT" -eq 0 ]
