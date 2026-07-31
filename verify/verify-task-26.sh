#!/bin/bash
# Verify Task 26: DaemonSet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task26"
DS_NAME="task26-ds"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 26: DaemonSet ═══════════════════════════════${NC}"
use_context "$CTX"

# ── Namespace ─────────────────────────────────────────────────────────────────

if kubectl get namespace "$NS" &>/dev/null; then
    check_pass "Namespace '$NS' exists"
else
    check_fail "Namespace '$NS' not found — run: kubectl create namespace $NS"
    verify_summary "26"; exit 1
fi

# ── DaemonSet exists ──────────────────────────────────────────────────────────

DS_JSON=$(kubectl get daemonset "$DS_NAME" -n "$NS" -o json 2>/dev/null)
if [ -n "$DS_JSON" ]; then
    check_pass "DaemonSet '$DS_NAME' exists in namespace $NS"
else
    check_fail "DaemonSet '$DS_NAME' not found in namespace $NS"
    verify_summary "26"; exit 1
fi

# ── DaemonSet kind ────────────────────────────────────────────────────────────

KIND=$(echo "$DS_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('kind',''))" 2>/dev/null)
[ "$KIND" = "DaemonSet" ] \
    && check_pass "Resource is a DaemonSet (not a Deployment)" \
    || check_fail "Resource kind should be DaemonSet, got '$KIND'"

# ── Label selector ────────────────────────────────────────────────────────────

DS_LABEL=$(echo "$DS_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
labels=d['spec']['selector'].get('matchLabels',{})
print(labels.get('app',''))
" 2>/dev/null)
[ "$DS_LABEL" = "$DS_NAME" ] \
    && check_pass "DaemonSet selector app=$DS_NAME" \
    || check_fail "DaemonSet selector should have app=$DS_NAME, got '$DS_LABEL'"

# ── Update strategy ───────────────────────────────────────────────────────────

UPDATE_TYPE=$(echo "$DS_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d['spec'].get('updateStrategy',{}).get('type',''))
" 2>/dev/null)
[ "$UPDATE_TYPE" = "RollingUpdate" ] \
    && check_pass "DaemonSet updateStrategy = RollingUpdate" \
    || check_fail "DaemonSet updateStrategy should be RollingUpdate, got '$UPDATE_TYPE'"

# ── Image check (Part C: should be updated to alpine) ────────────────────────

CURRENT_IMAGE=$(echo "$DS_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec']['template']['spec']['containers']:
    print(c.get('image',''))
    break
" 2>/dev/null)

if echo "$CURRENT_IMAGE" | grep -q "nginx:1.27.2-alpine"; then
    check_pass "DaemonSet image updated to $CURRENT_IMAGE (Part C complete)"
elif echo "$CURRENT_IMAGE" | grep -q "nginx"; then
    check_fail "Part C: DaemonSet image is '$CURRENT_IMAGE' — update to nginx:1.27.2-alpine" \
        "kubectl set image daemonset/$DS_NAME nginx=nginx:1.27.2-alpine -n $NS"
else
    check_fail "DaemonSet image '$CURRENT_IMAGE' not recognized as nginx"
fi

# ── Scheduling: desired = ready ────────────────────────────────────────────────

DESIRED=$(echo "$DS_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('desiredNumberScheduled',0))" 2>/dev/null)
READY=$(echo "$DS_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('numberReady',0))" 2>/dev/null)

if [ "${DESIRED:-0}" -ge 1 ] && [ "$DESIRED" = "$READY" ]; then
    check_pass "DaemonSet pods: ${READY}/${DESIRED} ready (one per schedulable node)"
elif [ "${DESIRED:-0}" -ge 1 ]; then
    check_fail "DaemonSet pods not all ready: ${READY}/${DESIRED}" \
        "kubectl rollout status daemonset/$DS_NAME -n $NS"
else
    check_fail "DaemonSet desiredNumberScheduled = 0 — no schedulable nodes found?"
fi

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "26"
[ "$FAIL_COUNT" -eq 0 ]
