#!/bin/bash
# CKA Simulator - Setup Script
# Run this in WSL2 (Ubuntu 22.04 recommended)
# Sets up 4 Kubernetes clusters matching real CKA exam contexts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║          CKA EXAM SIMULATOR  —  Setup                       ║"
    echo "  ║        Kubernetes v1.35  |  4 Clusters  |  28 Tasks         ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step()    { echo -e "${CYAN}[SETUP]${NC} $1"; }
ok()      { echo -e "${GREEN}[  ✓  ]${NC} $1"; }
fail()    { echo -e "${RED}[  ✗  ]${NC} $1"; }
warn()    { echo -e "${YELLOW}[ WARN ]${NC} $1"; }

check_os() {
    step "Checking operating system..."

    local kernel
    kernel="$(uname -s)"

    case "$kernel" in
        Darwin)
            ok "Running on macOS"
            ;;
        Linux)
            if [ -r /etc/os-release ] && grep -qi '^ID=ubuntu' /etc/os-release; then
                if grep -qi microsoft /proc/version 2>/dev/null; then
                    ok "Running on Ubuntu (WSL2)"
                else
                    ok "Running on Ubuntu"
                fi
            else
                fail "This script expects Ubuntu (via WSL2) on Windows, or macOS."
                echo ""
                echo "  Detected a non-Ubuntu Linux distro. This simulator is only"
                echo "  tested against Ubuntu 22.04+ inside WSL2 (Windows) or macOS."
                echo "  See INSTALL.md for supported setup instructions."
                exit 1
            fi
            ;;
        *)
            fail "Unsupported environment: $kernel"
            echo ""
            echo "  Windows users: this script must run inside a WSL2 Ubuntu terminal"
            echo "  (not Git Bash, Cygwin, PowerShell, or cmd.exe)."
            echo "  See INSTALL.md → 'Windows setup (via WSL2)' to install WSL2 + Ubuntu first."
            exit 1
            ;;
    esac
}

check_prerequisites() {
    step "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        fail "Docker not found."
        echo ""
        echo "  Install Docker Desktop for Windows, then enable WSL2 integration."
        echo "  Guide: https://docs.docker.com/desktop/wsl/"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        fail "Docker daemon is not running. Start Docker Desktop first."
        exit 1
    fi

    ok "Docker is running ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'version unknown'))"
}

install_kind() {
    if command -v kind &>/dev/null; then
        ok "kind already installed: $(kind version 2>/dev/null | head -1)"
        return
    fi

    step "Installing kind v0.25.0..."
    local ARCH
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && ARCH="amd64"
    [ "$ARCH" = "aarch64" ] && ARCH="arm64"

    curl -sSLo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-${ARCH}"
    chmod +x /tmp/kind
    sudo mv /tmp/kind /usr/local/bin/kind
    ok "kind installed: $(kind version | head -1)"
}

install_kubectl() {
    if command -v kubectl &>/dev/null; then
        ok "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
        return
    fi

    step "Installing kubectl v1.32.0..."
    local ARCH
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && ARCH="amd64"
    [ "$ARCH" = "aarch64" ] && ARCH="arm64"

    curl -sSLo /tmp/kubectl "https://dl.k8s.io/release/v1.32.0/bin/linux/${ARCH}/kubectl"
    chmod +x /tmp/kubectl
    sudo mv /tmp/kubectl /usr/local/bin/kubectl
    ok "kubectl installed"
}

install_extras() {
    # Install etcdctl (needed for etcd backup task)
    if ! command -v etcdctl &>/dev/null; then
        step "Installing etcdctl v3.5.17..."
        local ARCH
        ARCH=$(uname -m)
        [ "$ARCH" = "x86_64" ] && ARCH="amd64"
        [ "$ARCH" = "aarch64" ] && ARCH="arm64"

        curl -sSL "https://github.com/etcd-io/etcd/releases/download/v3.5.17/etcd-v3.5.17-linux-${ARCH}.tar.gz" \
            | tar xz -C /tmp
        sudo mv "/tmp/etcd-v3.5.17-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
        ok "etcdctl installed"
    else
        ok "etcdctl already installed"
    fi

    # Install jq (needed for verify scripts)
    if ! command -v jq &>/dev/null; then
        step "Installing jq..."
        sudo apt-get install -y jq &>/dev/null || sudo yum install -y jq &>/dev/null || true
        command -v jq &>/dev/null && ok "jq installed" || warn "jq install failed — some verify scripts may not work"
    else
        ok "jq already installed"
    fi
}

create_cluster() {
    local name=$1
    local config="$SCRIPT_DIR/clusters/${name}.yaml"

    if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
        ok "Cluster '${name}' already exists — skipping"
        return
    fi

    step "Creating cluster '${name}' (may take 2-5 min)..."
    kind create cluster --config "$config" --wait 180s 2>&1 | tail -5
    ok "Cluster '${name}' ready"
}

