#!/bin/bash
# Verify Task 11: Multi-container Pod with Init Container
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 11: Multi-container Pod ══════════════════════${NC}"
use_context "$CTX"

# 1. Pod exists
if ! kubectl get pod kucc8 -n default &>/dev/null; then
    check_fail "Pod 'kucc8' not found in default namespace"
    check_fail "Pod running status cannot be checked" "Pod does not exist"
    check_fail "Init container 'init-cont' cannot be checked" "Pod does not exist"
    check_fail "Init container image cannot be checked" "Pod does not exist"
    check_fail "Container 'c1' cannot be checked" "Pod does not exist"
    check_fail "Container 'c2' cannot be checked" "Pod does not exist"
    check_fail "Shared volume 'workdir' cannot be checked" "Pod does not exist"
    check_fail "Init container volume mount cannot be checked" "Pod does not exist"
    verify_summary "11"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

check_pass "Pod 'kucc8' exists in default namespace"
POD=$(kubectl get pod kucc8 -n default -o json 2>/dev/null)

# 2. Pod is Running
STATUS=$(echo "$POD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
if [ "$STATUS" = "Running" ]; then
    check_pass "Pod status is Running"
else
    check_fail "Pod is not Running" "status: $STATUS"
fi

# 3. Init container named init-cont
INIT=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
inits = [c['name'] for c in d['spec'].get('initContainers',[])]
print('found' if 'init-cont' in inits else 'missing')
" 2>/dev/null)
if [ "$INIT" = "found" ]; then
    check_pass "Init container 'init-cont' exists"
else
    check_fail "Init container 'init-cont' not found"
fi

# 4. Init container uses busybox
INIT_IMG=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('initContainers',[]):
    if c['name'] == 'init-cont':
        print(c.get('image',''))
" 2>/dev/null)
if echo "$INIT_IMG" | grep -q "busybox"; then
    check_pass "Init container image is busybox: $INIT_IMG"
else
    check_fail "Init container image should be busybox:1.36" "got: $INIT_IMG"
fi

# 5. Container c1 exists (nginx)
C1=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
names = [c['name'] for c in d['spec'].get('containers',[])]
print('found' if 'c1' in names else 'missing')
" 2>/dev/null)
if [ "$C1" = "found" ]; then
    check_pass "Container 'c1' exists"
else
    check_fail "Container 'c1' not found"
fi

# 6. Container c2 exists (memcached)
C2=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
names = [c['name'] for c in d['spec'].get('containers',[])]
print('found' if 'c2' in names else 'missing')
" 2>/dev/null)
if [ "$C2" = "found" ]; then
    check_pass "Container 'c2' exists"
else
    check_fail "Container 'c2' not found"
fi

# 7. Shared volume 'workdir' exists
VOL=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
names = [v['name'] for v in d['spec'].get('volumes',[])]
print('found' if 'workdir' in names else 'missing')
" 2>/dev/null)
if [ "$VOL" = "found" ]; then
    check_pass "Shared volume 'workdir' is defined"
else
    check_fail "Volume 'workdir' not found in pod spec"
fi

# 8. Init container mounts workdir at /workdir
INIT_MOUNT=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('initContainers',[]):
    if c['name'] == 'init-cont':
        for m in c.get('volumeMounts',[]):
            if m.get('name') == 'workdir' and m.get('mountPath') == '/workdir':
                print('found')
" 2>/dev/null)
if [ "$INIT_MOUNT" = "found" ]; then
    check_pass "Init container mounts 'workdir' at /workdir"
else
    check_fail "Init container does not mount 'workdir' at /workdir"
fi

verify_summary "11"
[ "$FAIL_COUNT" -eq 0 ]
