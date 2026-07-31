#!/bin/bash
# Verify Task 22: Job and CronJob
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
NS="task22"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 22: Job and CronJob ═════════════════════════${NC}"
use_context "$CTX"

# ── Namespace ─────────────────────────────────────────────────────────────────

if kubectl get namespace "$NS" &>/dev/null; then
    check_pass "Namespace '$NS' exists"
else
    check_fail "Namespace '$NS' not found — run: kubectl create namespace $NS"
fi

# ── Part A: Job ───────────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part A — Job:${NC}"
PART_A_FAIL_START=$FAIL_COUNT

if kubectl -n "$NS" get job task22-job &>/dev/null; then
    check_pass "Job 'task22-job' exists in namespace $NS"
    JOB_JSON=$(kubectl -n "$NS" get job task22-job -o json 2>/dev/null)

    # Check completions
    COMPLETIONS=$(echo "$JOB_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('completions',''))" 2>/dev/null)
    if [ "$COMPLETIONS" = "3" ]; then
        check_pass "Job spec.completions = 3"
    else
        check_fail "Job spec.completions should be 3, got '${COMPLETIONS:-not set}'"
    fi

    # Check parallelism
    PARALLELISM=$(echo "$JOB_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('parallelism',''))" 2>/dev/null)
    if [ "$PARALLELISM" = "2" ]; then
        check_pass "Job spec.parallelism = 2"
    else
        check_fail "Job spec.parallelism should be 2, got '${PARALLELISM:-not set}'"
    fi

    # Check image
    IMAGE=$(echo "$JOB_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin)
spec=d['spec']['template']['spec']
print(spec['containers'][0].get('image',''))" 2>/dev/null)
    if echo "$IMAGE" | grep -q "busybox"; then
        check_pass "Job uses busybox image: $IMAGE"
    else
        check_fail "Job image should be busybox:1.36, got '${IMAGE:-unknown}'"
    fi

    # Check successful completions
    SUCCEEDED=$(echo "$JOB_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('succeeded',0))" 2>/dev/null)
    if [ "${SUCCEEDED:-0}" -ge 3 ]; then
        check_pass "Job has ${SUCCEEDED} successful pod completions (all 3 complete)"
    elif [ "${SUCCEEDED:-0}" -ge 1 ]; then
        check_fail "Job has only ${SUCCEEDED}/3 completions — still running or failed"
        echo -e "     ${YELLOW}kubectl -n $NS get job task22-job  (watch COMPLETIONS column)${NC}"
    else
        check_fail "Job has 0 successful completions — may still be running or image pull failed"
        echo -e "     ${YELLOW}kubectl -n $NS describe job task22-job${NC}"
        echo -e "     ${YELLOW}kubectl -n $NS get pods --selector=job-name=task22-job${NC}"
    fi
else
    check_fail "Job 'task22-job' not found in namespace $NS"
    check_fail "Job spec.completions cannot be checked — job missing"
    check_fail "Job spec.parallelism cannot be checked — job missing"
    check_fail "Job image cannot be checked — job missing"
    check_fail "Job completions cannot be checked — job missing"
fi

PART_A_OK=0
[ "$FAIL_COUNT" -eq "$PART_A_FAIL_START" ] && PART_A_OK=1

# ── Part B: CronJob ───────────────────────────────────────────────────────────

echo -e "\n  ${BOLD}Part B — CronJob:${NC}"
PART_B_FAIL_START=$FAIL_COUNT

if kubectl -n "$NS" get cronjob task22-cronjob &>/dev/null; then
    check_pass "CronJob 'task22-cronjob' exists in namespace $NS"
    CJ_JSON=$(kubectl -n "$NS" get cronjob task22-cronjob -o json 2>/dev/null)

    # Check schedule
    SCHEDULE=$(echo "$CJ_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('schedule',''))" 2>/dev/null)
    if [ "$SCHEDULE" = "*/1 * * * *" ]; then
        check_pass "CronJob schedule = '*/1 * * * *' (every minute)"
    else
        check_fail "CronJob schedule should be '*/1 * * * *', got '${SCHEDULE:-not set}'"
    fi

    # Check image in jobTemplate
    CJ_IMAGE=$(echo "$CJ_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin)
spec=d['spec']['jobTemplate']['spec']['template']['spec']
print(spec['containers'][0].get('image',''))" 2>/dev/null)
    if echo "$CJ_IMAGE" | grep -q "busybox"; then
        check_pass "CronJob uses busybox image: $CJ_IMAGE"
    else
        check_fail "CronJob image should be busybox:1.36, got '${CJ_IMAGE:-unknown}'"
    fi

    # Check successfulJobsHistoryLimit
    HISTORY=$(echo "$CJ_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['spec'].get('successfulJobsHistoryLimit',''))" 2>/dev/null)
    if [ "$HISTORY" = "3" ]; then
        check_pass "CronJob successfulJobsHistoryLimit = 3"
    else
        check_fail "CronJob successfulJobsHistoryLimit should be 3, got '${HISTORY:-not set}'"
    fi
else
    check_fail "CronJob 'task22-cronjob' not found in namespace $NS"
    check_fail "CronJob schedule cannot be checked — cronjob missing"
    check_fail "CronJob image cannot be checked — cronjob missing"
    check_fail "CronJob successfulJobsHistoryLimit cannot be checked — cronjob missing"
fi

PART_B_OK=0
[ "$FAIL_COUNT" -eq "$PART_B_FAIL_START" ] && PART_B_OK=1

# ── Part checklist summary ─────────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}Checklist:${NC}"
if [ "$PART_A_OK" -eq 1 ]; then
    echo -e "  ${GREEN}✓${NC}  Part A — Job          complete"
else
    echo -e "  ${RED}✗${NC}  Part A — Job          incomplete"
fi
if [ "$PART_B_OK" -eq 1 ]; then
    echo -e "  ${GREEN}✓${NC}  Part B — CronJob      complete"
else
    echo -e "  ${RED}✗${NC}  Part B — CronJob      incomplete"
fi

# ── Final summary ──────────────────────────────────────────────────────────────

verify_summary "22"
[ "$FAIL_COUNT" -eq 0 ]