merge_kubeconfigs() {
    step "Merging kubeconfigs..."
    local KUBE_DIR="$HOME/.kube"
    mkdir -p "$KUBE_DIR"

    local configs=()
    for name in k8s hk8s bk8s wk8s; do
        if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
            local cfg="$KUBE_DIR/cka-${name}.yaml"
            kind get kubeconfig --name "${name}" > "$cfg"
            # Rename context from kind-<name> to <name> to match real exam
            sed -i "s/kind-${name}/${name}/g" "$cfg"
            configs+=("$cfg")
        fi
    done

    if [ ${#configs[@]} -gt 0 ]; then
        local merged="$KUBE_DIR/config-cka-simulator"
        KUBECONFIG=$(IFS=:; echo "${configs[*]}") kubectl config view --flatten > "$merged"
        ok "Merged kubeconfig: $merged"
        echo ""
        echo -e "  ${YELLOW}Add to your ~/.bashrc:${NC}"
        echo -e "  ${BOLD}export KUBECONFIG=~/.kube/config-cka-simulator${NC}"
    fi
}

write_aliases() {
    cat > "$SCRIPT_DIR/.exam-env" << 'ALIASES'
# CKA Simulator — Exam Environment
# Source this file: source ./cka-simulator/.exam-env

# Core aliases matching what's available in the real CKA exam
alias k='kubectl'
complete -o default -F __start_kubectl k 2>/dev/null || true

# Dry-run shortcut  (use: kubectl run pod1 --image=nginx $do)
export do='--dry-run=client -o yaml'

# Force delete      (use: kubectl delete pod mypod $now)
export now='--force --grace-period=0'

# Quick namespace switch
kns() { kubectl config set-context --current --namespace="$1"; echo "Namespace set to $1"; }

# Get events sorted
kevents() { kubectl get events --sort-by='.lastTimestamp' "$@"; }

export KUBECONFIG="$HOME/.kube/config-cka-simulator"

echo "CKA exam environment loaded."
echo "Clusters: k8s | hk8s | bk8s | wk8s"
echo "Switch:   kubectl config use-context <name>"
echo "Tip:      k get nodes --context=k8s"
ALIASES
    ok "Exam aliases written to $SCRIPT_DIR/.exam-env"
}

create_exam_namespaces() {
    step "Creating prerequisite namespaces and resources..."

    export KUBECONFIG="$HOME/.kube/config-cka-simulator"

    # k8s cluster namespaces
    for ns in app-team fubar audit ckad myspace ing-internal; do
        kubectl --context=k8s create namespace "$ns" 2>/dev/null || true
    done

    # wk8s cluster namespaces
    kubectl --context=wk8s create namespace kube-public 2>/dev/null || true

    ok "Namespaces created"

    # Run scenario init (pre-loads broken/pre-existing resources)
    if [ -f "$SCRIPT_DIR/scenarios/init-scenarios.sh" ]; then
        bash "$SCRIPT_DIR/scenarios/init-scenarios.sh"
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  Setup Complete!${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Clusters (matching real CKA exam context names):${NC}"
    echo -e "  ${GREEN}k8s${NC}   — Main cluster  (1 control-plane + 2 workers)"
    echo -e "  ${GREEN}hk8s${NC}  — HA cluster     (3 control-planes + 1 worker)"
    echo -e "  ${GREEN}bk8s${NC}  — Broken cluster (1 control-plane + 1 worker)"
    echo -e "  ${GREEN}wk8s${NC}  — Worker cluster (1 control-plane + 2 workers)"
    echo ""
    echo -e "${BOLD}Quick start:${NC}"
    echo -e "  source $SCRIPT_DIR/.exam-env"
    echo -e "  bash $SCRIPT_DIR/start-exam.sh      # 2-hour timed exam (17 tasks)"
    echo -e "  bash $SCRIPT_DIR/practice.sh         # Practice individual tasks"
    echo ""
    echo -e "${BOLD}Verify a task:${NC}"
    echo -e "  bash $SCRIPT_DIR/verify/verify-task-01.sh"
    echo ""
    echo -e "${BOLD}Tear down:${NC}"
    echo -e "  bash $SCRIPT_DIR/teardown.sh"
    echo ""
}

main() {
    header
    check_os
    echo ""
    check_prerequisites
    echo ""
    install_kind
    install_kubectl
    install_extras
    echo ""
    step "Creating 4 Kubernetes clusters..."
    echo ""
    create_cluster "k8s"
    create_cluster "hk8s"
    create_cluster "bk8s"
    create_cluster "wk8s"
    echo ""
    merge_kubeconfigs
    write_aliases
    create_exam_namespaces
    print_summary
}

main "$@"
