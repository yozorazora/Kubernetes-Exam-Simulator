#!/bin/bash
# Verify Task 03: Logging Sidecar
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 03: Logging Sidecar ══════════════════════════${NC}"
use_context "$CTX"

# 1. Pod legacy-app still exists
if kubectl get pod legacy-app -n audit &>/dev/null; then
    check_pass "Pod 'legacy-app' exists in namespace 'audit'"
else
    check_fail "Pod 'legacy-app' not found in namespace 'audit'"
    verify_summary "03"; [ "$FAIL_COUNT" -eq 0 ]; exit
fi

PODSPEC=$(kubectl get pod legacy-app -n audit -o json 2>/dev/null)

# 2. sidecar container exists
SIDECAR=$(echo "$PODSPEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
containers = d['spec'].get('containers',[])
names = [c['name'] for c in containers]
if 'sidecar' in names:
    print('found')
" 2>/dev/null)

if [ "$SIDECAR" = "found" ]; then
    check_pass "Sidecar container named 'sidecar' exists"
else
    check_fail "No container named 'sidecar' found in pod spec"
fi

# 3. sidecar uses busybox:1.36
SIDECAR_IMAGE=$(echo "$PODSPEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    if c['name'] == 'sidecar':
        print(c.get('image',''))
" 2>/dev/null)

if echo "$SIDECAR_IMAGE" | grep -q "busybox"; then
    check_pass "Sidecar uses busybox image: $SIDECAR_IMAGE"
else
    check_fail "Sidecar image should be busybox:1.36" "got: $SIDECAR_IMAGE"
fi

# 4. sidecar command includes tail -f
SIDECAR_CMD=$(echo "$PODSPEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    if c['name'] == 'sidecar':
        cmd = c.get('command', []) + c.get('args', [])
        print(' '.join(cmd))
" 2>/dev/null)

if echo "$SIDECAR_CMD" | grep -q "tail"; then
    check_pass "Sidecar command includes 'tail'"
else
    check_fail "Sidecar command should run 'tail -f /var/log/legacy-app.log'" "got: $SIDECAR_CMD"
fi

# 5. sidecar mounts a volume at /var/log
MOUNT=$(echo "$PODSPEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    if c['name'] == 'sidecar':
        for m in c.get('volumeMounts',[]):
            if m.get('mountPath') == '/var/log':
                print('found')
" 2>/dev/null)

if [ "$MOUNT" = "found" ]; then
    check_pass "Sidecar mounts volume at /var/log"
else
    check_fail "Sidecar does not mount a volume at /var/log"
fi

# 6. Pod is running (not crashlooping)
STATUS=$(kubectl get pod legacy-app -n audit -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$STATUS" = "Running" ]; then
    check_pass "Pod 'legacy-app' is Running"
else
    check_fail "Pod 'legacy-app' is not Running" "status: $STATUS"
fi

verify_summary "03"
[ "$FAIL_COUNT" -eq 0 ]
