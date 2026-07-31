#!/bin/bash
# Verify Task 08: Ingress
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 08: Ingress ══════════════════════════════════${NC}"
use_context "$CTX"

# 1. Ingress exists
if kubectl get ingress pong -n ing-internal &>/dev/null; then
    check_pass "Ingress 'pong' exists in namespace 'ing-internal'"
    ING=$(kubectl get ingress pong -n ing-internal -o json 2>/dev/null)

    PATH_VAL=$(echo "$ING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('rules',[]):
    for path in rule.get('http',{}).get('paths',[]):
        if path.get('path') == '/hello':
            print('found')
" 2>/dev/null)
    if [ "$PATH_VAL" = "found" ]; then
        check_pass "Ingress path '/hello' is defined"
    else
        check_fail "Ingress path '/hello' not found"
    fi

    SVC=$(echo "$ING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('rules',[]):
    for path in rule.get('http',{}).get('paths',[]):
        svc = path.get('backend',{}).get('service',{}).get('name','')
        if svc:
            print(svc)
" 2>/dev/null)
    if [ "$SVC" = "hi" ]; then
        check_pass "Backend service is 'hi'"
    else
        check_fail "Backend service should be 'hi'" "got: $SVC"
    fi

    PORT=$(echo "$ING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('rules',[]):
    for path in rule.get('http',{}).get('paths',[]):
        port = path.get('backend',{}).get('service',{}).get('port',{}).get('number',0)
        if port:
            print(port)
" 2>/dev/null)
    if [ "$PORT" = "5678" ]; then
        check_pass "Backend port is 5678"
    else
        check_fail "Backend port should be 5678" "got: $PORT"
    fi

    PTYPE=$(echo "$ING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('rules',[]):
    for path in rule.get('http',{}).get('paths',[]):
        if path.get('path') == '/hello':
            print(path.get('pathType',''))
" 2>/dev/null)
    if [ "$PTYPE" = "Prefix" ]; then
        check_pass "PathType is Prefix"
    else
        check_fail "PathType should be 'Prefix'" "got: $PTYPE"
    fi
else
    check_fail "Ingress 'pong' not found in namespace 'ing-internal'"
    check_fail "Ingress path '/hello' cannot be checked" "Ingress does not exist"
    check_fail "Backend service cannot be checked" "Ingress does not exist"
    check_fail "Backend port cannot be checked" "Ingress does not exist"
    check_fail "PathType cannot be checked" "Ingress does not exist"
fi

verify_summary "08"
[ "$FAIL_COUNT" -eq 0 ]
