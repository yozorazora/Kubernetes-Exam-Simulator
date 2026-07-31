#!/bin/bash
# Verify Task 09: Deployment Scale + Resource Limits + Rollout/Rollback
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 09: Deployment Scale, Resources, Rollout ════${NC}"
use_context "$CTX"

# ── Deployment exists ─────────────────────────────────────────────────────────

if kubectl get deployment presentation -n ckad &>/dev/null; then
    check_pass "Deployment 'presentation' exists in namespace 'ckad'"
else
    check_fail "Deployment 'presentation' not found in namespace 'ckad'"
    verify_summary "09"; exit 1
fi

DEPLOY=$(kubectl get deployment presentation -n ckad -o json 2>/dev/null)

# ── Part A: Scale ─────────────────────────────────────────────────────────────

REPLICAS=$(echo "$DEPLOY" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('replicas',0))" 2>/dev/null)
[ "$REPLICAS" = "3" ] \
    && check_pass "Deployment replicas = 3" \
    || check_fail "Deployment replicas should be 3" "got: $REPLICAS"

AVAIL=$(echo "$DEPLOY" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['status'].get('availableReplicas',0))" 2>/dev/null)
[ "$AVAIL" = "3" ] \
    && check_pass "3 replicas available/running" \
    || check_fail "Available replicas should be 3" "got: $AVAIL"

# ── Part A: Resource limits ───────────────────────────────────────────────────

for field in "cpu requests 100m" "memory requests 128Mi" "cpu limits 200m" "memory limits 256Mi"; do
    res_type=$(echo "$field" | awk '{print $1}')
    res_category=$(echo "$field" | awk '{print $2}')
    expected=$(echo "$field" | awk '{print $3}')
    actual=$(echo "$DEPLOY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec']['template']['spec']['containers']:
    print(c.get('resources',{}).get('$res_category',{}).get('$res_type',''))
    break
" 2>/dev/null)
    [ "$actual" = "$expected" ] \
        && check_pass "${res_type^} ${res_category%s} = $expected" \
        || check_fail "${res_type^} ${res_category%s} should be $expected" "got: $actual"
done

# ── Part B + C: Rollout history ───────────────────────────────────────────────

echo -e "\n  ${BOLD}Part B+C — Rollout and Rollback:${NC}"

REVISION_COUNT=$(kubectl rollout history deployment/presentation \
    -n ckad 2>/dev/null | grep -c '^[0-9]' || echo 0)

if [ "${REVISION_COUNT:-0}" -ge 2 ]; then
    check_pass "Rollout history has ${REVISION_COUNT} revisions (rolling update was performed)"
else
    check_fail "Rollout history has ${REVISION_COUNT:-0} revision(s) — Part B: update the image first" \
        "kubectl set image deployment/presentation nginx=nginx:1.27.2-alpine -n ckad"
fi

# ── Part C: Image should be rolled back to nginx:latest ───────────────────────

CURRENT_IMAGE=$(echo "$DEPLOY" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
for c in d['spec']['template']['spec']['containers']:
    print(c.get('image',''))
    break
" 2>/dev/null)

if echo "$CURRENT_IMAGE" | grep -q "nginx:latest\|nginx:1.27"; then
    if echo "$CURRENT_IMAGE" | grep -q "nginx:latest"; then
        check_pass "Image rolled back to '$CURRENT_IMAGE' (rollback complete)"
    else
        check_fail "Image is '$CURRENT_IMAGE' — Part C: roll back with: kubectl rollout undo deployment/presentation -n ckad"
    fi
else
    check_fail "Image is '$CURRENT_IMAGE' — expected nginx:latest after rollback"
fi

# ── Final summary ─────────────────────────────────────────────────────────────

verify_summary "09"
[ "$FAIL_COUNT" -eq 0 ]
