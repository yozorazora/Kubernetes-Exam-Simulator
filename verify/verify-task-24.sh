#!/bin/bash
# Verify Task 24: Helm Fundamentals
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task24"
RELEASE="task24-nginx"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 24: Helm Fundamentals ═══════════════════════${NC}"
use_context "$CTX"

# ── Helm is installed (hard prerequisite for every part) ─────────────────────

if ! command -v helm &>/dev/null; then
    check_fail "helm is not installed or not in PATH"
    echo -e "     ${YELLOW}Install Helm: https://helm.sh/docs/intro/install/${NC}"
    echo ""
    echo -e "  ${BOLD}Checklist:${NC}"
    echo -e "  ${RED}✗${NC}  Part A — Repo + install     cannot check — helm missing"
    echo -e "  ${RED}✗${NC}  Part B — Upgrade             cannot check — helm missing"
    echo -e "  ${YELLOW}~${NC}  Part C — Inspect             cannot check — helm missing"
    echo -e "  ${RED}✗${NC}  Part D — Rollback            cannot check — helm missing"
    verify_summary "24"; exit 1
fi
check_pass "helm is installed: $(helm version --short 2>/dev/null)"

RELEASE_JSON=$(helm list -n "$NS" -o json 2>/dev/null)
RELEASE_FOUND=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
releases = json.load(sys.stdin)
names = [r.get('name','') for r in releases]
print('yes' if '$RELEASE' in names else 'no')
" 2>/dev/null)

# ── Part A: repo registered + release installed ───────────────────────────────

echo -e "\n  ${BOLD}Part A — Add repo + install release:${NC}"
PART_A_FAIL_START=$FAIL_COUNT

if helm repo list 2>/dev/null | grep -q "bitnami"; then
    check_pass "bitnami Helm repo is registered"
else
    check_fail "bitnami repo not found — run: helm repo add bitnami https://charts.bitnami.com/bitnami"
fi

if [ "$RELEASE_FOUND" = "yes" ]; then
    check_pass "Helm release '$RELEASE' exists in namespace $NS"

    RELEASE_STATUS=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
releases = json.load(sys.stdin)
for r in releases:
    if r.get('name') == '$RELEASE':
        print(r.get('status',''))
" 2>/dev/null)
    if [ "$RELEASE_STATUS" = "deployed" ]; then
        check_pass "Release '$RELEASE' status = deployed"
    else
        check_fail "Release '$RELEASE' status should be 'deployed', got '${RELEASE_STATUS:-unknown}'"
    fi

    POD_RUNNING=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [ "${POD_RUNNING:-0}" -ge 1 ]; then
        check_pass "At least ${POD_RUNNING} pod(s) Running in namespace $NS"
    else
        check_fail "No Running pods in namespace $NS — chart may still be deploying"
    fi
else
    check_fail "Helm release '$RELEASE' not found in namespace $NS" \
        "helm list -n $NS  to check what's deployed"
fi

PART_A_OK=0
[ "$FAIL_COUNT" -eq "$PART_A_FAIL_START" ] && PART_A_OK=1

# ── Part B: upgrade performed (revision >= 2 at some point) ──────────────────

echo -e "\n  ${BOLD}Part B — Upgrade release (replicaCount=2):${NC}"
PART_B_FAIL_START=$FAIL_COUNT

if [ "$RELEASE_FOUND" = "yes" ]; then
    REVISION=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
releases = json.load(sys.stdin)
for r in releases:
    if r.get('name') == '$RELEASE':
        print(r.get('revision',''))
" 2>/dev/null)

    if [ "${REVISION:-0}" -ge 2 ]; then
        check_pass "Release is at revision ${REVISION} (upgrade has been applied)"
    elif [ "${REVISION:-0}" -ge 1 ]; then
        check_fail "Release is still at revision 1 — run: helm upgrade $RELEASE bitnami/nginx -n $NS --set replicaCount=2"
    else
        check_fail "Cannot determine release revision"
    fi

    HISTORY_OUTPUT=$(helm history "$RELEASE" -n "$NS" 2>/dev/null)
    ALREADY_ROLLED_BACK="no"
    echo "$HISTORY_OUTPUT" | grep -qi "rollback" && ALREADY_ROLLED_BACK="yes"

    REPLICA_COUNT=$(kubectl -n "$NS" get deployment "$RELEASE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "$REPLICA_COUNT" = "2" ]; then
        check_pass "Deployment replicas = 2"
    elif [ "$ALREADY_ROLLED_BACK" = "yes" ]; then
        check_pass "Deployment replicas = ${REPLICA_COUNT:-unknown} (expected — release was rolled back in Part D)"
    else
        check_fail "Deployment replicas should be 2, got '${REPLICA_COUNT:-unknown}'"
    fi
else
    check_fail "Cannot check upgrade — release not installed (see Part A)"
fi

PART_B_OK=0
[ "$FAIL_COUNT" -eq "$PART_B_FAIL_START" ] && PART_B_OK=1

# ── Part C: inspect (read-only — not independently verifiable) ───────────────

echo -e "\n  ${BOLD}Part C — Inspect the release:${NC}"
echo -e "  ${YELLOW}~${NC}  Read-only step, not auto-verified — run these yourself:"
echo -e "     ${YELLOW}helm list -n $NS${NC}"
echo -e "     ${YELLOW}helm status $RELEASE -n $NS${NC}"
echo -e "     ${YELLOW}helm history $RELEASE -n $NS${NC}"

# ── Part D: rollback to revision 1 ────────────────────────────────────────────

echo -e "\n  ${BOLD}Part D — Rollback to revision 1:${NC}"
PART_D_FAIL_START=$FAIL_COUNT

if [ "$RELEASE_FOUND" = "yes" ]; then
    if [ "$ALREADY_ROLLED_BACK" = "yes" ]; then
        check_pass "Release history shows a rollback entry"
    else
        check_fail "No rollback found in release history — run: helm rollback $RELEASE 1 -n $NS"
    fi
else
    check_fail "Cannot check rollback — release not installed (see Part A)"
fi

PART_D_OK=0
[ "$FAIL_COUNT" -eq "$PART_D_FAIL_START" ] && PART_D_OK=1

# ── Checklist summary ──────────────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}Checklist:${NC}"
[ "$PART_A_OK" -eq 1 ] \
    && echo -e "  ${GREEN}✓${NC}  Part A — Repo + install      complete" \
    || echo -e "  ${RED}✗${NC}  Part A — Repo + install      incomplete"
[ "$PART_B_OK" -eq 1 ] \
    && echo -e "  ${GREEN}✓${NC}  Part B — Upgrade             complete" \
    || echo -e "  ${RED}✗${NC}  Part B — Upgrade             incomplete"
echo -e "  ${YELLOW}~${NC}  Part C — Inspect              manual step (see above)"
[ "$PART_D_OK" -eq 1 ] \
    && echo -e "  ${GREEN}✓${NC}  Part D — Rollback            complete" \
    || echo -e "  ${RED}✗${NC}  Part D — Rollback            incomplete"

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "24"
[ "$FAIL_COUNT" -eq 0 ]
