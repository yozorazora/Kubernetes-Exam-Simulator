#!/bin/bash
# lib/common.sh - Shared functions for CKA Simulator

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

print_header() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║          CKA EXAM SIMULATOR  —  Kubernetes v1.32            ║"
    echo "  ║        Mimics Linux Foundation CKA Exam Environment         ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────${NC}"
}

print_step()    { echo -e "${CYAN}[STEP]${NC}  $1"; }
print_success() { echo -e "${GREEN}[  ✓  ]${NC} $1"; }
print_fail()    { echo -e "${RED}[  ✗  ]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[ WARN ]${NC} $1"; }
print_info()    { echo -e "${BLUE}[ INFO ]${NC} $1"; }
print_note()    { echo -e "${DIM}         $1${NC}"; }

check_pass() {
    local desc=$1
    echo -e "  ${GREEN}✓${NC} $desc"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_fail() {
    local desc=$1
    local detail="${2:-}"
    echo -e "  ${RED}✗${NC} $desc"
    [ -n "$detail" ] && echo -e "    ${DIM}→ $detail${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

verify_summary() {
    local task=$1
    echo ""
    echo -e "${BOLD}━━━ Verification Result: Task ${task} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"
    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo -e "\n  ${BOLD}${GREEN}✓  TASK ${task} — COMPLETE${NC}"
    else
        echo -e "\n  ${BOLD}${RED}✗  TASK ${task} — INCOMPLETE (fix the items above)${NC}"
    fi
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

use_context() {
    local ctx=$1
    if ! kubectl config use-context "$ctx" &>/dev/null; then
        print_fail "Cannot switch to context '$ctx'. Is the cluster running?"
        exit 1
    fi
}

check_command() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        print_fail "Required command not found: $cmd"
        return 1
    fi
    return 0
}

require_context() {
    local ctx=$1
    if ! kubectl config get-contexts "$ctx" &>/dev/null; then
        print_fail "Context '$ctx' not found. Run setup.sh first."
        exit 1
    fi
}

timer_display() {
    local seconds=$1
    printf '%02d:%02d:%02d' $((seconds/3600)) $(( (seconds%3600)/60 )) $((seconds%60))
}

# Starts the kind containers for a cluster context (if not already running)
# and waits until the API server actually responds. Running multiple kind
# clusters at once has been observed to starve etcd's disk I/O and cause
# scheduler/controller-manager leader-election flapping, so tasks should
# only bring up the one cluster they need.
start_cluster() {
    local ctx=$1
    local cp="${ctx}-control-plane"
    local wk="${ctx}-worker"

    local cp_state wk_state
    cp_state=$(docker inspect -f '{{.State.Running}}' "$cp" 2>/dev/null)
    wk_state=$(docker inspect -f '{{.State.Running}}' "$wk" 2>/dev/null)

    if [ "$cp_state" = "true" ] && [ "$wk_state" = "true" ]; then
        return 0
    fi

    echo -e "${CYAN}  Starting cluster '$ctx'...${NC}"
    if ! docker start "$cp" "$wk" &>/dev/null; then
        echo -e "${RED}  Failed to start containers for cluster '$ctx'. Is Docker running?${NC}"
        return 1
    fi

    echo -ne "${CYAN}  Waiting for cluster '$ctx' to be ready${NC}"
    local i=0
    until kubectl --context "$ctx" get nodes &>/dev/null; do
        echo -n "."
        sleep 2
        i=$((i+1))
        if [ "$i" -gt 45 ]; then
            echo -e "\n${RED}  Cluster '$ctx' did not become ready in time.${NC}"
            return 1
        fi
    done
    echo -e " ${GREEN}ready${NC}"
    sleep 1
    return 0
}

# Stops a cluster's containers to free resources for whichever cluster is
# used next. Safe to call even if the cluster is already stopped.
stop_cluster() {
    local ctx=$1
    local cp="${ctx}-control-plane"
    local wk="${ctx}-worker"
    echo -e "${DIM}  Stopping cluster '$ctx' to free resources...${NC}"
    docker stop "$cp" "$wk" &>/dev/null
}
