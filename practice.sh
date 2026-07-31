#!/bin/bash
# CKA Simulator — Practice Mode (no timer, select individual tasks)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[ -z "${KUBECONFIG:-}" ] && export KUBECONFIG="$HOME/.kube/config-cka-simulator"

declare -a TASKS=(
    "01|4 |k8s  |RBAC — ClusterRole + RoleBinding"
    "02|8 |hk8s |NetworkPolicy — restrict ingress by namespace"
    "03|4 |k8s  |Logging Sidecar — add sidecar to existing pod"
    "04|8 |wk8s |Cluster Upgrade — control-plane via kubeadm"
    "05|5 |k8s  |etcd Backup and Restore"
    "06|4 |wk8s |PersistentVolume + PersistentVolumeClaim"
    "07|4 |k8s  |Pod Scheduling — nodeSelector"
    "08|6 |k8s  |Ingress — expose service via Ingress resource"
    "09|5 |k8s  |Deployment — Scale, Resources, Rollout & Rollback"
    "10|4 |wk8s |Node Drain and Uncordon"
    "11|8 |k8s  |Multi-container Pod with Init Container"
    "12|7 |bk8s |Troubleshoot — fix broken Deployment"
    "13|4 |k8s  |ResourceQuota"
    "14|4 |k8s  |ServiceAccount with ClusterRoleBinding"
    "15|6 |k8s  |ConfigMaps and Secrets (env vars + volume mount)"
    "16|6 |wk8s |StorageClass + PVC"
    "17|14|bk8s |Troubleshoot — broken worker node (NotReady)"
    "18|10|k8s  |Troubleshoot — Pod Not Running (10 failure causes)"
    "19|10|bk8s |Troubleshoot — Control Plane Components (4 causes)"
    "20|6 |k8s  |Troubleshoot — Service & DNS Debugging (5 causes)"
    "21|4 |k8s  |Taints and Tolerations"
    "22|4 |k8s  |Job and CronJob"
    "23|3 |k8s  |kubectl JSONPath and Custom Columns"
    "24|4 |k8s  |Helm Fundamentals"
    "25|4 |k8s  |Custom Resource Definitions (CRDs)"
    "26|3 |k8s  |DaemonSet"
    "27|6 |k8s  |Gateway API"
    "28|4 |k8s  |Horizontal Pod Autoscaler (HPA)"
)

show_menu() {
    print_header
    echo -e "  ${BOLD}PRACTICE MODE — Select a task to study${NC}"
    echo -e "  ${DIM}No timer. Practice at your own pace.${NC}"
    echo ""
    echo -e "  ${BOLD}  #   Wt   Context   Topic${NC}"
    echo -e "  ─────────────────────────────────────────────────────────────────"

    local i=1
    for t in "${TASKS[@]}"; do
        local num weight ctx title
        IFS='|' read -r num weight ctx title <<< "$t"
        printf "  %2d.  %s%%   %-6s    %s\n" "$i" "$weight" "$ctx" "$title"
        ((i++))
    done

    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "  ${CYAN}[1-28]${NC}    Open task question"
    echo -e "  ${CYAN}v <N>${NC}     Verify task N"
    echo -e "  ${CYAN}hint <N>${NC}  Show hint for task N"
    echo -e "  ${CYAN}r <N>${NC}     Reset/re-initialize scenario for task N"
    echo -e "  ${CYAN}ans <N>${NC}   Show reference answer for task N"
    echo -e "  ${CYAN}q${NC}         Quit"
    echo ""
}

