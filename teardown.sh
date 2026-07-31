#!/bin/bash
# CKA Simulator — Teardown: delete all clusters and clean up

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${YELLOW}${BOLD}CKA Simulator Teardown${NC}"
echo ""
echo "This will delete all 4 simulator clusters:"
echo "  k8s  |  hk8s  |  bk8s  |  wk8s"
echo ""
read -rp "Are you sure? [y/N] " confirm
[[ "$confirm" != [yY] ]] && echo "Cancelled." && exit 0

for cluster in k8s hk8s bk8s wk8s; do
    if kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
        echo -e "${YELLOW}Deleting cluster: $cluster${NC}"
        kind delete cluster --name "$cluster"
        echo -e "${GREEN}Deleted: $cluster${NC}"
    else
        echo "Cluster $cluster not found — skipping"
    fi
done

# Clean up kubeconfig files
for cluster in k8s hk8s bk8s wk8s; do
    rm -f "$HOME/.kube/cka-${cluster}.yaml"
done
rm -f "$HOME/.kube/config-cka-simulator"

echo ""
echo -e "${GREEN}All simulator clusters deleted. Run setup.sh to start fresh.${NC}"
