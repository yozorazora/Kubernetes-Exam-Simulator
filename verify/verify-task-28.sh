#!/bin/bash
# Verify Task 28: Horizontal Pod Autoscaler (HPA)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task28"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 28: Horizontal Pod Autoscaler ════════════════${NC}"
use_context "$CTX"

# ── Namespace ─────────────────────────────────────────────────────────────────

kubectl get namespace "$NS" &>/dev/null \
    && check_pass "Namespace '$NS' exists" \
    || { check_fail "Namespace '$NS' not found"; verify_summary "28"; exit 1; }

# ── Part A: Deployment with resource requests ─────────────────────────────────

echo -e "\n  ${BOLD}Part A — Deployment:${NC}"

DEPLOY_JSON=$(kubectl get deployment task28-deploy -n "$NS" -o json 2>/dev/null)
if [ -n "$DEPLOY_JSON" ]; then
    check_pass "Deployment 'task28-deploy' exists in namespace $NS"

    DEPLOY_LABEL=$(echo "$DEPLOY_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d['spec']['selector'].get('matchLabels',{}).get('app',''))
" 2>/dev/null)
    [ "$DEPLOY_LABEL" = "task28-deploy" ] \
        && check_pass "Deployment selector label app=task28-deploy" \
        || check_fail "Deployment selector should have app=task28-deploy, got '$DEPLOY_LABEL'"

    CPU_REQ=$(echo "$DEPLOY_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec']['template']['spec']['containers']:
    print(c.get('resources',{}).get('requests',{}).get('cpu',''))
    break
" 2>/dev/null)
    if [ -n "$CPU_REQ" ]; then
        check_pass "Deployment has CPU request: $CPU_REQ (required for HPA)"
    else
        check_fail "Deployment containers have no CPU request — HPA needs requests to calculate utilization"
    fi
else
    check_fail "Deployment 'task28-deploy' not found in namespace $NS"
    check_fail "Deployment label cannot be checked"
    check_fail "Deployment CPU request cannot be checked"
fi

# ── Part B: HPA ───────────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part B — HPA:${NC}"

HPA_JSON=$(kubectl get hpa task28-hpa -n "$NS" -o json 2>/dev/null)
if [ -n "$HPA_JSON" ]; then
    check_pass "HPA 'task28-hpa' exists in namespace $NS"

    # Check target reference
    HPA_TARGET=$(echo "$HPA_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ref=d['spec'].get('scaleTargetRef',{})
print(ref.get('name',''))
" 2>/dev/null)
    [ "$HPA_TARGET" = "task28-deploy" ] \
        && check_pass "HPA targets Deployment 'task28-deploy'" \
        || check_fail "HPA scaleTargetRef should be 'task28-deploy', got '$HPA_TARGET'"

    # Check minReplicas
    HPA_MIN=$(echo "$HPA_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('minReplicas',''))" 2>/dev/null)
    [ "$HPA_MIN" = "2" ] \
        && check_pass "HPA minReplicas = 2" \
        || check_fail "HPA minReplicas should be 2, got '${HPA_MIN:-not set}'"

    # Check maxReplicas
    HPA_MAX=$(echo "$HPA_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('maxReplicas',''))" 2>/dev/null)
    [ "$HPA_MAX" = "5" ] \
        && check_pass "HPA maxReplicas = 5" \
        || check_fail "HPA maxReplicas should be 5, got '${HPA_MAX:-not set}'"

    # Check CPU target — works for both autoscaling/v1 and autoscaling/v2
    CPU_TARGET=$(echo "$HPA_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
# autoscaling/v1 stores as targetCPUUtilizationPercentage
v1_target = d['spec'].get('targetCPUUtilizationPercentage','')
if v1_target:
    print(v1_target)
    exit()
# autoscaling/v2 stores in metrics array
for m in d['spec'].get('metrics',[]):
    if m.get('type') == 'Resource':
        r = m.get('resource',{})
        if r.get('name') == 'cpu':
            target = r.get('target',{})
            print(target.get('averageUtilization',''))
            exit()
" 2>/dev/null)
    [ "$CPU_TARGET" = "50" ] \
        && check_pass "HPA target CPU utilization = 50%" \
        || check_fail "HPA CPU target should be 50%, got '${CPU_TARGET:-not found}'"
else
    check_fail "HPA 'task28-hpa' not found in namespace $NS"
    check_fail "HPA target reference cannot be checked"
    check_fail "HPA minReplicas cannot be checked"
    check_fail "HPA maxReplicas cannot be checked"
    check_fail "HPA CPU target cannot be checked"
fi

# ── Part C: HPA has scaled to at least minReplicas ────────────────────────────

echo -e "\n  ${BOLD}Part C — Current state:${NC}"

CURRENT_REPLICAS=$(kubectl get deployment task28-deploy -n "$NS" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "${CURRENT_REPLICAS:-0}" -ge 2 ]; then
    check_pass "Deployment has ${CURRENT_REPLICAS} ready replicas (HPA enforcing minReplicas=2)"
else
    echo -e "  ${YELLOW}  ~${NC} Deployment has ${CURRENT_REPLICAS:-0} ready replicas — HPA may still be initializing"
    echo -e "     ${DIM}(HPA scales to minReplicas within ~30 seconds)${NC}"
fi

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "28"
[ "$FAIL_COUNT" -eq 0 ]
