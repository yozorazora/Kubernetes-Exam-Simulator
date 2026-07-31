#!/bin/bash
# Verify Task 14: ServiceAccount with ClusterRoleBinding
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 14: ServiceAccount + ClusterRoleBinding ══════${NC}"
use_context "$CTX"

# 1. ServiceAccount pvviewer
if kubectl get serviceaccount pvviewer -n default &>/dev/null; then
    check_pass "ServiceAccount 'pvviewer' exists in default"
else
    check_fail "ServiceAccount 'pvviewer' not found in default"
fi

# 2. ClusterRole pvviewer-role
if kubectl get clusterrole pvviewer-role &>/dev/null; then
    check_pass "ClusterRole 'pvviewer-role' exists"
else
    check_fail "ClusterRole 'pvviewer-role' not found"
fi

# 3. ClusterRole allows list on persistentvolumes
CR=$(kubectl get clusterrole pvviewer-role -o json 2>/dev/null)
ALLOWS=$(echo "$CR" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d.get('rules',[]):
    if 'persistentvolumes' in rule.get('resources',[]) and 'list' in rule.get('verbs',[]):
        print('found')
" 2>/dev/null)
if [ "$ALLOWS" = "found" ]; then
    check_pass "ClusterRole allows 'list' on persistentvolumes"
else
    check_fail "ClusterRole should allow 'list' on persistentvolumes"
fi

# 4. ClusterRoleBinding pvviewer-role-binding
if kubectl get clusterrolebinding pvviewer-role-binding &>/dev/null; then
    check_pass "ClusterRoleBinding 'pvviewer-role-binding' exists"
else
    check_fail "ClusterRoleBinding 'pvviewer-role-binding' not found"
fi

# 5. ClusterRoleBinding binds pvviewer-role to pvviewer SA
CRB=$(kubectl get clusterrolebinding pvviewer-role-binding -o json 2>/dev/null)
BOUND=$(echo "$CRB" | python3 -c "
import sys,json
d=json.load(sys.stdin)
role = d.get('roleRef',{}).get('name','')
sas = [(s.get('name',''), s.get('namespace','')) for s in d.get('subjects',[])]
if role == 'pvviewer-role' and ('pvviewer', 'default') in sas:
    print('found')
" 2>/dev/null)
if [ "$BOUND" = "found" ]; then
    check_pass "ClusterRoleBinding correctly binds pvviewer-role to pvviewer@default"
else
    check_fail "ClusterRoleBinding is not correctly configured"
fi

# 6. Pod pvviewer exists
if kubectl get pod pvviewer -n default &>/dev/null; then
    check_pass "Pod 'pvviewer' exists in default"
else
    check_fail "Pod 'pvviewer' not found in default"
fi

# 7. Pod uses pvviewer ServiceAccount
SA=$(kubectl get pod pvviewer -n default -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
if [ "$SA" = "pvviewer" ]; then
    check_pass "Pod uses ServiceAccount 'pvviewer'"
else
    check_fail "Pod should use ServiceAccount 'pvviewer'" "got: $SA"
fi

# 8. Permission test
CAN=$(kubectl auth can-i list persistentvolumes \
    --as=system:serviceaccount:default:pvviewer 2>/dev/null)
if [ "$CAN" = "yes" ]; then
    check_pass "ServiceAccount can list PersistentVolumes"
else
    check_fail "ServiceAccount cannot list PersistentVolumes"
fi

verify_summary "14"
[ "$FAIL_COUNT" -eq 0 ]
