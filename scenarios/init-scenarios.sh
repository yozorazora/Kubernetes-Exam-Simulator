#!/bin/bash
# CKA Simulator — Scenario Initialization
# Pre-loads cluster state for tasks that require pre-existing resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[init]${NC} $1"; }
warn() { echo -e "${YELLOW}[init]${NC} $1"; }
step() { echo -e "${CYAN}[init]${NC} $1"; }

[ -z "${KUBECONFIG:-}" ] && export KUBECONFIG="$HOME/.kube/config-cka-simulator"

# ─── k8s cluster ────────────────────────────────────────────────────────────

init_k8s() {
    step "Initializing k8s cluster scenarios..."

    # Label the worker node with disk=ssd (Task 07)
    # Also label control-plane as fallback since cluster is slim (1 CP + 1 worker)
    WORKER=$(kubectl --context=k8s get nodes --selector='!node-role.kubernetes.io/control-plane' \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$WORKER" ]; then
        kubectl --context=k8s label node "$WORKER" disk=ssd --overwrite &>/dev/null
        ok "Labeled worker node '$WORKER' with disk=ssd (Task 07)"
    else
        # Fallback: label control-plane if no separate worker
        CP=$(kubectl --context=k8s get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        kubectl --context=k8s label node "$CP" disk=ssd --overwrite &>/dev/null
        ok "Labeled node '$CP' with disk=ssd (Task 07)"
    fi

    # Task 03: Create legacy-app pod with a volume for sidecar task
    kubectl --context=k8s create namespace audit 2>/dev/null || true
    cat <<EOF | kubectl --context=k8s apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
  namespace: audit
spec:
  containers:
  - name: count
    image: busybox:1.36
    command: ["/bin/sh", "-c", "i=0; while true; do echo \"\$i: \$(date)\" >> /var/log/legacy-app.log; sleep 1; i=\$((i+1)); done"]
    volumeMounts:
    - name: varlog
      mountPath: /var/log
  volumes:
  - name: varlog
    emptyDir: {}
EOF
    ok "Created legacy-app pod in namespace audit (Task 03)"

    # Task 08: Create service 'hi' in ing-internal namespace
    kubectl --context=k8s create namespace ing-internal 2>/dev/null || true
    cat <<EOF | kubectl --context=k8s apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: hello-app
  namespace: ing-internal
  labels:
    app: hi
spec:
  containers:
  - name: hello
    image: hashicorp/http-echo:latest
    args: ["-text=Hello from CKA simulator!"]
    ports:
    - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: hi
  namespace: ing-internal
spec:
  selector:
    app: hi
  ports:
  - port: 5678
    targetPort: 5678
EOF
    ok "Created service 'hi' in ing-internal namespace (Task 08)"

    # Task 08: Install NGINX ingress controller (kind provider)
    if ! kubectl --context=k8s get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
        step "Installing NGINX ingress controller for kind (Task 08)..."
        kubectl --context=k8s apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml &>/dev/null
        kubectl --context=k8s wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=120s &>/dev/null \
            && ok "NGINX ingress controller is ready (Task 08)" \
            || warn "NGINX ingress controller not yet ready — may need more time (Task 08)"
    else
        ok "NGINX ingress controller already installed (Task 08)"
    fi

    # Task 09: Create 'presentation' deployment in ckad namespace
    kubectl --context=k8s create namespace ckad 2>/dev/null || true
    cat <<EOF | kubectl --context=k8s apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: presentation
  namespace: ckad
spec:
  replicas: 1
  selector:
    matchLabels:
      app: presentation
  template:
    metadata:
      labels:
        app: presentation
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF
    ok "Created 'presentation' deployment in ckad namespace (Task 09)"

    # Task 13: Ensure myspace namespace exists
    kubectl --context=k8s create namespace myspace 2>/dev/null || true
    ok "Ensured namespace 'myspace' exists (Task 13)"

    # Task 05 Part B needs a pre-existing "previous" snapshot to restore from
    # (on the real exam it's already there). Create it here so it's present
    # even before the student ever runs the task's reset.
    CPNODE="k8s-control-plane"
    if docker inspect "$CPNODE" &>/dev/null; then
        docker exec "$CPNODE" mkdir -p /var/lib/backup 2>/dev/null
        if ! docker exec "$CPNODE" test -f /var/lib/backup/etcd-snapshot-previous.db 2>/dev/null; then
            if docker exec "$CPNODE" bash -c '
                export ETCDCTL_API=3
                etcdctl snapshot save /var/lib/backup/etcd-snapshot-previous.db \
                  --endpoints=https://127.0.0.1:2379 \
                  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                  --cert=/etc/kubernetes/pki/etcd/server.crt \
                  --key=/etc/kubernetes/pki/etcd/server.key
            ' &>/dev/null; then
                ok "Created /var/lib/backup/etcd-snapshot-previous.db (Task 05 Part B)"
            else
                warn "Could not create etcd-snapshot-previous.db (Task 05 Part B)"
            fi
        else
            ok "/var/lib/backup/etcd-snapshot-previous.db already present (Task 05 Part B)"
        fi
    fi
}

# ─── hk8s cluster ────────────────────────────────────────────────────────────

init_hk8s() {
    step "Initializing hk8s cluster scenarios..."

    # Task 02: Create namespaces fubar and internal
    kubectl --context=hk8s create namespace fubar 2>/dev/null || true
    kubectl --context=hk8s create namespace internal 2>/dev/null || true

    # Label 'internal' namespace so namespaceSelector works
    kubectl --context=hk8s label namespace internal kubernetes.io/metadata.name=internal --overwrite &>/dev/null
    kubectl --context=hk8s label namespace fubar kubernetes.io/metadata.name=fubar --overwrite &>/dev/null

    ok "Created namespaces fubar and internal (Task 02)"
}

# ─── bk8s cluster ────────────────────────────────────────────────────────────

init_bk8s() {
    step "Initializing bk8s cluster scenarios (broken resources)..."

    # Task 12: Create a broken deployment (wrong image)
    cat <<EOF | kubectl --context=bk8s apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-deployment
  template:
    metadata:
      labels:
        app: nginx-deployment
    spec:
      containers:
      - name: nginx
        image: nginx:broken-image-does-not-exist
EOF
    ok "Created broken nginx-deployment with invalid image (Task 12)"

    # Task 17: Stop kubelet on the worker node to make it NotReady
    WORKER_CONTAINER="bk8s-worker"
    if docker inspect "$WORKER_CONTAINER" &>/dev/null; then
        docker exec "$WORKER_CONTAINER" systemctl stop kubelet 2>/dev/null || true
        ok "Stopped kubelet on $WORKER_CONTAINER — node will become NotReady (Task 17)"
        warn "Task 17: Fix with: docker exec -it bk8s-worker bash → systemctl start kubelet"
    else
        warn "Could not find container $WORKER_CONTAINER for Task 17 setup"
    fi
}

# ─── wk8s cluster ────────────────────────────────────────────────────────────

init_wk8s() {
    step "Initializing wk8s cluster scenarios..."

    # Task 06: Ensure default namespace is available (it always is)
    ok "wk8s cluster ready for Tasks 06, 10, 16"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}${CYAN}Initializing exam scenarios across all clusters...${NC}"
    echo ""

    # Only init clusters that exist
    for cluster in k8s hk8s bk8s wk8s; do
        if kubectl config get-contexts "$cluster" &>/dev/null 2>&1; then
            "init_${cluster}" 2>/dev/null || warn "Some init steps failed for $cluster (may be OK)"
        else
            warn "Context '$cluster' not found — skipping"
        fi
    done

    echo ""
    ok "Scenario initialization complete."
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Task 17 has intentionally broken bk8s-worker (kubelet stopped)."
    echo -e "  ${YELLOW}Note:${NC} Task 12 has an intentionally broken deployment (bad image)."
    echo ""
}

main "$@"
