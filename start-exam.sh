#!/bin/bash
# CKA Simulator — Timed Exam Mode
# Simulates the 2-hour Linux Foundation CKA performance-based exam

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

EXAM_DURATION=$((2 * 60 * 60))   # 2 hours in seconds
EXAM_START=0
EXAM_PID=0
TIMER_PID=0

# Task list: (number weight context short-title)
declare -a TASKS=(
    "01 4  k8s   RBAC — ClusterRole + RoleBinding"
    "02 8  hk8s  NetworkPolicy — restrict ingress by namespace"
    "03 4  k8s   Logging Sidecar — add sidecar to existing pod"
    "04 8  wk8s  Cluster Upgrade — control-plane node via kubeadm"
    "05 5  k8s   etcd Backup and Restore"
    "06 4  wk8s  PersistentVolume + PersistentVolumeClaim"
    "07 4  k8s   Pod Scheduling — nodeSelector"
    "08 6  k8s   Ingress — expose service via Ingress resource"
    "09 5  k8s   Deployment — Scale, Resources, Rollout & Rollback"
    "10 4  wk8s  Node Drain and Uncordon"
    "11 8  k8s   Multi-container Pod with Init Container"
    "12 7  bk8s  Troubleshoot — fix broken Deployment"
    "13 4  k8s   ResourceQuota"
    "14 4  k8s   ServiceAccount with ClusterRoleBinding"
    "15 6  k8s   ConfigMaps and Secrets (env vars + volume mount)"
    "16 6  wk8s  StorageClass + PVC"
    "17 14 bk8s  Troubleshoot — broken worker node (NotReady)"
    "18 10 k8s   Troubleshoot — Pod Not Running (10 failure causes)"
    "19 10 bk8s  Troubleshoot — Control Plane Components (4 causes)"
    "20 6  k8s   Troubleshoot — Service & DNS Debugging (5 causes)"
    "21 4  k8s   Taints and Tolerations"
    "22 4  k8s   Job and CronJob"
    "23 3  k8s   kubectl JSONPath and Custom Columns"
    "24 4  k8s   Helm Fundamentals"
    "25 4  k8s   Custom Resource Definitions (CRDs)"
    "26 3  k8s   DaemonSet"
    "27 6  k8s   Gateway API"
    "28 4  k8s   Horizontal Pod Autoscaler (HPA)"
)

TOTAL_WEIGHT=0
for t in "${TASKS[@]}"; do
    w=$(echo "$t" | awk '{print $2}')
    TOTAL_WEIGHT=$((TOTAL_WEIGHT + w))
done

start_timer() {
    EXAM_START=$(date +%s)
    (
        while true; do
            local now elapsed remaining
            now=$(date +%s)
            elapsed=$((now - EXAM_START))
            remaining=$((EXAM_DURATION - elapsed))

            if [ "$remaining" -le 0 ]; then
                echo ""
                echo -e "\n${RED}${BOLD}════════════════════════════════════════${NC}"
                echo -e "${RED}${BOLD}  TIME'S UP! Exam session has ended.    ${NC}"
                echo -e "${RED}${BOLD}════════════════════════════════════════${NC}"
                kill -USR1 $$ 2>/dev/null
                exit 0
            fi

            # Print timer bar to status line (non-intrusive)
            local pct=$(( (elapsed * 100) / EXAM_DURATION ))
            local t_display
            t_display=$(printf '%02d:%02d:%02d' $((remaining/3600)) $(( (remaining%3600)/60 )) $((remaining%60)) )

            # Write to terminal title bar
            printf "\033]0;CKA Exam │ Time Left: %s │ %d%% elapsed\007" "$t_display" "$pct"

            sleep 30
        done
    ) &
    TIMER_PID=$!
}

stop_timer() {
    [ "$TIMER_PID" -ne 0 ] && kill "$TIMER_PID" 2>/dev/null || true
    printf "\033]0;\007"  # Reset title bar
}

show_time_remaining() {
    local now elapsed remaining
    now=$(date +%s)
    elapsed=$((now - EXAM_START))
    remaining=$((EXAM_DURATION - elapsed))
    local t_display
    t_display=$(printf '%02d:%02d:%02d' $((remaining/3600)) $(( (remaining%3600)/60 )) $((remaining%60)))
    echo -e "  ${CYAN}Time remaining: ${BOLD}${t_display}${NC}"
}

