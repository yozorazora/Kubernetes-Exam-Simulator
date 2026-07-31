#!/bin/bash
# scenarios/reset.sh — Reset a single task back to its initial state
# Usage: bash scenarios/reset.sh <task-number>
#   e.g. bash scenarios/reset.sh 01

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "${KUBECONFIG:-}" ] && export KUBECONFIG="$HOME/.kube/config-cka-simulator"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }

TASK="$(printf '%02d' "$((10#${1:-0}))")"

echo ""
echo -e "${BOLD}${CYAN}Resetting Task ${TASK}...${NC}"
echo ""

# ── helpers ───────────────────────────────────────────────────────────────────

kd() { kubectl --context="$1" delete --ignore-not-found "$@" 2>/dev/null; }

wait_deleted() {
    local ctx=$1; shift
    kubectl --context="$ctx" wait --for=delete "$@" --timeout=30s 2>/dev/null || true
}

# ── Task resets ───────────────────────────────────────────────────────────────

reset_01() {
    info "Deleting ClusterRole, ServiceAccount, and RoleBinding (Task 01)..."
    kubectl --context=k8s delete clusterrole deployment-clusterrole --ignore-not-found 2>/dev/null \
        && ok "Deleted ClusterRole 'deployment-clusterrole'" || true
    kubectl --context=k8s delete serviceaccount cicd-token -n app-team --ignore-not-found 2>/dev/null \
        && ok "Deleted ServiceAccount 'cicd-token'" || true
    kubectl --context=k8s delete rolebinding -n app-team \
        $(kubectl --context=k8s get rolebinding -n app-team --no-headers 2>/dev/null \
          | awk '{print $1}') --ignore-not-found 2>/dev/null || true
    ok "Cleared any RoleBindings in app-team"
}

reset_02() {
    info "Deleting NetworkPolicy in fubar namespace (Task 02)..."
    kubectl --context=hk8s delete networkpolicy --all -n fubar --ignore-not-found 2>/dev/null \
        && ok "Deleted all NetworkPolicies in fubar" || true
}

reset_03() {
    info "Deleting and recreating legacy-app pod (Task 03)..."
    kubectl --context=k8s delete pod legacy-app -n audit --force --grace-period=0 --ignore-not-found 2>/dev/null
    sleep 2
    cat <<EOF | kubectl --context=k8s apply -f - 2>/dev/null
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
    ok "Recreated legacy-app with original single container (sidecar removed)"
}

reset_04() {
    local SCRIPT_ROOT
    SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local CLUSTER_CFG="$SCRIPT_ROOT/clusters/wk8s.yaml"
    local KUBECONFIG_FILE="$HOME/.kube/config-cka-simulator"

    info "Deleting wk8s cluster (this takes ~1-2 min)..."
    kind delete cluster --name wk8s 2>/dev/null && ok "Deleted wk8s cluster" || true

    info "Recreating wk8s cluster at v1.31.x (this takes ~2-5 min)..."
    if kind create cluster --config "$CLUSTER_CFG" --wait 180s 2>&1 | tail -3; then
        ok "Created wk8s cluster (control-plane: v1.31.x, worker: v1.32.x)"
    else
        fail "Failed to create wk8s cluster — check Docker and kind are running"
        return 1
    fi

    info "Merging kubeconfig..."
    local cfg="$HOME/.kube/cka-wk8s.yaml"
    kind get kubeconfig --name wk8s > "$cfg" 2>/dev/null
    sed -i "s/kind-wk8s/wk8s/g" "$cfg"

    # Re-merge all cluster configs into the combined kubeconfig
    local configs=()
    for name in k8s hk8s bk8s wk8s; do
        local f="$HOME/.kube/cka-${name}.yaml"
        [ -f "$f" ] && configs+=("$f")
    done
    if [ ${#configs[@]} -gt 0 ]; then
        KUBECONFIG=$(IFS=:; echo "${configs[*]}") kubectl config view --flatten > "$KUBECONFIG_FILE"
        ok "Kubeconfig merged: $KUBECONFIG_FILE"
    fi

    # Fresh kind node images have no Kubernetes apt repo configured at all, so
    # apt-get install kubeadm/kubelet/kubectl fails with "Unable to locate
    # package" regardless of version. Add the real pkgs.k8s.io repo so the
    # exam-accurate apt-mark/apt-get upgrade flow genuinely works each reset.
    info "Adding Kubernetes apt repo (pkgs.k8s.io) to wk8s-control-plane..."
    if docker exec -i wk8s-control-plane bash << 'REPO_SETUP'
set -e
apt-get update -qq
apt-get install -y -qq gnupg apt-transport-https ca-certificates >/dev/null
mkdir -p -m 755 /etc/apt/keyrings
# Task 04's target is always v1.32 (matches the worker's version and what
# verify-task-04.sh checks) — do NOT substitute a different minor even if
# it happens to be reachable; that silently breaks the task's version match.
CHOSEN="v1.32"
HTTP_CODE=$(curl -sL -o /tmp/k8s-key.asc -w "%{http_code}" "https://pkgs.k8s.io/core:/stable:/${CHOSEN}/deb/Release.key" || echo "000")
[ "$HTTP_CODE" != "200" ] && { echo "pkgs.k8s.io v1.32 repo unreachable (http $HTTP_CODE)"; exit 1; }
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg < /tmp/k8s-key.asc
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${CHOSEN}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
rm -f /tmp/k8s-key.asc
apt-get update -qq
echo "Repo added for $CHOSEN"
REPO_SETUP
    then
        ok "Kubernetes apt repo ready — apt-mark/apt-get kubeadm/kubelet/kubectl will work for real"
    else
        warn "Could not add Kubernetes apt repo (no internet access?) — apt-get install will still fail"
    fi

    ok "wk8s reset complete — control-plane is now v1.31.x"
    info "Run 'check' to confirm verify shows Failed (v1.32.x target not yet met)"
    info "Then practice: drain → upgrade kubeadm/kubelet → uncordon"
}

reset_05() {
    local CPNODE="k8s-control-plane"

    if ! docker inspect "$CPNODE" &>/dev/null; then
        fail "Container '$CPNODE' not found — is Docker Desktop running?"
        return 1
    fi

    # Remove snapshot so Part A can be redone
    if docker exec "$CPNODE" test -f /var/lib/backup/etcd-snapshot.db 2>/dev/null; then
        docker exec "$CPNODE" rm -f /var/lib/backup/etcd-snapshot.db 2>/dev/null \
            && ok "Removed /var/lib/backup/etcd-snapshot.db" \
            || fail "Could not remove snapshot file"
    else
        ok "No snapshot file present (already clean)"
    fi

    # Restore etcd manifest if Part B was completed (data-dir changed to etcd-restored)
    local DATA_DIR
    DATA_DIR=$(docker exec "$CPNODE" grep -- '--data-dir=' /etc/kubernetes/manifests/etcd.yaml 2>/dev/null | head -1)
    if echo "$DATA_DIR" | grep -q "etcd-restored"; then
        info "etcd manifest points to /var/lib/etcd-restored — restoring original..."
        docker exec "$CPNODE" bash -c "
            sed -i 's|--data-dir=/var/lib/etcd-restored|--data-dir=/var/lib/etcd|g' /etc/kubernetes/manifests/etcd.yaml
            sed -i 's|/var/lib/etcd-restored|/var/lib/etcd|g' /etc/kubernetes/manifests/etcd.yaml
        " 2>/dev/null && ok "Restored etcd manifest to use /var/lib/etcd" \
                      || fail "Could not restore etcd manifest — check manually"

        info "Waiting for etcd to restart (up to 60s)..."
        local retries=6
        while [ $retries -gt 0 ]; do
            if kubectl --context=k8s get nodes &>/dev/null 2>&1; then
                ok "Cluster is accessible again"
                break
            fi
            sleep 10
            ((retries--))
        done
        [ $retries -eq 0 ] && warn "Cluster may still be restarting — wait a moment before practicing"
    else
        ok "etcd manifest already uses /var/lib/etcd — no manifest change needed"
    fi

    # Clean up restored data dir if it exists
    if docker exec "$CPNODE" test -d /var/lib/etcd-restored 2>/dev/null; then
        docker exec "$CPNODE" rm -rf /var/lib/etcd-restored 2>/dev/null \
            && ok "Removed /var/lib/etcd-restored" \
            || warn "Could not remove /var/lib/etcd-restored — may need manual cleanup"
    fi

    # Ensure backup directory exists for Part A
    docker exec "$CPNODE" mkdir -p /var/lib/backup 2>/dev/null
    ok "Backup directory /var/lib/backup is ready"

    # Part B needs /var/lib/backup/etcd-snapshot-previous.db to already exist
    # (on the real exam it's pre-provided). Nothing else produces it, so
    # regenerate it here from the current — now-restored — etcd state.
    info "Preparing /var/lib/backup/etcd-snapshot-previous.db for Part B restore practice..."
    docker exec "$CPNODE" rm -f /var/lib/backup/etcd-snapshot-previous.db 2>/dev/null
    if docker exec "$CPNODE" bash -c '
        export ETCDCTL_API=3
        etcdctl snapshot save /var/lib/backup/etcd-snapshot-previous.db \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key
    ' &>/dev/null; then
        ok "Created /var/lib/backup/etcd-snapshot-previous.db"
    else
        fail "Could not create etcd-snapshot-previous.db — is etcd running/reachable?"
    fi

    info "Enter node with: docker exec -it k8s-control-plane bash"
    info "Then run: etcdctl snapshot save /var/lib/backup/etcd-snapshot.db ..."
}

reset_06() {
    info "Deleting PV and PVC (Task 06)..."
    kubectl --context=wk8s delete pvc pvc-app-config -n default --ignore-not-found 2>/dev/null \
        && ok "Deleted PVC 'pvc-app-config'" || true
    kubectl --context=wk8s patch pv app-config -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl --context=wk8s delete pv app-config --ignore-not-found 2>/dev/null \
        && ok "Deleted PV 'app-config'" || true
}

reset_07() {
    info "Deleting pod nginx-kusc00401 (Task 07)..."
    kubectl --context=k8s delete pod nginx-kusc00401 --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted pod 'nginx-kusc00401'" || true
    info "Node label disk=ssd is kept (it was there from setup)."
}

reset_08() {
    info "Deleting Ingress 'pong' in ing-internal (Task 08)..."
    kubectl --context=k8s delete ingress pong -n ing-internal --ignore-not-found 2>/dev/null \
        && ok "Deleted Ingress 'pong'" || true

    # Ensure ingress controller is present
    if ! kubectl --context=k8s get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
        info "NGINX ingress controller not found — installing..."
        kubectl --context=k8s apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml &>/dev/null
        kubectl --context=k8s wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=120s 2>/dev/null \
            && ok "NGINX ingress controller is ready" \
            || warn "Ingress controller not yet ready — wait a moment before testing"
    else
        ok "NGINX ingress controller already running"
    fi
}

reset_09() {
    info "Resetting 'presentation' deployment to original state (Task 09)..."
    kubectl --context=k8s delete deployment presentation -n ckad --ignore-not-found 2>/dev/null
    sleep 1
    cat <<EOF | kubectl --context=k8s apply -f - 2>/dev/null
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
    ok "Reset 'presentation' to 1 replica with no resource limits"
}

reset_10() {
    info "Cordoning wk8s-worker to simulate pre-task state (Task 10)..."
    kubectl --context=wk8s cordon wk8s-worker 2>/dev/null \
        && ok "Cordoned wk8s-worker — node is now unschedulable (check will fail)" \
        || fail "Could not cordon wk8s-worker — is the wk8s cluster running?"
    info "Practice: kubectl drain wk8s-worker --ignore-daemonsets --delete-emptydir-data"
    info "Then:     kubectl uncordon wk8s-worker"
}

reset_11() {
    info "Deleting pod kucc8 (Task 11)..."
    kubectl --context=k8s delete pod kucc8 --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted pod 'kucc8'" || true
}

reset_12() {
    info "Deleting nginx-deployment to clear all ReplicaSets (Task 12)..."
    kubectl --context=bk8s delete deployment nginx-deployment -n default \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted nginx-deployment (all old ReplicaSets removed)" \
        || { fail "Could not delete nginx-deployment — is the bk8s cluster running?"; return; }

    sleep 2

    info "Recreating nginx-deployment with broken image..."
    cat <<EOF | kubectl --context=bk8s apply -f - 2>/dev/null
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
    ok "Recreated nginx-deployment with broken image (nginx:broken-image-does-not-exist)"
    info "Pods will enter ImagePullBackOff shortly"
}

reset_13() {
    info "Deleting ResourceQuota in myspace (Task 13)..."
    kubectl --context=k8s delete resourcequota --all -n myspace --ignore-not-found 2>/dev/null \
        && ok "Deleted all ResourceQuotas in myspace" || true
}

reset_14() {
    info "Deleting ServiceAccount, ClusterRole, ClusterRoleBinding, Pod (Task 14)..."
    kubectl --context=k8s delete clusterrolebinding pvviewer-role-binding --ignore-not-found 2>/dev/null \
        && ok "Deleted ClusterRoleBinding 'pvviewer-role-binding'" || true
    kubectl --context=k8s delete clusterrole pvviewer-role --ignore-not-found 2>/dev/null \
        && ok "Deleted ClusterRole 'pvviewer-role'" || true
    kubectl --context=k8s delete serviceaccount pvviewer --ignore-not-found 2>/dev/null \
        && ok "Deleted ServiceAccount 'pvviewer'" || true
    kubectl --context=k8s delete pod pvviewer --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted Pod 'pvviewer'" || true
}

reset_15() {
    info "Deleting ConfigMap, Secret, and Pods (Task 15)..."
    kubectl --context=k8s delete pod configmap-pod --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted Pod 'configmap-pod'" || true
    kubectl --context=k8s delete configmap ckad-config --ignore-not-found 2>/dev/null \
        && ok "Deleted ConfigMap 'ckad-config'" || true
    kubectl --context=k8s delete pod secret-pod --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted Pod 'secret-pod'" || true
    kubectl --context=k8s delete secret ckad-secret --ignore-not-found 2>/dev/null \
        && ok "Deleted Secret 'ckad-secret'" || true
}

reset_16() {
    info "Deleting StorageClass and any related PVCs (Task 16)..."
    kubectl --context=wk8s delete pvc delayed-volume-pvc --ignore-not-found 2>/dev/null \
        && ok "Deleted PVC 'delayed-volume-pvc'" || true
    kubectl --context=wk8s delete pod test-pod --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted test Pod (if any)" || true
    kubectl --context=wk8s delete storageclass delayed-volume-sc --ignore-not-found 2>/dev/null \
        && ok "Deleted StorageClass 'delayed-volume-sc'" || true
}

reset_17() {
    info "Restoring bk8s-worker to healthy state (clears all Task 17 causes)..."
    if ! docker inspect bk8s-worker &>/dev/null; then
        fail "Container 'bk8s-worker' not found — is Docker Desktop running?"
        return 1
    fi

    # Ensure the kind load balancer container is running (if the bk8s cluster uses one)
    if docker inspect bk8s-external-load-balancer &>/dev/null; then
        LB_STATE=$(docker inspect --format '{{.State.Status}}' bk8s-external-load-balancer 2>/dev/null)
        if [ "$LB_STATE" != "running" ]; then
            info "Starting bk8s-external-load-balancer..."
            docker start bk8s-external-load-balancer 2>/dev/null || true
            sleep 5
        fi
    fi

    # Restore worker (causes 1, 2, 3, 5)
    docker exec -i bk8s-worker bash << 'INNER'
# Cause 5 cleanup: unmount tmpfs from /var/lib/kubelet if still mounted
if mount | grep -q " on /var/lib/kubelet type tmpfs"; then
    systemctl stop kubelet 2>/dev/null || true
    umount /var/lib/kubelet 2>/dev/null || true
fi
rm -f /var/lib/disk-fill-test   # legacy cause 5 fill file

[ -f /var/lib/kubelet/config.yaml.bak17 ] && {
    cp /var/lib/kubelet/config.yaml.bak17 /var/lib/kubelet/config.yaml
    rm -f /var/lib/kubelet/config.yaml.bak17
}
[ -f /etc/kubernetes/kubelet.conf.bak17 ] && {
    cp /etc/kubernetes/kubelet.conf.bak17 /etc/kubernetes/kubelet.conf
    rm -f /etc/kubernetes/kubelet.conf.bak17
}
systemctl start containerd 2>/dev/null || true
sleep 1
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet
INNER

    # New cause 4: restore kubelet.conf on control-plane
    if docker exec bk8s-control-plane test -f /etc/kubernetes/kubelet.conf.bak17c4 2>/dev/null; then
        info "Restoring bk8s-control-plane kubelet.conf (broken by cause 4)..."
        docker exec bk8s-control-plane bash -c '
            cp /etc/kubernetes/kubelet.conf.bak17c4 /etc/kubernetes/kubelet.conf
            rm /etc/kubernetes/kubelet.conf.bak17c4
            systemctl restart kubelet
        '
        local waited=0
        while [ $waited -lt 60 ]; do
            CP_STATUS=$(kubectl --context=bk8s get node bk8s-control-plane \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            [ "$CP_STATUS" = "True" ] && break
            sleep 5; waited=$((waited + 5))
        done
    fi

    # Legacy: clean up old apiserver.crt backup from previous sessions
    if docker exec bk8s-control-plane test -f /etc/kubernetes/pki/apiserver.crt.bak17 2>/dev/null; then
        info "Restoring bk8s-control-plane apiserver.crt (legacy backup)..."
        if kubectl --context=bk8s get nodes >/dev/null 2>&1; then
            docker exec bk8s-control-plane bash -c '
                cp /etc/kubernetes/pki/apiserver.crt.bak17 /etc/kubernetes/pki/apiserver.crt
                rm -f /etc/kubernetes/pki/apiserver.crt.bak17
                rm -f /etc/kubernetes/kubelet.conf.bak17
            '
        else
            docker exec -i bk8s-control-plane bash << 'CP_INNER'
cp /etc/kubernetes/pki/apiserver.crt.bak17 /etc/kubernetes/pki/apiserver.crt
rm -f /etc/kubernetes/pki/apiserver.crt.bak17
rm -f /etc/kubernetes/kubelet.conf.bak17
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-restore.yaml
sleep 8
mv /tmp/kube-apiserver-restore.yaml /etc/kubernetes/manifests/
CP_INNER
            local waited=0
            while [ $waited -lt 90 ]; do
                CP_STATUS=$(kubectl --context=bk8s get node bk8s-control-plane \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
                [ "$CP_STATUS" = "True" ] && break
                sleep 5; waited=$((waited + 5))
            done
        fi
    fi

    # If the kubelet.conf server address is unreachable, patch it to 127.0.0.1:6443
    docker exec -i bk8s-control-plane bash << 'CP_PATCH'
SERVER=$(awk '/server:/{print $2; exit}' /etc/kubernetes/kubelet.conf 2>/dev/null | sed 's|https://||')
if [ -n "$SERVER" ]; then
    HOST="${SERVER%:*}"; PORT="${SERVER##*:}"
    if ! timeout 3 bash -c ">/dev/tcp/$HOST/$PORT" 2>/dev/null; then
        if timeout 3 bash -c ">/dev/tcp/127.0.0.1/6443" 2>/dev/null; then
            sed -i "s|server: https://[^:]*:[0-9]*|server: https://127.0.0.1:6443|" /etc/kubernetes/kubelet.conf
            echo "Patched kubelet.conf: $HOST:$PORT → 127.0.0.1:6443"
        fi
    fi
fi
CP_PATCH

    docker exec bk8s-control-plane systemctl restart kubelet 2>/dev/null || true
    local cp_waited=0
    while [ $cp_waited -lt 90 ]; do
        CP_STATUS=$(kubectl --context=bk8s get node bk8s-control-plane \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        [ "$CP_STATUS" = "True" ] && { ok "Control-plane is Ready"; break; }
        sleep 5; cp_waited=$((cp_waited + 5))
    done
    [ "$CP_STATUS" != "True" ] && warn "Control-plane may still be coming up — check: docker exec -it bk8s-control-plane bash"

    info "Waiting for bk8s-worker to become Ready (up to 60s)..."
    local waited=0
    while [ $waited -lt 60 ]; do
        local cond
        cond=$(kubectl --context=bk8s get node bk8s-worker \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$cond" = "True" ]; then
            ok "Node bk8s-worker is Ready"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        printf "  . waited %ds\n" "$waited"
    done

    [ $waited -ge 60 ] && warn "Node may still be coming up — wait a moment"

    # Clear per-cause progress tracking so student starts fresh
    rm -f /tmp/cka17-active /tmp/cka17-done

    echo ""
    ok "Node restored to healthy state. Progress tracking cleared."
    info "Use 'cause <1-5>' in the task shell to begin practicing each cause."
}

reset_18() {
    info "Cleaning up task18 namespace (pod, PVC, ConfigMaps, Secret)..."

    kubectl --context=k8s delete pod task18-pod -n task18 \
        --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted pod 'task18-pod'" || true
    kubectl --context=k8s delete pvc task18-pvc -n task18 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted PVC 'task18-pvc'" || true
    kubectl --context=k8s delete configmap task18-config-vol task18-env-config \
        -n task18 --ignore-not-found 2>/dev/null \
        && ok "Deleted ConfigMaps" || true
    kubectl --context=k8s delete secret task18-env-secret \
        -n task18 --ignore-not-found 2>/dev/null \
        && ok "Deleted Secret 'task18-env-secret'" || true

    # Clear per-cause progress tracking
    rm -f /tmp/cka18-active /tmp/cka18-done
    ok "Progress tracking cleared."
    info "Use 'cause <1-10>' in the task shell to begin practicing each cause."
}

reset_19() {
    CP="bk8s-control-plane"

    if ! docker inspect "$CP" &>/dev/null; then
        fail "Container '$CP' not found — is the bk8s cluster running?"
        return 1
    fi

    info "Restoring all Task 19 control plane manifests to clean state..."

    docker exec -i "$CP" bash << 'INNER'
MANIFEST_DIR="/etc/kubernetes/manifests"
PKI_DIR="/etc/kubernetes/pki"

for bak_file in "$PKI_DIR"/kube-*.yaml.bak19c*; do
    [ -f "$bak_file" ] || continue
    base=$(basename "$bak_file")
    orig_name="${base%.bak19c*}"
    cp "$bak_file" "$MANIFEST_DIR/$orig_name"
    rm -f "$bak_file"
    echo "  Restored $orig_name"
done
INNER

    ok "Manifests restored"

    info "Waiting for kube-apiserver to be reachable (up to 90s)..."
    local waited=0
    while [ $waited -lt 90 ]; do
        if kubectl --context=bk8s get nodes --request-timeout=5s &>/dev/null 2>&1; then
            ok "kube-apiserver is accessible"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        printf "  . waited %ds\n" "$waited"
    done
    [ $waited -ge 90 ] && warn "API server may still be starting"

    info "Waiting for scheduler and controller-manager (up to 60s)..."
    local waited2=0
    while [ $waited2 -lt 60 ]; do
        SCHED=$(kubectl --context=bk8s get pods -n kube-system -l component=kube-scheduler \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        CM=$(kubectl --context=bk8s get pods -n kube-system -l component=kube-controller-manager \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        [ "$SCHED" = "Running" ] && [ "$CM" = "Running" ] && break
        sleep 5; waited2=$((waited2 + 5))
    done
    [ "$SCHED" = "Running" ] && ok "kube-scheduler is Running" || warn "kube-scheduler may still be starting"
    [ "$CM"    = "Running" ] && ok "kube-controller-manager is Running" || warn "kube-controller-manager may still be starting"

    rm -f /tmp/cka19-active /tmp/cka19-done
    ok "Progress tracking cleared."
    info "Use 'cause <1-4>' in the task shell to begin practicing each cause."
}

reset_20() {
    info "Cleaning up task20 resources (pods, services) and restoring CoreDNS..."

    # Restore CoreDNS if it was scaled down by cause 3
    local coredns_replicas=2
    [ -f /tmp/cka20-coredns-replicas ] && \
        coredns_replicas=$(cat /tmp/cka20-coredns-replicas 2>/dev/null)
    local current
    current=$(kubectl --context=k8s get deployment coredns -n kube-system \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "${current:-2}" -eq 0 ]; then
        info "Scaling CoreDNS back to ${coredns_replicas} replica(s)..."
        kubectl --context=k8s scale deployment coredns \
            -n kube-system --replicas="${coredns_replicas}" 2>/dev/null \
            && ok "CoreDNS scaled to ${coredns_replicas}" || true
        kubectl --context=k8s wait pods -n kube-system -l k8s-app=kube-dns \
            --for=condition=Ready --timeout=60s 2>/dev/null || true
    fi
    rm -f /tmp/cka20-coredns-replicas

    kubectl --context=k8s -n task20 delete pod task20-server task20-client \
        --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted pods" || true
    kubectl --context=k8s -n task20 delete svc task20-svc \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted service in task20" || true
    kubectl --context=k8s -n default delete svc task20-svc \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted service in default (if present)" || true

    rm -f /tmp/cka20-active /tmp/cka20-done
    ok "Progress tracking cleared."
    info "Use 'cause <1-5>' in the task shell to begin practicing each cause."
}

reset_21() {
    info "Cleaning up task21 resources (taint, pods, namespace)..."

    # Discover worker node and remove taint
    local worker
    worker=$(kubectl --context=k8s get nodes --no-headers 2>/dev/null \
        | grep -v "control-plane\|master" | head -1 | awk '{print $1}')

    if [ -n "$worker" ]; then
        # Remove taint if present (the trailing '-' removes it)
        kubectl --context=k8s taint node "$worker" dedicated=blue:NoSchedule- \
            &>/dev/null \
            && ok "Removed taint dedicated=blue:NoSchedule from '$worker'" || true
    fi

    kubectl --context=k8s -n task21 delete pod pod-no-toleration pod-tolerant \
        --force --grace-period=0 --ignore-not-found 2>/dev/null \
        && ok "Deleted task21 pods" || true

    ok "Task 21 reset complete — ready to practice again."
}

reset_22() {
    info "Cleaning up task22 namespace (job, cronjob, pods)..."

    kubectl --context=k8s delete namespace task22 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task22 (and all resources inside)" || true

    ok "Task 22 reset complete — ready to practice again."
}

reset_23() {
    info "Cleaning up task23 output files..."

    rm -f /tmp/task23-node-ips.txt \
           /tmp/task23-kube-system-pods.txt \
           /tmp/task23-apiserver-image.txt \
           /tmp/task23-pod-status.txt \
        && ok "Removed /tmp/task23-*.txt files" || true

    ok "Task 23 reset complete — ready to practice again."
}

reset_24() {
    info "Cleaning up task24 Helm release and namespace..."

    if command -v helm &>/dev/null; then
        helm uninstall task24-nginx --namespace task24 2>/dev/null \
            && ok "Uninstalled Helm release task24-nginx" || true

        helm repo remove bitnami 2>/dev/null \
            && ok "Removed bitnami Helm repo (re-add it to re-practice Part A)" || true
    fi

    kubectl --context=k8s delete namespace task24 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task24" || true

    ok "Task 24 reset complete — ready to practice again."
}

reset_25() {
    info "Cleaning up task25 CRD and custom resources..."

    kubectl --context=k8s delete namespace task25 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task25 (and all Backup resources inside)" || true

    kubectl --context=k8s delete crd backups.storage.example.com \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted CRD backups.storage.example.com" || true

    ok "Task 25 reset complete — ready to practice again."
}

reset_26() {
    info "Cleaning up task26 DaemonSet and namespace..."

    kubectl --context=k8s delete namespace task26 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task26 (and DaemonSet inside)" || true

    ok "Task 26 reset complete — ready to practice again."
}

reset_27() {
    info "Cleaning up task27 Gateway API resources and namespace..."

    kubectl --context=k8s delete httproute task27-route -n task27 \
        --ignore-not-found 2>/dev/null || true
    kubectl --context=k8s delete gateway task27-gateway -n task27 \
        --ignore-not-found 2>/dev/null || true
    kubectl --context=k8s delete gatewayclass task27-gwc \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted GatewayClass task27-gwc" || true
    kubectl --context=k8s delete namespace task27 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task27" || true

    ok "Task 27 reset complete — ready to practice again."
    info "Note: Gateway API CRDs are kept installed (cluster-wide resource)."
}

reset_28() {
    info "Cleaning up task28 HPA, Deployment, and namespace..."

    kubectl --context=k8s delete namespace task28 \
        --ignore-not-found 2>/dev/null \
        && ok "Deleted namespace task28 (HPA + Deployment inside)" || true

    ok "Task 28 reset complete — ready to practice again."
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "$TASK" in
    01) reset_01 ;;
    02) reset_02 ;;
    03) reset_03 ;;
    04) reset_04 ;;
    05) reset_05 ;;
    06) reset_06 ;;
    07) reset_07 ;;
    08) reset_08 ;;
    09) reset_09 ;;
    10) reset_10 ;;
    11) reset_11 ;;
    12) reset_12 ;;
    13) reset_13 ;;
    14) reset_14 ;;
    15) reset_15 ;;
    16) reset_16 ;;
    17) reset_17 ;;
    18) reset_18 ;;
    19) reset_19 ;;
    20) reset_20 ;;
    21) reset_21 ;;
    22) reset_22 ;;
    23) reset_23 ;;
    24) reset_24 ;;
    25) reset_25 ;;
    26) reset_26 ;;
    27) reset_27 ;;
    28) reset_28 ;;
    *)
        echo -e "${RED}Unknown task number: $TASK${NC}"
        echo "Usage: bash reset.sh <01-28>"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}${BOLD}Task ${TASK} reset complete.${NC}"
echo ""