open_task() {
    local idx=$1
    local t="${TASKS[$((idx-1))]}"
    local num ctx
    IFS='|' read -r num _ ctx _ <<< "$t"
    ctx=$(echo "$ctx" | tr -d ' ')
    local file="$SCRIPT_DIR/questions/task-${num}.md"
    local verify="$SCRIPT_DIR/verify/verify-task-${num}.sh"

    if [ ! -f "$file" ]; then
        echo "Task file not found: $file"
        read -rp "Press Enter to continue..."
        return
    fi

    clear
    awk '/^## Hint/{exit} {print}' "$file"
    echo ""
    echo -e "${CYAN}┌─ Interactive Shell ──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│  Type kubectl commands below to complete the task.              │${NC}"
    if [ "$num" = "17" ]; then
        echo -e "${CYAN}│  check  hint  answer  reset  cause <1-5>   task  back          │${NC}"
    elif [ "$num" = "18" ]; then
        echo -e "${CYAN}│  check  hint  answer  reset  cause <1-10>  task  back          │${NC}"
    elif [ "$num" = "19" ]; then
        echo -e "${CYAN}│  check  hint  answer  reset  cause <1-4>   task  back          │${NC}"
    elif [ "$num" = "20" ]; then
        echo -e "${CYAN}│  check  hint  answer  reset  cause <1-5>   task  back          │${NC}"
    else
        echo -e "${CYAN}│  check  hint  answer  reset  task  back                        │${NC}"
    fi
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    if ! start_cluster "$ctx"; then
        read -rp "Press Enter to return to menu..."
        return
    fi

    local TMP
    TMP=$(mktemp -d)

    # Write rcfile for the interactive subshell
    cat > "$TMP/rcfile.sh" << RCEOF
[ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null
[ -d "\$HOME/.local/bin" ] && export PATH="\$HOME/.local/bin:\$PATH"
export KUBECONFIG="\${KUBECONFIG:-$HOME/.kube/config-cka-simulator}"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

check() {
    echo ""
    if [ -f "$verify" ]; then
        bash "$verify"
    else
        echo "No verify script found for task $num."
    fi
    echo ""
}

hint() {
    echo ""
    grep -A 60 "^## Hint" "$file" | grep -B 60 "^## Answer" | head -60
    echo ""
}

answer() {
    echo ""
    grep -A 100 "^## Answer" "$file" | head -80
    echo ""
}

task() {
    clear
    awk '/^## Hint/{exit} {print}' "$file"
    echo ""
}

reset() {
    echo ""
    echo -e "\033[1;33m  Resetting Task $num to its original state...\033[0m"
    bash "$SCRIPT_DIR/scenarios/reset.sh" "$num"
}

back() { exit 0; }

PS1="\[\033[1;33m\][task-$num]\[\033[0m\] \$ "
RCEOF

    # Append cause() helper for task 17 — lets user set up any of the 5 failure causes
    if [ "$num" = "17" ]; then
        cat >> "$TMP/rcfile.sh" << CAUSEEOF

cause() {
    local n="\$1"
    if [ -z "\$n" ]; then
        echo ""
        echo -e "  \${BOLD}Task 17 — Choose a root cause to practice:\${NC}"
        echo -e "  \${CYAN}cause 1\${NC}  kubelet service stopped       \${YELLOW}(Most common, ~90% of exams)\${NC}"
        echo -e "  \${CYAN}cause 2\${NC}  containerd runtime stopped"
        echo -e "  \${CYAN}cause 3\${NC}  kubelet config file error"
        echo -e "  \${CYAN}cause 4\${NC}  Certificate expired           \${YELLOW}(real x509 expiry error)\${NC}"
        echo -e "  \${CYAN}cause 5\${NC}  Disk full                     \${YELLOW}(creates 2 GB fill file)\${NC}"
        echo ""
        return
    fi
    bash "$SCRIPT_DIR/scenarios/setup-task-17-cause.sh" "\$n"
}
CAUSEEOF
    fi

    # Append cause() helper for task 18 — lets user set up any of the 10 pod failure causes
    if [ "$num" = "18" ]; then
        cat >> "$TMP/rcfile.sh" << CAUSEEOF

cause() {
    local n="\$1"
    if [ -z "\$n" ]; then
        echo ""
        echo -e "  \${BOLD}Task 18 — Choose a root cause to practice:\${NC}"
        echo -e "  \${CYAN}cause 1\${NC}   Pod Pending — insufficient CPU/memory"
        echo -e "  \${CYAN}cause 2\${NC}   ImagePullBackOff — wrong image name (typo)"
        echo -e "  \${CYAN}cause 3\${NC}   CrashLoopBackOff — container exits with code 1"
        echo -e "  \${CYAN}cause 4\${NC}   FailedMount — ConfigMap volume not found"
        echo -e "  \${CYAN}cause 5\${NC}   CreateContainerConfigError — ConfigMap missing (envFrom)"
        echo -e "  \${CYAN}cause 6\${NC}   CreateContainerConfigError — Secret missing (envFrom)"
        echo -e "  \${CYAN}cause 7\${NC}   PVC Pending — invalid StorageClass"
        echo -e "  \${CYAN}cause 8\${NC}   Readiness probe failing — wrong port"
        echo -e "  \${CYAN}cause 9\${NC}   Liveness probe failing — always-fail command"
        echo -e "  \${CYAN}cause 10\${NC}  ErrImagePull — wrong image tag"
        echo ""
        return
    fi
    bash "$SCRIPT_DIR/scenarios/setup-task-18-cause.sh" "\$n"
}
CAUSEEOF
    fi

    # Append cause() helper for task 19 — control plane failure causes
    if [ "$num" = "19" ]; then
        cat >> "$TMP/rcfile.sh" << CAUSEEOF

cause() {
    local n="\$1"
    if [ -z "\$n" ]; then
        echo ""
        echo -e "  \${BOLD}Task 19 — Choose a root cause to practice:\${NC}"
        echo -e "  \${CYAN}cause 1\${NC}  kube-apiserver CrashLoopBackOff  \${YELLOW}(bad flag — kubectl stops working)\${NC}"
        echo -e "  \${CYAN}cause 2\${NC}  kube-scheduler cannot start      \${YELLOW}(bad kubeconfig path)\${NC}"
        echo -e "  \${CYAN}cause 3\${NC}  kube-controller-manager failed   \${YELLOW}(bad kubeconfig path)\${NC}"
        echo -e "  \${CYAN}cause 4\${NC}  static pod manifest YAML error   \${YELLOW}(scheduler pod disappears)\${NC}"
        echo ""
        return
    fi
    bash "$SCRIPT_DIR/scenarios/setup-task-19-cause.sh" "\$n"
}
CAUSEEOF
    fi

    # Append cause() helper for task 20 — service & DNS failure causes
    if [ "$num" = "20" ]; then
        cat >> "$TMP/rcfile.sh" << CAUSEEOF

cause() {
    local n="\$1"
    if [ -z "\$n" ]; then
        echo ""
        echo -e "  \${BOLD}Task 20 — Choose a root cause to practice:\${NC}"
        echo -e "  \${CYAN}cause 1\${NC}  Selector mismatch — no endpoints"
        echo -e "  \${CYAN}cause 2\${NC}  Wrong targetPort — connection refused despite endpoints"
        echo -e "  \${CYAN}cause 3\${NC}  CoreDNS scaled to 0 — all DNS fails   \${YELLOW}(cluster-wide impact)\${NC}"
        echo -e "  \${CYAN}cause 4\${NC}  Wrong service port — client reaches wrong port"
        echo -e "  \${CYAN}cause 5\${NC}  Service in wrong namespace — short DNS name fails"
        echo ""
        return
    fi
    bash "$SCRIPT_DIR/scenarios/setup-task-20-cause.sh" "\$n"
}
CAUSEEOF
    fi

    bash --rcfile "$TMP/rcfile.sh" -i
    rm -rf "$TMP"

    stop_cluster "$ctx"
}

verify_task() {
    local idx=$1
    local t="${TASKS[$((idx-1))]}"
    local num ctx
    IFS='|' read -r num _ ctx _ <<< "$t"
    ctx=$(echo "$ctx" | tr -d ' ')
    local script="$SCRIPT_DIR/verify/verify-task-${num}.sh"
    if [ -f "$script" ]; then
        if start_cluster "$ctx"; then
            bash "$script"
        fi
    else
        echo -e "${YELLOW}No verify script for task $num yet.${NC}"
    fi
    echo ""
    read -rp "Press Enter to continue..."
}

show_hint() {
    local idx=$1
    local t="${TASKS[$((idx-1))]}"
    local num
    IFS='|' read -r num _ _ _ <<< "$t"
    local file="$SCRIPT_DIR/questions/task-${num}.md"
    if [ -f "$file" ]; then
        echo -e "\n${YELLOW}${BOLD}═══ HINT for Task ${num} ════════════════════════════${NC}"
        grep -A 20 "^## Hint" "$file" 2>/dev/null || echo "No hint section in task file."
        echo ""
        read -rp "Press Enter to continue..."
    fi
}

show_answer() {
    local idx=$1
    local t="${TASKS[$((idx-1))]}"
    local num
    IFS='|' read -r num _ _ _ <<< "$t"
    local file="$SCRIPT_DIR/questions/task-${num}.md"
    if [ -f "$file" ]; then
        echo -e "\n${CYAN}${BOLD}═══ REFERENCE ANSWER for Task ${num} ═══════════════${NC}"
        grep -A 100 "^## Answer" "$file" 2>/dev/null || echo "No answer section in task file."
        echo ""
        read -rp "Press Enter to continue..."
    fi
}

reset_scenario() {
    local idx=$1
    local t="${TASKS[$((idx-1))]}"
    local num
    IFS='|' read -r num _ _ _ <<< "$t"
    local setup="$SCRIPT_DIR/scenarios/setup-task-${num}.sh"
    if [ -f "$setup" ]; then
        echo -e "${YELLOW}Re-initializing scenario for task ${num}...${NC}"
        bash "$setup"
        echo -e "${GREEN}Done.${NC}"
    else
        echo "No setup script for task $num."
    fi
    read -rp "Press Enter to continue..."
}

main() {
    while true; do
        show_menu
        read -rp "  → " input

        case "$input" in
            [1-9]|1[0-9]|2[0-9])
                open_task "$input"
                ;;
            v\ [1-9]|"v 1"[0-9]|"v 2"[0-9])
                verify_task "${input#v }"
                ;;
            hint\ [1-9]|"hint 1"[0-9]|"hint 2"[0-9])
                show_hint "${input#hint }"
                ;;
            ans\ [1-9]|"ans 1"[0-9]|"ans 2"[0-9])
                show_answer "${input#ans }"
                ;;
            r\ [1-9]|"r 1"[0-9]|"r 2"[0-9])
                reset_scenario "${input#r }"
                ;;
            q|quit|exit)
                echo "Goodbye! Keep practicing."
                exit 0
                ;;
            *)
                echo -e "${YELLOW}Unknown command.${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