show_task_list() {
    print_header
    echo -e "  ${BOLD}CERTIFIED KUBERNETES ADMINISTRATOR (CKA) — Simulator Exam${NC}"
    echo -e "  ${DIM}Duration: 2 hours  |  Passing score: 66%  |  Tasks: 28${NC}"
    echo ""
    echo -e "  ${BOLD}Task #  Weight  Context  Description${NC}"
    echo -e "  ──────  ──────  ───────  ──────────────────────────────────────────"

    for t in "${TASKS[@]}"; do
        local num weight ctx title
        num=$(echo "$t" | awk '{print $1}')
        weight=$(echo "$t" | awk '{print $2}')
        ctx=$(echo "$t" | awk '{print $3}')
        title=$(echo "$t" | cut -d' ' -f4-)
        printf "  Task %s  %3d%%    %-5s   %s\n" "$num" "$weight" "$ctx" "$title"
    done

    echo ""
    show_time_remaining
    echo ""
}

task_context() {
    local task_num=$1
    printf '%s\n' "${TASKS[@]}" | awk -v n="$task_num" '$1==n{print $3; exit}'
}

open_task() {
    local task_num=$1
    local task_file="$SCRIPT_DIR/questions/task-${task_num}.md"
    local verify_script="$SCRIPT_DIR/verify/verify-task-${task_num}.sh"
    local ctx
    ctx=$(task_context "$task_num")

    if [ ! -f "$task_file" ]; then
        echo -e "${RED}Task file not found: $task_file${NC}"
        return
    fi

    clear
    show_time_remaining
    echo ""
    awk '/^## Hint/{exit} {print}' "$task_file"
    echo ""
    echo -e "${CYAN}┌─ Interactive Shell ──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│  Type kubectl commands below to complete the task.              │${NC}"
    echo -e "${CYAN}│  check  hint  answer  reset  task  back                        │${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    if ! start_cluster "$ctx"; then
        read -rp "Press Enter to return to menu..."
        return
    fi

    local TMP
    TMP=$(mktemp -d)

    cat > "$TMP/rcfile.sh" << RCEOF
[ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null
[ -d "\$HOME/.local/bin" ] && export PATH="\$HOME/.local/bin:\$PATH"
export KUBECONFIG="\${KUBECONFIG:-$HOME/.kube/config-cka-simulator}"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

check() {
    echo ""
    if [ -f "$verify_script" ]; then
        bash "$verify_script"
    else
        echo "No verify script found for task $task_num."
    fi
    echo ""
}

hint() {
    echo ""
    grep -A 60 "^## Hint" "$task_file" | grep -B 60 "^## Answer" | head -60
    echo ""
}

answer() {
    echo ""
    grep -A 100 "^## Answer" "$task_file" | head -80
    echo ""
}

task() {
    clear
    awk '/^## Hint/{exit} {print}' "$task_file"
    echo ""
}

reset() {
    echo ""
    echo -e "\033[1;33m  Resetting Task $task_num to its original state...\033[0m"
    bash "$SCRIPT_DIR/scenarios/reset.sh" "$task_num"
}

back() { exit 0; }

PS1="\[\033[1;33m\][task-$task_num]\[\033[0m\] \$ "
RCEOF

    bash --rcfile "$TMP/rcfile.sh" -i
    rm -rf "$TMP"

    stop_cluster "$ctx"
}

verify_task() {
    local task_num=$1
    local verify_script="$SCRIPT_DIR/verify/verify-task-${task_num}.sh"
    local ctx
    ctx=$(task_context "$task_num")

    if [ ! -f "$verify_script" ]; then
        echo -e "${YELLOW}No verify script for task $task_num yet.${NC}"
        return
    fi

    if ! start_cluster "$ctx"; then
        read -rp "Press Enter to continue..."
        return
    fi

    bash "$verify_script"
    echo ""
    read -rp "Press Enter to continue..."
}

exam_menu() {
    while true; do
        show_task_list
        echo -e "  ${BOLD}Commands:${NC}"
        echo -e "  ${CYAN}[1-28]${NC}  Open task"
        echo -e "  ${CYAN}v <N>${NC}   Verify task (e.g. v 3)"
        echo -e "  ${CYAN}va${NC}      Verify all tasks (score estimate)"
        echo -e "  ${CYAN}t${NC}       Show time remaining"
        echo -e "  ${CYAN}q${NC}       End exam (submit)"
        echo ""

        read -rp "  → " input

        case "$input" in
            [0-9]|[0-9][0-9])
                local n
                n=$(printf '%02d' "$input")
                open_task "$n"
                ;;
            v\ *)
                local n
                n=$(printf '%02d' "${input#v }")
                verify_task "$n"
                ;;
            va)
                verify_all
                ;;
            t)
                show_time_remaining
                read -rp "Press Enter..."
                ;;
            q|quit|exit)
                end_exam
                return
                ;;
            *)
                echo -e "${YELLOW}Unknown command: $input${NC}"
                sleep 1
                ;;
        esac
    done
}

