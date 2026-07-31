#!/bin/bash
# Task 17 — Break a node with a specific root cause for practice
# Usage: bash setup-task-17-cause.sh <1-5>

CAUSE="${1:-}"
WORKER="bk8s-worker"
CP="bk8s-control-plane"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }

if ! docker inspect "$WORKER" &>/dev/null; then
    fail "Container '$WORKER' not found — is Docker Desktop running?"
    exit 1
fi

# Which node will be broken — causes 1/2/3/5 break the worker,
# cause 4 breaks the control-plane. Set per cause function.
BROKEN_NODE="$WORKER"

# ── Restore all nodes to clean healthy state before applying a new cause ───────

restore_clean() {
    info "Restoring nodes to clean state..."

    # Ensure the kind load balancer container is running (if the bk8s cluster uses one)
    if docker inspect bk8s-external-load-balancer &>/dev/null; then
        LB_STATE=$(docker inspect --format '{{.State.Status}}' bk8s-external-load-balancer 2>/dev/null)
        if [ "$LB_STATE" != "running" ]; then
            info "Starting bk8s-external-load-balancer..."
            docker start bk8s-external-load-balancer 2>/dev/null || true
            sleep 5
        fi
    fi

    # Restore worker
    docker exec -i "$WORKER" bash << 'INNER'
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
systemctl start kubelet 2>/dev/null || true
INNER

    # New cause 4: restore kubelet.conf on control-plane (kubelet client cert scenario)
    if docker exec "$CP" test -f /etc/kubernetes/kubelet.conf.bak17c4 2>/dev/null; then
        info "Restoring bk8s-control-plane kubelet.conf (was broken by cause 4)..."
        docker exec "$CP" bash -c '
            cp /etc/kubernetes/kubelet.conf.bak17c4 /etc/kubernetes/kubelet.conf
            rm /etc/kubernetes/kubelet.conf.bak17c4
            systemctl restart kubelet
        '
        local waited=0
        while [ $waited -lt 60 ]; do
            CP_STATUS=$(kubectl --context=bk8s get node "$CP" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            [ "$CP_STATUS" = "True" ] && break
            sleep 5; waited=$((waited + 5))
        done
    fi

    # Legacy: clean up old apiserver.crt backup if present from a previous session
    if docker exec "$CP" test -f /etc/kubernetes/pki/apiserver.crt.bak17 2>/dev/null; then
        info "Restoring bk8s-control-plane apiserver.crt (legacy backup)..."
        if kubectl --context=bk8s get nodes >/dev/null 2>&1; then
            docker exec "$CP" bash -c '
                cp /etc/kubernetes/pki/apiserver.crt.bak17 /etc/kubernetes/pki/apiserver.crt
                rm -f /etc/kubernetes/pki/apiserver.crt.bak17
                rm -f /etc/kubernetes/kubelet.conf.bak17
            '
        else
            docker exec -i "$CP" bash << 'CP_INNER'
cp /etc/kubernetes/pki/apiserver.crt.bak17 /etc/kubernetes/pki/apiserver.crt
rm -f /etc/kubernetes/pki/apiserver.crt.bak17
rm -f /etc/kubernetes/kubelet.conf.bak17
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-restore.yaml
sleep 8
mv /tmp/kube-apiserver-restore.yaml /etc/kubernetes/manifests/
CP_INNER
            local waited=0
            while [ $waited -lt 90 ]; do
                CP_STATUS=$(kubectl --context=bk8s get node "$CP" \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
                [ "$CP_STATUS" = "True" ] && break
                sleep 5; waited=$((waited + 5))
            done
        fi
    fi

    # If the kubelet.conf server address is unreachable (e.g. the kind load balancer
    # container was removed or got a new IP), patch it to 127.0.0.1:6443 so the
    # control-plane kubelet can reach its own local API server.
    docker exec -i "$CP" bash << 'CP_PATCH'
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

    docker exec "$CP" systemctl restart kubelet 2>/dev/null || true
    local cp_waited=0
    while [ $cp_waited -lt 90 ]; do
        CP_STATUS=$(kubectl --context=bk8s get node "$CP" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        [ "$CP_STATUS" = "True" ] && { ok "Control-plane is Ready"; break; }
        sleep 5; cp_waited=$((cp_waited + 5))
    done
    [ "$CP_STATUS" != "True" ] && warn "Control-plane is still NotReady — check with: docker exec -it $CP bash"

    ok "Nodes restored to clean state"
}

# ── Cause 1: kubelet service stopped ──────────────────────────────────────────

cause_1() {
    BROKEN_NODE="$WORKER"
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 1: kubelet service stopped ━━━━━━━━━━━━━━━━━${NC}"
    restore_clean
    docker exec "$WORKER" systemctl stop kubelet 2>/dev/null \
        && ok "Stopped kubelet on $WORKER" \
        || { fail "Could not stop kubelet"; exit 1; }
    echo ""
    echo -e "  ${BOLD}Node affected:${NC} $WORKER"
    echo -e "  ${BOLD}SSH in:${NC}        ${CYAN}docker exec -it $WORKER bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}sudo systemctl status kubelet${NC}  →  Active: inactive (dead)"
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sudo systemctl start kubelet${NC}"
    echo -e "  ${GREEN}sudo systemctl enable kubelet${NC}"
    echo ""
}

# ── Cause 2: containerd runtime stopped ───────────────────────────────────────

cause_2() {
    BROKEN_NODE="$WORKER"
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 2: containerd runtime stopped ━━━━━━━━━━━━━━${NC}"
    restore_clean
    docker exec -i "$WORKER" bash << 'INNER'
systemctl stop containerd
systemctl stop kubelet
INNER
    ok "Stopped containerd and kubelet on $WORKER"
    echo ""
    echo -e "  ${BOLD}Node affected:${NC} $WORKER"
    echo -e "  ${BOLD}SSH in:${NC}        ${CYAN}docker exec -it $WORKER bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}sudo systemctl status containerd${NC}  →  Active: inactive (dead)"
    echo -e "  ${YELLOW}sudo journalctl -u kubelet | grep -i 'rpc\\|connection'${NC}"
    echo -e "  → \"rpc error: code = Unavailable desc = connection refused\""
    echo ""
    echo -e "  ${BOLD}Fix:${NC}"
    echo -e "  ${GREEN}sudo systemctl start containerd && sudo systemctl enable containerd${NC}"
    echo -e "  ${GREEN}sudo systemctl restart kubelet${NC}"
    echo ""
}

# ── Cause 3: kubelet config file error ────────────────────────────────────────

cause_3() {
    BROKEN_NODE="$WORKER"
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 3: kubelet config file error ━━━━━━━━━━━━━━━${NC}"
    restore_clean
    docker exec -i "$WORKER" bash << 'INNER'
cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak17
printf '\nINVALID_YAML_ENTRY: [unclosed\n' >> /var/lib/kubelet/config.yaml
systemctl restart kubelet 2>/dev/null || true
INNER
    ok "Corrupted /var/lib/kubelet/config.yaml on $WORKER"
    info "Backup at: /var/lib/kubelet/config.yaml.bak17"
    echo ""
    echo -e "  ${BOLD}Node affected:${NC} $WORKER"
    echo -e "  ${BOLD}SSH in:${NC}        ${CYAN}docker exec -it $WORKER bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}sudo systemctl status kubelet${NC}  →  Active: failed (Result: exit-code)"
    echo -e "  ${YELLOW}sudo journalctl -u kubelet -xe | grep -i error${NC}"
    echo -e "  → \"failed to load Kubelet config file\" / \"yaml: line X: did not find\""
    echo ""
    echo -e "  ${BOLD}Fix A — edit out the bad line:${NC}"
    echo -e "  ${GREEN}sudo vi /var/lib/kubelet/config.yaml${NC}"
    echo -e "  ${GREEN}sudo systemctl daemon-reload && sudo systemctl restart kubelet${NC}"
    echo ""
    echo -e "  ${BOLD}Fix B — restore from backup:${NC}"
    echo -e "  ${GREEN}sudo cp /var/lib/kubelet/config.yaml.bak17 /var/lib/kubelet/config.yaml${NC}"
    echo -e "  ${GREEN}sudo systemctl daemon-reload && sudo systemctl restart kubelet${NC}"
    echo ""
}

# ── Cause 4: certificate expired ──────────────────────────────────────────────
# Breaks the kubelet CLIENT cert embedded in /etc/kubernetes/kubelet.conf on
# bk8s-control-plane. kubelet cannot authenticate to the API server →
# bk8s-control-plane goes NotReady. kube-apiserver (static pod) keeps running,
# so kubectl get nodes still works from outside.
# Fix: kubeadm certs renew all (renews kubelet.conf cert) + systemctl restart kubelet.

cause_4() {
    BROKEN_NODE="$CP"
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 4: certificate expired ━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! docker inspect "$CP" &>/dev/null; then
        fail "Container '$CP' not found — is bk8s cluster running?"
        exit 1
    fi

    restore_clean
    info "Replacing kubelet client cert in kubelet.conf with an expired cert on $CP..."

    docker exec -i "$CP" bash << 'CP_INNER'
set -e

# Backup current kubelet.conf
cp /etc/kubernetes/kubelet.conf /etc/kubernetes/kubelet.conf.bak17c4

# Generate an expired kubelet client cert signed by the cluster CA
mkdir -p /tmp/exp-kbl/newcerts
touch /tmp/exp-kbl/index.txt
echo '1000' > /tmp/exp-kbl/serial

openssl genrsa -out /tmp/exp-kbl/kubelet.key 2048 2>/dev/null
openssl req -new -key /tmp/exp-kbl/kubelet.key \
    -subj "/O=system:nodes/CN=system:node:bk8s-control-plane" \
    -out /tmp/exp-kbl/kubelet.csr 2>/dev/null

cat > /tmp/exp-kbl/openssl.cnf << 'CACONF'
[ ca ]
default_ca = E
[ E ]
certificate   = /etc/kubernetes/pki/ca.crt
private_key   = /etc/kubernetes/pki/ca.key
new_certs_dir = /tmp/exp-kbl/newcerts
database      = /tmp/exp-kbl/index.txt
serial        = /tmp/exp-kbl/serial
policy        = P
default_md    = sha256
x509_extensions = kubelet_ext
[ P ]
commonName       = supplied
organizationName = supplied
[ kubelet_ext ]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
CACONF

openssl ca -config /tmp/exp-kbl/openssl.cnf \
    -in /tmp/exp-kbl/kubelet.csr \
    -out /tmp/exp-kbl/kubelet.crt \
    -startdate 20200101000000Z \
    -enddate 20201231235959Z \
    -batch 2>/dev/null

[ -s /tmp/exp-kbl/kubelet.crt ] || { echo "ERROR: cert generation failed"; exit 1; }
echo "--- expired cert dates ---"
openssl x509 -in /tmp/exp-kbl/kubelet.crt -noout -dates

# Embed expired cert + key into kubelet.conf
python3 - << 'PYEOF'
import base64, re
with open('/tmp/exp-kbl/kubelet.crt', 'rb') as f:
    cert_b64 = base64.b64encode(f.read()).decode()
with open('/tmp/exp-kbl/kubelet.key', 'rb') as f:
    key_b64 = base64.b64encode(f.read()).decode()
with open('/etc/kubernetes/kubelet.conf', 'r') as f:
    conf = f.read()
conf = re.sub(r'client-certificate-data:.*', f'client-certificate-data: {cert_b64}', conf)
conf = re.sub(r'client-key-data:.*', f'client-key-data: {key_b64}', conf)
with open('/etc/kubernetes/kubelet.conf', 'w') as f:
    f.write(conf)
print("kubelet.conf updated with expired certificate")
PYEOF

rm -rf /tmp/exp-kbl
systemctl restart kubelet
echo "DONE"
CP_INNER

    local RC=$?
    if [ $RC -ne 0 ]; then
        fail "Cause 4 setup failed (exit $RC) — see output above"
        exit 1
    fi

    if ! docker exec "$CP" test -f /etc/kubernetes/kubelet.conf.bak17c4 2>/dev/null; then
        fail "Backup not found — setup likely failed silently"
        exit 1
    fi

    ok "Installed expired kubelet client cert on $CP"
    info "kube-apiserver static pod keeps running — API server stays UP"
    info "Backup: /etc/kubernetes/kubelet.conf.bak17c4 (inside $CP)"
    echo ""
    echo -e "  ${BOLD}Node affected:${NC} $CP  ${YELLOW}(kube-apiserver still runs — it is a static pod)${NC}"
    echo -e "  ${BOLD}SSH in:${NC}         ${CYAN}docker exec -it $CP bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}sudo systemctl status kubelet${NC}  →  Active: activating (auto-restart)"
    echo -e "  ${YELLOW}sudo journalctl -u kubelet | grep -i 'expired\\|bootstrap'${NC}"
    echo -e "  → \"bootstrap client certificate in /etc/kubernetes/kubelet.conf is expired\""
    echo -e "  → \"unable to load bootstrap kubeconfig\""
    echo ""
    echo -e "  ${BOLD}Fix (run on bk8s-control-plane):${NC}"
    echo -e "  ${GREEN}sudo rm /etc/kubernetes/kubelet.conf${NC}                   ${YELLOW}# remove expired conf (kubeadm won't overwrite)${NC}"
    echo -e "  ${GREEN}sudo kubeadm init phase kubeconfig kubelet${NC}             ${YELLOW}# regenerate with new valid cert${NC}"
    echo -e "  ${GREEN}sudo systemctl restart kubelet${NC}                         ${YELLOW}# picks up the new cert${NC}"
    echo ""
}

# ── Cause 5: disk full ────────────────────────────────────────────────────────

cause_5() {
    BROKEN_NODE="$WORKER"
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Setting up Cause 5: disk full ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    restore_clean
    warn "Mounting 200 MB tmpfs over /var/lib/kubelet and filling it — takes ~5 seconds..."
    docker exec -i "$WORKER" bash << 'INNER'
set -e

# Copy essential kubelet files before the mount hides them
mkdir -p /tmp/kbl-ess/pki
cp /var/lib/kubelet/config.yaml           /tmp/kbl-ess/ 2>/dev/null || true
cp /var/lib/kubelet/kubeadm-flags.env     /tmp/kbl-ess/ 2>/dev/null || true
cp -aL /var/lib/kubelet/pki/.             /tmp/kbl-ess/pki/ 2>/dev/null || true

# Stop kubelet, then mount a tiny tmpfs over its data dir
systemctl stop kubelet 2>/dev/null || true
mount -t tmpfs -o size=200m tmpfs /var/lib/kubelet

# Restore essential files onto the tmpfs so kubelet can at least try to start
cp /tmp/kbl-ess/config.yaml       /var/lib/kubelet/ 2>/dev/null || true
cp /tmp/kbl-ess/kubeadm-flags.env /var/lib/kubelet/ 2>/dev/null || true
mkdir -p /var/lib/kubelet/pki
cp -a /tmp/kbl-ess/pki/.          /var/lib/kubelet/pki/ 2>/dev/null || true
rm -rf /tmp/kbl-ess

# Fill the tmpfs completely
dd if=/dev/zero of=/var/lib/kubelet/disk-fill.img bs=1M 2>/dev/null || true

# Start kubelet briefly so journalctl captures the "no space" error
systemctl start kubelet 2>/dev/null || true
sleep 4
# Then stop it — crash loop keeps heartbeating and the node never goes NotReady otherwise
systemctl stop kubelet 2>/dev/null || true
echo DONE
INNER

    ok "Mounted 200 MB tmpfs at /var/lib/kubelet (100% full) on $WORKER"
    info "kubelet stopped after brief crash — node will be NotReady in ~40s"
    echo ""
    echo -e "  ${BOLD}Node affected:${NC} $WORKER"
    echo -e "  ${BOLD}SSH in:${NC}        ${CYAN}docker exec -it $WORKER bash${NC}"
    echo ""
    echo -e "  ${BOLD}Symptom:${NC}"
    echo -e "  ${YELLOW}df -h${NC}"
    echo -e "  → tmpfs   200M  200M     0 100%  /var/lib/kubelet"
    echo -e "  ${YELLOW}sudo systemctl status kubelet${NC}  →  Active: inactive (dead)"
    echo -e "  ${YELLOW}sudo systemctl start kubelet && sleep 2 && systemctl status kubelet${NC}"
    echo -e "  → starts then crashes again  (exit-code) — disk is still full"
    echo -e "  ${YELLOW}sudo journalctl -u kubelet | grep -i 'space'${NC}"
    echo -e "  → \"no space left on device\""
    echo ""
    echo -e "  ${BOLD}Fix (inside bk8s-worker):${NC}"
    echo -e "  ${GREEN}sudo du -sh /var/lib/kubelet/* | sort -rh | head${NC}   ${YELLOW}# find the large file${NC}"
    echo -e "  ${GREEN}sudo journalctl --vacuum-time=2d${NC}                   ${YELLOW}# free journal space${NC}"
    echo -e "  ${GREEN}sudo crictl rmi --prune${NC}                            ${YELLOW}# free unused images${NC}"
    echo -e "  ${GREEN}sudo rm /var/lib/kubelet/disk-fill.img${NC}             ${YELLOW}# remove fill file${NC}"
    echo -e "  ${GREEN}sudo systemctl restart kubelet${NC}"
    echo ""
}

# ── Main dispatch ──────────────────────────────────────────────────────────────

case "$CAUSE" in
    1) cause_1 ;;
    2) cause_2 ;;
    3) cause_3 ;;
    4) cause_4 ;;
    5) cause_5 ;;
    *)
        echo ""
        echo -e "${BOLD}Task 17 — Choose a root cause to practice:${NC}"
        echo ""
        echo -e "  ${CYAN}cause 1${NC}  kubelet service stopped          ${YELLOW}(Most common, ~90% of exams)${NC}"
        echo -e "  ${CYAN}cause 2${NC}  containerd runtime stopped        ${YELLOW}→ bk8s-worker${NC}"
        echo -e "  ${CYAN}cause 3${NC}  kubelet config file error         ${YELLOW}→ bk8s-worker${NC}"
        echo -e "  ${CYAN}cause 4${NC}  Certificate expired               ${YELLOW}→ bk8s-control-plane${NC}"
        echo -e "  ${CYAN}cause 5${NC}  Disk full                         ${YELLOW}→ bk8s-worker${NC}"
        echo ""
        echo -e "  Usage: ${YELLOW}cause <1-5>${NC}  inside the task-17 shell"
        echo ""
        exit 1
        ;;
esac

# Record active cause for progress tracking in verify-task-17.sh
echo "$CAUSE" > /tmp/cka17-active

info "Waiting for $BROKEN_NODE to become NotReady (up to 90s)..."
waited=0
while [ "$waited" -lt 90 ]; do
    cond=$(kubectl --context=bk8s get node "$BROKEN_NODE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$cond" != "True" ]; then
        ok "Node $BROKEN_NODE is NotReady — scenario is live"
        break
    fi
    sleep 5
    waited=$((waited + 5))
    printf "  . %ds elapsed\n" "$waited"
done
[ "$waited" -ge 90 ] && warn "Node may still show Ready — Kubernetes takes ~40s to detect NotReady"

echo ""
echo -e "${BOLD}${YELLOW}  $BROKEN_NODE is NotReady. SSH in with: docker exec -it $BROKEN_NODE bash${NC}"
echo -e "  Diagnose → fix → run ${CYAN}check${NC} to verify → ${CYAN}cause <N>${NC} for next scenario."
echo ""
