#!/bin/bash
# Verify Task 25: Custom Resource Definitions (CRDs)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task25"
CRD_NAME="backups.storage.example.com"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 25: Custom Resource Definitions ══════════════${NC}"
use_context "$CTX"

# ── CRD is registered ─────────────────────────────────────────────────────────

CRD_JSON=$(kubectl get crd "$CRD_NAME" -o json 2>/dev/null)
if [ -n "$CRD_JSON" ]; then
    check_pass "CRD '$CRD_NAME' is registered in the cluster"
else
    check_fail "CRD '$CRD_NAME' not found — apply the CRD YAML first"
    verify_summary "25"; exit 1
fi

# ── CRD group ─────────────────────────────────────────────────────────────────

CRD_GROUP=$(echo "$CRD_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('group',''))" 2>/dev/null)
[ "$CRD_GROUP" = "storage.example.com" ] \
    && check_pass "CRD group = storage.example.com" \
    || check_fail "CRD group should be 'storage.example.com', got '$CRD_GROUP'"

# ── CRD kind ──────────────────────────────────────────────────────────────────

CRD_KIND=$(echo "$CRD_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['spec']['names'].get('kind',''))" 2>/dev/null)
[ "$CRD_KIND" = "Backup" ] \
    && check_pass "CRD kind = Backup" \
    || check_fail "CRD kind should be 'Backup', got '$CRD_KIND'"

# ── CRD scope ─────────────────────────────────────────────────────────────────

CRD_SCOPE=$(echo "$CRD_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('scope',''))" 2>/dev/null)
[ "$CRD_SCOPE" = "Namespaced" ] \
    && check_pass "CRD scope = Namespaced" \
    || check_fail "CRD scope should be 'Namespaced', got '$CRD_SCOPE'"

# ── CRD is Established ────────────────────────────────────────────────────────

CRD_ESTABLISHED=$(echo "$CRD_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for cond in d.get('status',{}).get('conditions',[]):
    if cond.get('type') == 'Established' and cond.get('status') == 'True':
        print('yes')
" 2>/dev/null)
[ "$CRD_ESTABLISHED" = "yes" ] \
    && check_pass "CRD condition Established=True (API is ready)" \
    || check_fail "CRD is not yet Established — wait a moment and re-check"

# ── Namespace exists ──────────────────────────────────────────────────────────

if kubectl get namespace "$NS" &>/dev/null; then
    check_pass "Namespace '$NS' exists"
else
    check_fail "Namespace '$NS' not found — run: kubectl create namespace $NS"
fi

# ── Custom resource 'daily-backup' exists ─────────────────────────────────────

CR_JSON=$(kubectl get backup daily-backup -n "$NS" -o json 2>/dev/null)
if [ -n "$CR_JSON" ]; then
    check_pass "Custom resource 'daily-backup' exists in namespace $NS"
else
    check_fail "Custom resource 'daily-backup' not found in namespace $NS" \
        "Apply the Backup YAML after the CRD is Established"
    verify_summary "25"; exit 1
fi

# ── Custom resource spec.source ───────────────────────────────────────────────

CR_SOURCE=$(echo "$CR_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('spec',{}).get('source',''))" 2>/dev/null)
[ "$CR_SOURCE" = "/data/postgres" ] \
    && check_pass "Backup spec.source = /data/postgres" \
    || check_fail "Backup spec.source should be '/data/postgres', got '$CR_SOURCE'"

# ── Custom resource spec.retention ───────────────────────────────────────────

CR_RETENTION=$(echo "$CR_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('spec',{}).get('retention',''))" 2>/dev/null)
[ "$CR_RETENTION" = "7" ] \
    && check_pass "Backup spec.retention = 7" \
    || check_fail "Backup spec.retention should be 7, got '$CR_RETENTION'"

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "25"
[ "$FAIL_COUNT" -eq 0 ]