verify_all() {
    clear
    echo -e "${BOLD}${BLUE}═══ EXAM SCORE ESTIMATE ════════════════════════════════════════${NC}"
    echo ""

    local total_earned=0
    local total_possible=0

    for t in "${TASKS[@]}"; do
        local num weight ctx title
        num=$(echo "$t" | awk '{print $1}')
        weight=$(echo "$t" | awk '{print $2}')
        title=$(echo "$t" | cut -d' ' -f4-)
        total_possible=$((total_possible + weight))

        local verify_script="$SCRIPT_DIR/verify/verify-task-${num}.sh"
        if [ -f "$verify_script" ]; then
            # Run verify silently, capture exit code
            if bash "$verify_script" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Task ${num} (${weight}%)  ${title}"
                total_earned=$((total_earned + weight))
            else
                echo -e "  ${RED}✗${NC} Task ${num} (${weight}%)  ${title}"
            fi
        else
            echo -e "  ${YELLOW}?${NC} Task ${num} (${weight}%)  ${title} — no verifier"
        fi
    done

    echo ""
    echo -e "${BOLD}──────────────────────────────────────────────────────────────────${NC}"
    local pct=$((total_earned * 100 / total_possible))
    if [ "$pct" -ge 66 ]; then
        echo -e "  ${BOLD}${GREEN}Score: ${total_earned}% / ${total_possible}% — PASS (≥66%)${NC}"
    else
        echo -e "  ${BOLD}${RED}Score: ${total_earned}% / ${total_possible}% — FAIL (<66%)${NC}"
    fi
    echo ""
    read -rp "Press Enter to continue..."
}

end_exam() {
    stop_timer
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - EXAM_START))

    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                    EXAM SESSION ENDED                       ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    printf "  Time used: %02d:%02d:%02d\n" $((elapsed/3600)) $(( (elapsed%3600)/60 )) $((elapsed%60))
    echo ""
    echo -e "  Run ${CYAN}bash $SCRIPT_DIR/verify/verify-task-XX.sh${NC} to check individual tasks."
    echo ""
}

pre_exam_briefing() {
    print_header
    echo -e "  ${BOLD}PRE-EXAM BRIEFING${NC}"
    echo ""
    echo -e "  ${BOLD}Duration:${NC}       2 hours (120 minutes)"
    echo -e "  ${BOLD}Tasks:${NC}          28 performance-based tasks"
    echo -e "  ${BOLD}Passing score:${NC}  66%"
    echo -e "  ${BOLD}Kubernetes:${NC}     v1.35"
    echo ""
    echo -e "  ${BOLD}Available Clusters:${NC}"
    echo -e "    ${GREEN}k8s${NC}   — Main cluster"
    echo -e "    ${GREEN}hk8s${NC}  — High-availability cluster"
    echo -e "    ${GREEN}bk8s${NC}  — Cluster with issues (troubleshooting tasks)"
    echo -e "    ${GREEN}wk8s${NC}  — Worker/networking cluster"
    echo ""
    echo -e "  ${BOLD}Rules (same as real exam):${NC}"
    echo -e "  • You may use: https://kubernetes.io/docs (and sub-pages)"
    echo -e "  • Each task specifies which cluster to use — set context first!"
    echo -e "  • kubectl autocomplete is available (tab completion)"
    echo -e "  • Use: kubectl config use-context <name> before each task"
    echo ""
    echo -e "  ${BOLD}Tip:${NC} Use ${CYAN}kubectl run pod1 --image=nginx \$do${NC} to generate YAML quickly."
    echo ""
    echo -e "  ${YELLOW}Ensure KUBECONFIG is set:${NC}"
    echo -e "    export KUBECONFIG=~/.kube/config-cka-simulator"
    echo ""

    read -rp "  Press Enter to start the 2-hour timer..." _
}

# Handle time's up signal
trap 'end_exam; exit 0' USR1

main() {
    if [ -z "${KUBECONFIG:-}" ] && [ ! -f "$HOME/.kube/config-cka-simulator" ]; then
        echo -e "${YELLOW}Warning: KUBECONFIG not set. Run setup.sh first.${NC}"
        echo -e "Then: export KUBECONFIG=~/.kube/config-cka-simulator"
        exit 1
    fi

    [ -z "${KUBECONFIG:-}" ] && export KUBECONFIG="$HOME/.kube/config-cka-simulator"

    pre_exam_briefing
    start_timer
    exam_menu
}

main "$@"
