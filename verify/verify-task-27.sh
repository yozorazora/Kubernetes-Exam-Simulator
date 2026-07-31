#!/bin/bash
# Verify Task 27: Gateway API
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task27"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 27: Gateway API ═════════════════════════════${NC}"
use_context "$CTX"

# ── Gateway API CRDs are installed ────────────────────────────────────────────

if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    check_pass "Gateway API CRDs are installed"
else
    check_fail "Gateway API CRDs not found — install them first:" \
        "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
    verify_summary "27"; exit 1
fi

# ── Namespace ─────────────────────────────────────────────────────────────────

kubectl get namespace "$NS" &>/dev/null \
    && check_pass "Namespace '$NS' exists" \
    || check_fail "Namespace '$NS' not found"

# ── Part A: Backend pod + service ─────────────────────────────────────────────

echo -e "\n  ${BOLD}Part A — Backend:${NC}"

SERVER_PHASE=$(kubectl -n "$NS" get pod task27-server \
    -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$SERVER_PHASE" = "Running" ] \
    && check_pass "Pod 'task27-server' is Running" \
    || check_fail "Pod 'task27-server' is '${SERVER_PHASE:-not found}'"

SVC_EXISTS=$(kubectl -n "$NS" get svc task27-svc --no-headers 2>/dev/null | wc -l)
[ "${SVC_EXISTS:-0}" -ge 1 ] \
    && check_pass "Service 'task27-svc' exists in namespace $NS" \
    || check_fail "Service 'task27-svc' not found in namespace $NS"

# ── Part B: GatewayClass ──────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part B — GatewayClass:${NC}"

GWC_JSON=$(kubectl get gatewayclass task27-gwc -o json 2>/dev/null)
if [ -n "$GWC_JSON" ]; then
    check_pass "GatewayClass 'task27-gwc' exists"

    CONTROLLER=$(echo "$GWC_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('controllerName',''))" 2>/dev/null)
    [ "$CONTROLLER" = "example.com/task27-controller" ] \
        && check_pass "GatewayClass controllerName = example.com/task27-controller" \
        || check_fail "GatewayClass controllerName should be 'example.com/task27-controller', got '$CONTROLLER'"
else
    check_fail "GatewayClass 'task27-gwc' not found"
    check_fail "GatewayClass controllerName cannot be checked"
fi

# ── Part C: Gateway ───────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part C — Gateway:${NC}"

GW_JSON=$(kubectl get gateway task27-gateway -n "$NS" -o json 2>/dev/null)
if [ -n "$GW_JSON" ]; then
    check_pass "Gateway 'task27-gateway' exists in namespace $NS"

    GWC_REF=$(echo "$GW_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('gatewayClassName',''))" 2>/dev/null)
    [ "$GWC_REF" = "task27-gwc" ] \
        && check_pass "Gateway references GatewayClass 'task27-gwc'" \
        || check_fail "Gateway gatewayClassName should be 'task27-gwc', got '$GWC_REF'"

    LISTENER=$(echo "$GW_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for l in d['spec'].get('listeners',[]):
    if l.get('name') == 'http' and l.get('port') == 80 and l.get('protocol') == 'HTTP':
        print('found')
" 2>/dev/null)
    [ "$LISTENER" = "found" ] \
        && check_pass "Gateway has listener 'http' on port 80 / protocol HTTP" \
        || check_fail "Gateway listener should be named 'http', port 80, protocol HTTP"

    ALLOWED=$(echo "$GW_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for l in d['spec'].get('listeners',[]):
    ar = l.get('allowedRoutes',{}).get('namespaces',{}).get('from','')
    if ar == 'Same':
        print('found')
" 2>/dev/null)
    [ "$ALLOWED" = "found" ] \
        && check_pass "Gateway allowedRoutes.namespaces.from = Same" \
        || check_fail "Gateway allowedRoutes.namespaces.from should be 'Same'"
else
    check_fail "Gateway 'task27-gateway' not found in namespace $NS"
    check_fail "Gateway gatewayClassName cannot be checked"
    check_fail "Gateway listener cannot be checked"
    check_fail "Gateway allowedRoutes cannot be checked"
fi

# ── Part D: HTTPRoute ─────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part D — HTTPRoute:${NC}"

HR_JSON=$(kubectl get httproute task27-route -n "$NS" -o json 2>/dev/null)
if [ -n "$HR_JSON" ]; then
    check_pass "HTTPRoute 'task27-route' exists in namespace $NS"

    PARENT=$(echo "$HR_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in d['spec'].get('parentRefs',[]):
    if p.get('name') == 'task27-gateway':
        print('found')
" 2>/dev/null)
    [ "$PARENT" = "found" ] \
        && check_pass "HTTPRoute parentRef → task27-gateway" \
        || check_fail "HTTPRoute parentRefs should include task27-gateway"

    BACKEND=$(echo "$HR_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('rules',[]):
    for b in rule.get('backendRefs',[]):
        if b.get('name') == 'task27-svc' and b.get('port') == 80:
            print('found')
" 2>/dev/null)
    [ "$BACKEND" = "found" ] \
        && check_pass "HTTPRoute backend → task27-svc:80" \
        || check_fail "HTTPRoute backendRefs should target task27-svc on port 80"
else
    check_fail "HTTPRoute 'task27-route' not found in namespace $NS"
    check_fail "HTTPRoute parentRef cannot be checked"
    check_fail "HTTPRoute backend cannot be checked"
fi

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "27"
[ "$FAIL_COUNT" -eq 0 ]
