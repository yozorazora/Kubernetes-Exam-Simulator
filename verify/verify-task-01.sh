#!/bin/bash
# Verify Task 01: RBAC — ClusterRole + RoleBinding
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 01: RBAC ════════════════════════════════════${NC}"
use_context "$CTX"

# 1. ClusterRole exists
if kubectl get clusterrole deployment-clusterrole &>/dev/null; then
    check_pass "ClusterRole 'deployment-clusterrole' exists"
else
    check_fail "ClusterRole 'deployment-clusterrole' not found"
fi

# 2. ClusterRole has create verb on deployments
VERBS=$(kubectl get clusterrole deployment-clusterrole -o jsonpath='{.rules[*].verbs[*]}' 2>/dev/null)
if echo "$VERBS" | grep -qw "create"; then
    check_pass "ClusterRole allows 'create' verb"
else
    check_fail "ClusterRole missing 'create' verb" "verbs found: $VERBS"
fi

# 3. ClusterRole covers correct resources
RESOURCES=$(kubectl get clusterrole deployment-clusterrole -o jsonpath='{.rules[*].resources[*]}' 2>/dev/null)
for res in deployments statefulsets daemonsets; do
    if echo "$RESOURCES" | grep -qi "$res"; then
        check_pass "ClusterRole covers resource: $res"
    else
        check_fail "ClusterRole missing resource: $res" "resources found: $RESOURCES"
    fi
done

# 4. ServiceAccount exists in app-team
if kubectl get serviceaccount cicd-token -n app-team &>/dev/null; then
    check_pass "ServiceAccount 'cicd-token' exists in namespace 'app-team'"
else
    check_fail "ServiceAccount 'cicd-token' not found in namespace 'app-team'"
fi

# 5. RoleBinding (not ClusterRoleBinding) binds the ClusterRole to the SA
BINDING=$(kubectl get rolebinding -n app-team -o json 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('roleRef', {}).get('name') == 'deployment-clusterrole':
        for subj in item.get('subjects', []):
            if subj.get('name') == 'cicd-token' and subj.get('namespace') == 'app-team':
                print('found')
" 2>/dev/null)

if [ "$BINDING" = "found" ]; then
    check_pass "RoleBinding binds 'deployment-clusterrole' to 'cicd-token' in 'app-team'"
else
    check_fail "No RoleBinding found binding ClusterRole to ServiceAccount in app-team"
fi

# 6. Permission test — can create deployments in app-team
CAN=$(kubectl auth can-i create deployments \
    --as=system:serviceaccount:app-team:cicd-token \
    -n app-team 2>/dev/null)
if [ "$CAN" = "yes" ]; then
    check_pass "ServiceAccount can create Deployments in app-team"
else
    check_fail "ServiceAccount cannot create Deployments in app-team" "auth can-i returned: $CAN"
fi

# 7. Permission test — cannot delete in app-team
CANNOT=$(kubectl auth can-i delete deployments \
    --as=system:serviceaccount:app-team:cicd-token \
    -n app-team 2>/dev/null)
if [ "$CANNOT" = "no" ]; then
    check_pass "ServiceAccount correctly CANNOT delete Deployments"
else
    check_fail "ServiceAccount has unexpected delete permission"
fi

verify_summary "01"
[ "$FAIL_COUNT" -eq 0 ]
