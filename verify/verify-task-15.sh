#!/bin/bash
# Verify Task 15: ConfigMaps and Secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 15: ConfigMaps and Secrets ══════════════════${NC}"
use_context "$CTX"

# ── Part A: ConfigMap ─────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part A+B — ConfigMap:${NC}"

CM=$(kubectl get configmap ckad-config -n default -o json 2>/dev/null)
if [ -n "$CM" ]; then
    check_pass "ConfigMap 'ckad-config' exists in default"
    EXAM_MODE=$(echo "$CM" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('EXAM_MODE',''))" 2>/dev/null)
    [ "$EXAM_MODE" = "CKA" ] \
        && check_pass "ConfigMap has EXAM_MODE=CKA" \
        || check_fail "ConfigMap should have EXAM_MODE=CKA" "got: '$EXAM_MODE'"

    CT=$(echo "$CM" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('CLUSTER_TYPE',''))" 2>/dev/null)
    [ -n "$CT" ] \
        && check_pass "ConfigMap has CLUSTER_TYPE=$CT" \
        || check_fail "ConfigMap should have CLUSTER_TYPE key"
else
    check_fail "ConfigMap 'ckad-config' not found in default"
    check_fail "EXAM_MODE key cannot be checked"
    check_fail "CLUSTER_TYPE key cannot be checked"
fi

# ── Part B: configmap-pod ─────────────────────────────────────────────────────

POD_CM=$(kubectl get pod configmap-pod -n default -o json 2>/dev/null)
if [ -n "$POD_CM" ]; then
    check_pass "Pod 'configmap-pod' exists"
    CM_STATUS=$(echo "$POD_CM" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
    [ "$CM_STATUS" = "Running" ] \
        && check_pass "Pod 'configmap-pod' is Running" \
        || check_fail "Pod 'configmap-pod' is not Running" "status: $CM_STATUS"

    ENVFROM=$(echo "$POD_CM" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    for ef in c.get('envFrom',[]):
        if ef.get('configMapRef',{}).get('name') == 'ckad-config':
            print('found')
" 2>/dev/null)
    [ "$ENVFROM" = "found" ] \
        && check_pass "Pod 'configmap-pod' uses envFrom → ckad-config" \
        || check_fail "Pod 'configmap-pod' does not reference ckad-config via envFrom"
else
    check_fail "Pod 'configmap-pod' not found in default"
    check_fail "configmap-pod running status cannot be checked"
    check_fail "configmap-pod envFrom cannot be checked"
fi

# ── Part C: Secret ────────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part C+D — Secret:${NC}"

SEC=$(kubectl get secret ckad-secret -n default -o json 2>/dev/null)
if [ -n "$SEC" ]; then
    check_pass "Secret 'ckad-secret' exists in default"

    DB_USER_B64=$(echo "$SEC" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('DB_USER',''))" 2>/dev/null)
    DB_USER=$(echo "$DB_USER_B64" | base64 -d 2>/dev/null)
    [ "$DB_USER" = "admin" ] \
        && check_pass "Secret has DB_USER=admin" \
        || check_fail "Secret DB_USER should decode to 'admin'" "decoded: '$DB_USER'"

    DB_PASS_B64=$(echo "$SEC" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('DB_PASSWORD',''))" 2>/dev/null)
    DB_PASS=$(echo "$DB_PASS_B64" | base64 -d 2>/dev/null)
    [ "$DB_PASS" = "s3cr3t" ] \
        && check_pass "Secret has DB_PASSWORD=s3cr3t" \
        || check_fail "Secret DB_PASSWORD should decode to 's3cr3t'" "decoded: '$DB_PASS'"
else
    check_fail "Secret 'ckad-secret' not found in default — run Part C first"
    check_fail "DB_USER cannot be checked"
    check_fail "DB_PASSWORD cannot be checked"
fi

# ── Part D: secret-pod ────────────────────────────────────────────────────────

POD_SEC=$(kubectl get pod secret-pod -n default -o json 2>/dev/null)
if [ -n "$POD_SEC" ]; then
    check_pass "Pod 'secret-pod' exists"

    SEC_STATUS=$(echo "$POD_SEC" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['status'].get('phase',''))" 2>/dev/null)
    [ "$SEC_STATUS" = "Running" ] \
        && check_pass "Pod 'secret-pod' is Running" \
        || check_fail "Pod 'secret-pod' is not Running" "status: $SEC_STATUS"

    # Check envFrom secretRef
    SENVFROM=$(echo "$POD_SEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    for ef in c.get('envFrom',[]):
        if ef.get('secretRef',{}).get('name') == 'ckad-secret':
            print('found')
" 2>/dev/null)
    [ "$SENVFROM" = "found" ] \
        && check_pass "Pod 'secret-pod' uses envFrom → ckad-secret (env vars)" \
        || check_fail "Pod 'secret-pod' should reference ckad-secret via envFrom.secretRef"

    # Check volume mount at /etc/secret-data
    VMOUNT=$(echo "$POD_SEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    for vm in c.get('volumeMounts',[]):
        if vm.get('mountPath') == '/etc/secret-data':
            print('found')
" 2>/dev/null)
    [ "$VMOUNT" = "found" ] \
        && check_pass "Pod 'secret-pod' has volumeMount at /etc/secret-data" \
        || check_fail "Pod 'secret-pod' missing volumeMount at /etc/secret-data"

    # Check volume references the secret
    SVOL=$(echo "$POD_SEC" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d['spec'].get('volumes',[]):
    if v.get('secret',{}).get('secretName') == 'ckad-secret':
        print('found')
" 2>/dev/null)
    [ "$SVOL" = "found" ] \
        && check_pass "Pod 'secret-pod' volume sources from ckad-secret" \
        || check_fail "Pod 'secret-pod' volume should reference ckad-secret"

    # Live check: confirm files visible at /etc/secret-data
    if [ "$SEC_STATUS" = "Running" ]; then
        LS_RESULT=$(kubectl exec secret-pod -n default -- ls /etc/secret-data 2>/dev/null)
        if echo "$LS_RESULT" | grep -q "DB_USER"; then
            check_pass "Secret files visible at /etc/secret-data (DB_USER, DB_PASSWORD)"
        else
            check_fail "Files not visible at /etc/secret-data inside pod" \
                "ls output: '$LS_RESULT'"
        fi
    fi
else
    check_fail "Pod 'secret-pod' not found in default — run Part D first"
    check_fail "secret-pod running status cannot be checked"
    check_fail "secret-pod envFrom cannot be checked"
    check_fail "secret-pod volumeMount cannot be checked"
    check_fail "secret-pod volume cannot be checked"
fi

# ── Final summary ─────────────────────────────────────────────────────────────

verify_summary "15"
[ "$FAIL_COUNT" -eq 0 ]
