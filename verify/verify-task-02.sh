#!/bin/bash
# Verify Task 02: NetworkPolicy
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="hk8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 02: NetworkPolicy ════════════════════════════${NC}"
use_context "$CTX"

# 1. NetworkPolicy exists
if kubectl get networkpolicy allow-from-internal -n fubar &>/dev/null; then
    check_pass "NetworkPolicy 'allow-from-internal' exists in namespace 'fubar'"
else
    check_fail "NetworkPolicy 'allow-from-internal' not found in namespace 'fubar'"
fi

NP=$(kubectl get networkpolicy allow-from-internal -n fubar -o json 2>/dev/null)
if [ -z "$NP" ]; then
    check_fail "podSelector cannot be checked" "NetworkPolicy does not exist"
    check_fail "policyTypes cannot be checked" "NetworkPolicy does not exist"
    check_fail "namespaceSelector for 'internal' cannot be checked" "NetworkPolicy does not exist"
    check_fail "port 9000 cannot be checked" "NetworkPolicy does not exist"
    verify_summary "02"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

# 2. Applies to all pods in fubar (podSelector: {})
PODSELECTOR=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['spec']['podSelector']))" 2>/dev/null)
if [ "$PODSELECTOR" = "{}" ]; then
    check_pass "podSelector is empty (applies to all pods in fubar)"
else
    check_fail "podSelector should be empty {}" "got: $PODSELECTOR"
fi

# 3. Ingress policy type is set
PTYPES=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d['spec'].get('policyTypes',[])))" 2>/dev/null)
if echo "$PTYPES" | grep -q "Ingress"; then
    check_pass "policyTypes includes Ingress"
else
    check_fail "policyTypes does not include Ingress" "got: $PTYPES"
fi

# 4. Ingress rule has namespaceSelector for 'internal'
NS_SELECTOR=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ingress = d['spec'].get('ingress', [])
for rule in ingress:
    for frm in rule.get('from', []):
        ns = frm.get('namespaceSelector', {}).get('matchLabels', {})
        if ns.get('kubernetes.io/metadata.name') == 'internal':
            print('found')
" 2>/dev/null)

if [ "$NS_SELECTOR" = "found" ]; then
    check_pass "namespaceSelector matches 'internal' namespace label"
else
    check_fail "namespaceSelector for namespace 'internal' not found" \
        "Ensure matchLabels: {kubernetes.io/metadata.name: internal}"
fi

# 5. Port 9000 is specified
PORT=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ingress = d['spec'].get('ingress', [])
for rule in ingress:
    for p in rule.get('ports', []):
        if p.get('port') == 9000:
            print('found')
" 2>/dev/null)

if [ "$PORT" = "found" ]; then
    check_pass "Ingress rule allows port 9000"
else
    check_fail "Ingress rule for port 9000 not found"
fi

verify_summary "02"
[ "$FAIL_COUNT" -eq 0 ]
